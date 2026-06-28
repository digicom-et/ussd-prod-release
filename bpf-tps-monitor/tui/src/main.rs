//! CLI entry point: parses args, enters the alternate screen, then
//! drives the `Terminal::draw` loop. No `println!` ever fires inside
//! the loop — ratatui's backend only redraws dirty cells, so the host
//! terminal sees a stable, in-place view.

mod app;
mod poll;
mod ui;

use anyhow::Result;
use clap::Parser;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{
        disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
    },
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io::{self, Stdout};
use std::time::Duration;
use tokio::sync::mpsc;

use crate::app::App;
use crate::poll::Metrics;

#[derive(Parser, Debug)]
#[command(version, about = "SCTP/M3UA TPS TUI dashboard")]
struct Args {
    /// Collector HTTP endpoint (no trailing slash).
    /// Example: `http://collector:9090` when running under docker-compose,
    /// or `http://127.0.0.1:9090` for a local collector.
    #[arg(long, default_value = "http://127.0.0.1:9090")]
    collector: String,

    /// Polling interval in milliseconds.
    #[arg(long, default_value_t = 1000)]
    interval_ms: u64,
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Install a panic hook that restores the terminal first — otherwise
    // a panic inside `terminal.draw` leaves the user stuck in raw mode.
    let original_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = restore_terminal();
        original_hook(info);
    }));

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::new(args.collector.clone(), args.interval_ms)?;

    // Initial draw so the user sees the dashboard immediately.
    terminal.draw(|f| ui::ui(f, &app))?;

    // Channel used to deliver poll results back from the background
    // polling task. Unbounded because the producer runs at most once
    // per `interval_ms` and we drain on every iteration.
    let (tx, mut rx) = mpsc::unbounded_channel::<Result<Metrics>>();
    let poll_client = app.client.clone_arc();
    let interval_ms = args.interval_ms;
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_millis(interval_ms)).await;
            let r = poll_client.fetch().await;
            // If the receiver was dropped, the user has quit.
            if tx.send(r).is_err() {
                break;
            }
        }
    });

    let res = run_loop(&mut terminal, &mut app, args.interval_ms, &mut rx).await;

    // Always restore — even on Err.
    restore_terminal()?;

    if let Err(err) = res {
        eprintln!("sctp-m3ua-tui: {err:?}");
        std::process::exit(1);
    }
    Ok(())
}

fn restore_terminal() -> Result<()> {
    disable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, LeaveAlternateScreen, DisableMouseCapture)?;
    Ok(())
}

/// The main event loop.
///
/// Each iteration:
///   1. Drain any poll results delivered via the channel.
///   2. Render via `Terminal::draw` — ratatui only rewrites dirty
///      cells, so the host terminal does NOT scroll.
///   3. Wait up to `interval_ms` (or 250 ms when paused) for a key.
///
/// The HTTP poll itself runs in a dedicated `tokio::spawn`'d task so
/// the UI thread never blocks on the network.
async fn run_loop(
    terminal: &mut Terminal<CrosstermBackend<Stdout>>,
    app: &mut App,
    interval_ms: u64,
    rx: &mut mpsc::UnboundedReceiver<Result<Metrics>>,
) -> Result<()> {
    loop {
        // === 1. Drain poll results (non-blocking).
        while let Ok(r) = rx.try_recv() {
            match r {
                Ok(m) => app.apply_metrics(m),
                Err(e) => {
                    app.record_error();
                    // Keep last good state visible on screen; only log to
                    // stderr (the host shell sees it after alt-screen exit).
                    eprintln!("poll error: {e:?}");
                }
            }
        }

        // === 2. Render.
        terminal.draw(|f| ui::ui(f, app))?;

        // === 3. Wait for input / next tick.
        let wait = if app.paused { 250 } else { interval_ms };
        if event::poll(Duration::from_millis(wait))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                        KeyCode::Char('p') | KeyCode::Char('P') => {
                            app.toggle_pause();
                        }
                        KeyCode::Char('r') | KeyCode::Char('R') => {
                            app.reset_history();
                        }
                        KeyCode::Char('c')
                            if key
                                .modifiers
                                .contains(crossterm::event::KeyModifiers::CONTROL) =>
                        {
                            return Ok(());
                        }
                        _ => {}
                    }
                }
            }
        }
    }
}
