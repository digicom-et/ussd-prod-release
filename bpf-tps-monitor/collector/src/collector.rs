//! AF_PACKET raw-socket capture, classic-BPF filter, and SCTP/M3UA parsing.
//!
//! The reader task is *blocking* on purpose: `AF_PACKET` is a synchronous
//! kernel API and we'd rather burn one OS thread than pay an extra copy
//! through userspace ring buffers (which require `CAP_NET_RAW` + `mmap`).

use std::os::fd::AsRawFd;
use std::os::unix::io::RawFd;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use socket2::{Domain, Protocol, Socket, Type};
use tracing::{debug, info, warn};

use crate::metrics::{Direction, M3uaClass, Metrics};

// -----------------------------------------------------------------------------
// Classic BPF program — keep only IPv4/SCTP (proto 132) frames.
//
// BPF jump offsets are RELATIVE to the instruction AFTER the jump
// (i.e. `pc_after = pc + 1 + jt` or `pc + 1 + jf`). When `pc_after` exceeds
// the program length the kernel returns 0 (drop), which we use as the
// fall-through drop path.
//
// Layout:
//   0: ldh  [12]                 ; load EtherType
//   1: jeq  #0x800  jt 1 jf 6    ; IPv4?  true ->3;  false ->8 (drop)
//   2: ret  #0                   ; (unreachable safety)
//   3: ldb  [23]                 ; load IP-proto byte
//   4: jeq  #132   jt 1 jf 3    ; SCTP?  true ->6 (accept);  false ->8 (drop)
//   5: ret  #0                   ; (unreachable safety)
//   6: ret  #262144              ; accept
// -----------------------------------------------------------------------------
const BPF_INSTRUCTIONS: &[libc::sock_filter] = &[
    // 0: ldh [12]
    libc::sock_filter { code: 0x28, jt: 0, jf: 0, k: 12 },
    // 1: jeq #0x800  jt +1 ->[3]  jf +6 ->[8 OOB=drop]
    libc::sock_filter { code: 0x15, jt: 1, jf: 6, k: 0x800 },
    // 2: ret #0  (unreachable safety)
    libc::sock_filter { code: 0x06, jt: 0, jf: 0, k: 0 },
    // 3: ldb [23]
    libc::sock_filter { code: 0x30, jt: 0, jf: 0, k: 23 },
    // 4: jeq #132  jt +1 ->[6]  jf +3 ->[8 OOB=drop]
    libc::sock_filter { code: 0x15, jt: 1, jf: 3, k: 132 },
    // 5: ret #0  (unreachable safety)
    libc::sock_filter { code: 0x06, jt: 0, jf: 0, k: 0 },
    // 6: ret #262144  (accept)
    libc::sock_filter { code: 0x06, jt: 0, jf: 0, k: 262_144 },
];

fn attach_bpf_filter(fd: RawFd) -> Result<()> {
    // Safety: BPF_INSTRUCTIONS is a static slice of POD. The kernel copies
    // the program internally so we don't need to keep it alive beyond the
    // setsockopt call.
    let prog = libc::sock_fprog {
        len: BPF_INSTRUCTIONS.len() as u16,
        filter: BPF_INSTRUCTIONS.as_ptr() as *mut _,
    };
    let ret = unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_ATTACH_FILTER,
            &prog as *const _ as *const libc::c_void,
            std::mem::size_of::<libc::sock_fprog>() as libc::socklen_t,
        )
    };
    if ret != 0 {
        return Err(std::io::Error::last_os_error())
            .context("setsockopt(SO_ATTACH_FILTER) failed");
    }
    Ok(())
}

// -----------------------------------------------------------------------------
// Socket helpers
// -----------------------------------------------------------------------------

/// Open a raw `AF_PACKET` socket suitable for capturing IPv4/SCTP frames.
///
/// `iface`: if `Some(name)` and `name != "any"`, the socket is bound via
/// `SO_BINDTODEVICE`. Pass `None` to capture on all interfaces.
pub fn open_packet_socket(iface: Option<&str>) -> Result<Socket> {
    // ETH_P_ALL = 0x0003, but AF_PACKET + Type::RAW + ETH_P_ALL is the canonical
    // way to get every L2 frame.
    let proto = Protocol::from(0x0003u16.to_be() as i32);

    let sock = Socket::new(Domain::PACKET, Type::RAW, Some(proto))
        .context("socket(AF_PACKET, RAW, ETH_P_ALL)")?;

    // Generous receive buffer (1 MiB) so we don't drop frames under burst load.
    let rcvbuf: libc::c_int = 1 << 20;
    unsafe {
        libc::setsockopt(
            sock.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_RCVBUF,
            &rcvbuf as *const _ as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        );
    }

    // Install BPF filter before binding (cheap, kernel-side).
    attach_bpf_filter(sock.as_raw_fd())?;

    if let Some(name) = iface {
        if !name.is_empty() && name != "any" {
            let cstr = std::ffi::CString::new(name)
                .with_context(|| format!("interface name contains NUL: {name}"))?;
            let ret = unsafe {
                libc::setsockopt(
                    sock.as_raw_fd(),
                    libc::SOL_SOCKET,
                    libc::SO_BINDTODEVICE,
                    cstr.as_ptr() as *const libc::c_void,
                    cstr.as_bytes().len() as libc::socklen_t,
                )
            };
            if ret != 0 {
                let err = std::io::Error::last_os_error();
                return Err(anyhow!(
                    "setsockopt(SO_BINDTODEVICE={name}) failed: {err}"
                ));
            }
            info!(interface = %name, "bound AF_PACKET socket to interface");
        } else {
            info!("capturing on all interfaces (any)");
        }
    } else {
        info!("capturing on all interfaces (default)");
    }

    Ok(sock)
}

// -----------------------------------------------------------------------------
// SCTP / M3UA parsing
// -----------------------------------------------------------------------------

/// Parsed view of a single DATA chunk (RFC 4960 §6.10).
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)] // stream_seq/payload_proto_id kept for downstream consumers
pub struct DataChunk {
    pub stream_id: u16,
    pub stream_seq: u16,
    pub payload_proto_id: u32,
    /// Length of the user-data payload in bytes (excludes the DATA chunk header).
    pub payload_len: usize,
    /// M3UA class if the chunk's payload is M3UA (proto 3) and we could
    /// peek the header; otherwise `None`.
    pub m3ua_class: Option<M3uaClass>,
}

#[derive(Debug, Clone, Copy)]
#[allow(dead_code)] // vtag/chunks_len kept for future inspection / tests
pub struct PacketSummary {
    pub src_port: u16,
    pub dst_port: u16,
    pub vtag: u32,
    pub chunks_len: usize,
}

/// Try to parse one DATA chunk from a slice. Returns `None` if `chunk_type`
/// isn't 0x00 or the buffer is truncated. The caller must validate the chunk
/// is fully contained in the input buffer.
pub fn parse_data_chunk(buf: &[u8]) -> Option<DataChunk> {
    // DATA chunk layout (RFC 4960 §6.10):
    //   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //   |   Type = 0    | Reserved|U|B|E|         Length                |
    //   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //   |                              TSN                              |
    //   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //   |      Stream Identifier S      |   Stream Sequence Number n    |
    //   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //   |                  Payload Protocol Identifier                  |
    //   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //   /                 User Data (seq n of Stream S)                  /
    if buf.len() < 16 {
        return None;
    }
    let length = u16::from_be_bytes([buf[2], buf[3]]) as usize;
    if length < 16 || length > buf.len() {
        return None;
    }
    let stream_id = u16::from_be_bytes([buf[8], buf[9]]);
    let stream_seq = u16::from_be_bytes([buf[10], buf[11]]);
    let payload_proto_id = u32::from_be_bytes([buf[12], buf[13], buf[14], buf[15]]);
    let payload_len = length - 16;

    // M3UA peek (RFC 4666 §3): version(1) + reserved(1) + class(1) + type(1)
    // + length(4) + ... but we only need to reach the class byte at offset 19
    // (= 14 L2 + 9 IPv4 + ... wait — this is relative to the DATA chunk body
    // AFTER the chunk header). The DATA chunk header is 16 bytes; user data
    // starts at buf[16]. M3UA common header: byte 0=version, 1=reserved,
    // 2=class, 3=type, 4..7=length. So class is at buf[16+2]=buf[18].
    let m3ua_class = if payload_proto_id == 3 && payload_len >= 8 {
        let class_byte = buf[18];
        Some(M3uaClass::from_u8(class_byte))
    } else {
        None
    };

    Some(DataChunk {
        stream_id,
        stream_seq,
        payload_proto_id,
        payload_len,
        m3ua_class,
    })
}

/// Walk the SCTP chunk list and collect DATA chunks.
fn iter_data_chunks(sctp_chunks: &[u8], out: &mut Vec<DataChunk>) {
    let mut off = 0;
    while off + 4 <= sctp_chunks.len() {
        let chunk_type = sctp_chunks[off];
        let chunk_len = u16::from_be_bytes([sctp_chunks[off + 2], sctp_chunks[off + 3]])
            as usize;
        if chunk_len < 4 || off + chunk_len > sctp_chunks.len() {
            break; // malformed / truncated — bail out
        }
        if chunk_type == 0x00 {
            if let Some(d) = parse_data_chunk(&sctp_chunks[off..off + chunk_len]) {
                out.push(d);
            }
        }
        off += chunk_len;
    }
}

/// Top-level frame parser. Returns Some(summary) when the frame is a valid
/// IPv4/SCTP packet, plus the DATA chunks found in `out`.
pub fn parse_frame(buf: &[u8], out: &mut Vec<DataChunk>) -> Option<PacketSummary> {
    // Ethernet header (14 bytes): dst(6) + src(6) + ethertype(2).
    if buf.len() < 14 {
        return None;
    }
    let ethertype = u16::from_be_bytes([buf[12], buf[13]]);
    if ethertype != 0x0800 {
        return None; // IPv4 only (BPF filter guarantees this in practice).
    }

    // IPv4 header — variable length, 20 bytes minimum.
    if buf.len() < 14 + 20 {
        return None;
    }
    let ip = &buf[14..];
    let version_ihl = ip[0];
    if version_ihl >> 4 != 4 {
        return None;
    }
    let ihl = ((version_ihl & 0x0f) as usize) * 4;
    if ihl < 20 || 14 + ihl > buf.len() {
        return None;
    }
    if ip[9] != 132 {
        return None; // Not SCTP. BPF should have filtered it.
    }

    let total_len = u16::from_be_bytes([ip[2], ip[3]]) as usize;
    let sctp_end = 14 + total_len.min(buf.len() - 14);
    let sctp = &buf[14 + ihl..sctp_end];

    if sctp.len() < 12 {
        return None;
    }
    let src_port = u16::from_be_bytes([sctp[0], sctp[1]]);
    let dst_port = u16::from_be_bytes([sctp[2], sctp[3]]);
    let vtag = u32::from_be_bytes([sctp[4], sctp[5], sctp[6], sctp[7]]);

    // Chunk list starts at offset 12.
    let chunks = &sctp[12..];
    iter_data_chunks(chunks, out);

    Some(PacketSummary {
        src_port,
        dst_port,
        vtag,
        chunks_len: chunks.len(),
    })
}

/// Classify a packet as in/out/passthrough vs the gateway port.
fn classify(src_port: u16, dst_port: u16, gw_port: u16) -> Option<Direction> {
    if src_port == gw_port {
        Some(Direction::Out)
    } else if dst_port == gw_port {
        Some(Direction::In)
    } else {
        None
    }
}

// -----------------------------------------------------------------------------
// Capture loop
// -----------------------------------------------------------------------------

/// Blocking capture loop. Designed to be spawned via
/// [`tokio::task::spawn_blocking`]. Runs forever; only returns on fatal errors.
pub fn run_capture(metrics: Metrics, iface: Option<String>, gw_port: u16) -> Result<()> {
    let iface_ref = iface.as_deref();
    let sock = open_packet_socket(iface_ref)?;
    let fd = sock.as_raw_fd();

    // Big static buffer; AF_PACKET MTU is usually <= 1500 (jumbo <= 9000).
    const BUF_LEN: usize = 65535;
    let mut buf = vec![0u8; BUF_LEN];

    info!(fd, gw_port, "capture loop started");

    loop {
        // SAFETY: `buf` outlives the recv call. We re-arm `n` after every
        // successful read so the slice passed in is always valid.
        let n = unsafe {
            libc::recv(
                fd,
                buf.as_mut_ptr() as *mut libc::c_void,
                buf.len(),
                0,
            )
        };
        if n < 0 {
            let err = std::io::Error::last_os_error();
            // Interrupted system call is fine; just retry.
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            warn!(error = %err, "recv() failed");
            std::thread::sleep(Duration::from_millis(50));
            continue;
        }
        if n == 0 {
            continue;
        }
        let frame = &buf[..n as usize];

        let mut data_chunks: Vec<DataChunk> = Vec::with_capacity(4);
        let Some(summary) = parse_frame(frame, &mut data_chunks) else {
            debug!(len = n, "frame did not parse as SCTP, skipping");
            continue;
        };

        if let Some(direction) = classify(summary.src_port, summary.dst_port, gw_port) {
            for dc in &data_chunks {
                metrics.record(
                    direction,
                    dc.payload_len as u64,
                    dc.stream_id,
                    dc.m3ua_class,
                );
            }
        }
    }
}

/// Convenience: spawn the capture loop on tokio's blocking thread pool.
pub fn spawn_capture(
    metrics: Metrics,
    iface: Option<String>,
    gw_port: u16,
) -> tokio::task::JoinHandle<Result<()>> {
    tokio::task::spawn_blocking(move || run_capture(metrics, iface, gw_port))
}

/// Verify the BPF program looks sane. Cheap smoke test.
#[allow(dead_code)] // exposed for tests / external tooling
pub fn bpf_program_ok() -> bool {
    if BPF_INSTRUCTIONS.len() < 5 {
        return false;
    }
    let mut has_drop = false;
    let mut has_accept = false;
    for insn in BPF_INSTRUCTIONS {
        // BPF_RET = 0x06
        if insn.code == 0x06 {
            if insn.k == 0 {
                has_drop = true;
            } else if insn.k >= 1 {
                has_accept = true;
            }
        }
    }
    has_drop && has_accept
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Hand-build a minimal IPv4/SCTP frame carrying one DATA chunk
    /// whose payload is a stub M3UA message.
    fn build_frame() -> Vec<u8> {
        // ---- Ethernet (14) ----
        let mut f = vec![0u8; 14];
        f[12] = 0x08; f[13] = 0x00; // EtherType = IPv4

        // ---- IPv4 (20) ----
        let ip_start = f.len();
        f.push(0x45); // version=4, ihl=5 (20 bytes)
        f.push(0x00); // DSCP/ECN
        f.push(0x00); f.push(0x00); // total length placeholder
        f.push(0x00); f.push(0x00); // identification
        f.push(0x40); f.push(0x00); // flags=DF, frag=0
        f.push(64);     // TTL
        f.push(132);    // proto = SCTP
        f.push(0x00); f.push(0x00); // checksum (skipped)
        f.extend_from_slice(&[10, 0, 0, 1]);   // src
        f.extend_from_slice(&[10, 0, 0, 2]);   // dst

        // ---- SCTP common header (12) ----
        f.push(0x1F); f.push(0x4C); // src port 8012 (gateway)
        f.push(0x0B); f.push(0x59); // dst port 2905 (some peer)
        f.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]); // vtag
        f.extend_from_slice(&[0x00, 0x00, 0x00, 0x00]); // checksum

        // ---- DATA chunk ----
        f.push(0x00);             // type
        f.push(0x00);             // flags
        f.push(0x00); f.push(0x18); // length = 24
        f.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]); // TSN
        f.push(0x00); f.push(0x07); // stream_id = 7
        f.push(0x00); f.push(0x01); // stream_seq = 1
        f.extend_from_slice(&[0x00, 0x00, 0x00, 0x03]); // ppid = M3UA
        // 8 bytes M3UA: version=1, reserved=0, class=1 (transfer), type=1, length=8
        f.push(0x01); f.push(0x00); f.push(0x01); f.push(0x01);
        f.extend_from_slice(&[0x00, 0x00, 0x00, 0x08]);

        // Fix IPv4 total length.
        let total = (f.len() - ip_start) as u16;
        f[ip_start + 2..ip_start + 4].copy_from_slice(&total.to_be_bytes());
        f
    }

    #[test]
    fn bpf_filter_is_sane() {
        assert!(bpf_program_ok());
    }

    #[test]
    fn parse_synthetic_sctp_frame() {
        let frame = build_frame();
        let mut chunks = Vec::new();
        let summary = parse_frame(&frame, &mut chunks).expect("should parse");
        assert_eq!(summary.src_port, 8012);
        assert_eq!(summary.dst_port, 2905);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].stream_id, 7);
        assert_eq!(chunks[0].stream_seq, 1);
        assert_eq!(chunks[0].payload_proto_id, 3);
        assert_eq!(chunks[0].payload_len, 8);
        assert_eq!(chunks[0].m3ua_class, Some(M3uaClass::Transfer));
    }

    #[test]
    fn classify_in_out() {
        assert_eq!(classify(8012, 2905, 8012), Some(Direction::Out));
        assert_eq!(classify(2905, 8012, 8012), Some(Direction::In));
        assert_eq!(classify(1111, 2222, 8012), None);
    }
}
