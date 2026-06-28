//! Render the dashboard. Uses ratatui widgets that only redraw dirty
//! cells — when called from `Terminal::draw(|f| ui(f, &app))`, no
//! scrolling happens in the host terminal even if the user resizes.

use crate::app::App;
use chrono::Utc;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    symbols,
    text::{Line, Span},
    widgets::{Block, Borders, Chart, Dataset, Gauge, GraphType, Paragraph, Wrap},
    Frame,
};

/// Convert a Unix timestamp into a human-readable wall-clock string.
/// Returns "—" if the collector has not sent a timestamp yet.
fn fmt_ts(ts: Option<i64>) -> String {
    match ts {
        Some(t) => chrono::DateTime::<Utc>::from_timestamp(t, 0)
            .map(|dt| dt.format("%Y-%m-%d %H:%M:%S UTC").to_string())
            .unwrap_or_else(|| "—".to_string()),
        None => "—".to_string(),
    }
}

fn fmt_u64(v: Option<u64>) -> String {
    v.map(|n| n.to_string())
        .unwrap_or_else(|| "—".to_string())
}

fn fmt_bytes(v: Option<u64>) -> String {
    let n = match v {
        Some(n) => n,
        None => return "—".to_string(),
    };
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut val = n as f64;
    let mut idx = 0;
    while val >= 1024.0 && idx < UNITS.len() - 1 {
        val /= 1024.0;
        idx += 1;
    }
    format!("{:.2} {}", val, UNITS[idx])
}

fn fmt_duration(d: std::time::Duration) -> String {
    let s = d.as_secs();
    format!("{:02}:{:02}:{:02}", s / 3600, (s / 60) % 60, s % 60)
}

fn fmt_tps(v: f64) -> String {
    format!("{:>9.1}", v)
}

/// Top-level entry point. Splits the screen into fixed-height sections,
/// then renders each panel. Always succeeds — never panics on missing
/// data; renders "—" or a yellow banner instead.
pub fn ui(f: &mut Frame, app: &App) {
    let area = f.size();

    // Outer chrome — title + status bar
    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // title
            Constraint::Min(8),    // body (everything else)
            Constraint::Length(3), // status bar
        ])
        .split(area);

    render_title(f, outer[0], app);

    // Body: left = TPS + cumulative, right = M3UA classes,
    // bottom = sparkline (full width).
    let body = outer[1];

    let (top_row, sparkline) = if body.height >= 14 {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(11), // top metrics row
                Constraint::Min(3),     // sparkline
            ])
            .split(body);
        (chunks[0], Some(chunks[1]))
    } else {
        (body, None)
    };

    let top_cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(40), // TPS + cumulative
            Constraint::Percentage(60), // M3UA classes
        ])
        .split(top_row);

    let left_col = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(5), // TPS panel
            Constraint::Length(6), // cumulative panel
        ])
        .split(top_cols[0]);

    render_tps(f, left_col[0], app);
    render_cumulative(f, left_col[1], app);
    render_classes(f, top_cols[1], app);

    if let Some(sp) = sparkline {
        render_sparkline(f, sp, app);
    }

    render_status(f, outer[2], app);
}

fn render_title(f: &mut Frame, area: Rect, app: &App) {
    let title = Line::from(vec![
        Span::styled(
            " USSD GW SCTP/M3UA TPS Monitor ",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(" ─ "),
        Span::styled(
            format!("collector: {}", app.collector_url),
            Style::default().fg(Color::DarkGray),
        ),
        Span::raw("  "),
        Span::styled(
            format!("Uptime: {}", fmt_duration(app.uptime())),
            Style::default().fg(Color::Green),
        ),
    ]);
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));
    let p = Paragraph::new(title).block(block);
    f.render_widget(p, area);
}

fn render_tps(f: &mut Frame, area: Rect, app: &App) {
    let now_total = app
        .latest
        .as_ref()
        .map(|m| m.total_tps())
        .unwrap_or(0.0);
    let now_in = app.latest.as_ref().and_then(|m| m.in_tps).unwrap_or(0.0);
    let now_out = app.latest.as_ref().and_then(|m| m.out_tps).unwrap_or(0.0);

    let text = vec![
        Line::from(format!(
            " Now      :  in={}   out={}   total={} tps",
            fmt_tps(now_in),
            fmt_tps(now_out),
            fmt_tps(now_total)
        )),
        Line::from(format!(
            " Avg 60s  :  in={}   out={}   total={} tps",
            fmt_tps(app.avg_in()),
            fmt_tps(app.avg_out()),
            fmt_tps(app.avg_total())
        )),
        Line::from(format!(
            " Peak 60s :  in={}   out={}   total={} tps",
            fmt_tps(app.peak_in),
            fmt_tps(app.peak_out),
            fmt_tps(app.peak_total)
        )),
    ];

    let block = Block::default()
        .title(Span::styled(
            " TPS (in/out/total) ",
            Style::default().fg(Color::Yellow),
        ))
        .borders(Borders::ALL);
    f.render_widget(Paragraph::new(text).block(block), area);
}

fn render_cumulative(f: &mut Frame, area: Rect, app: &App) {
    let cum = app.latest.as_ref().and_then(|m| m.cumulative.as_ref());
    let (in_pk, out_pk, in_b, out_b) = match cum {
        Some(c) => (
            Some(c.in_packets),
            Some(c.out_packets),
            Some(c.in_bytes),
            Some(c.out_bytes),
        ),
        None => (None, None, None, None),
    };

    let interfaces = app
        .latest
        .as_ref()
        .and_then(|m| m.interfaces.as_ref())
        .map(|v| v.join(", "))
        .unwrap_or_else(|| "—".into());

    let text = vec![
        Line::from(format!(
            " IN  : {:>14} packets   {}",
            fmt_u64(in_pk),
            fmt_bytes(in_b)
        )),
        Line::from(format!(
            " OUT : {:>14} packets   {}",
            fmt_u64(out_pk),
            fmt_bytes(out_b)
        )),
        Line::from(Span::styled(
            format!(" ifaces: {interfaces}"),
            Style::default().fg(Color::DarkGray),
        )),
    ];

    let block = Block::default()
        .title(Span::styled(
            " Packet counters (cumulative) ",
            Style::default().fg(Color::Yellow),
        ))
        .borders(Borders::ALL);
    f.render_widget(Paragraph::new(text).block(block), area);
}

fn render_classes(f: &mut Frame, area: Rect, app: &App) {
    let classes = app.ordered_classes();
    let total: u64 = classes.iter().map(|(_, v)| *v).sum::<u64>().max(1);

    let inner = Layout::default()
        .direction(Direction::Vertical)
        .constraints(
            classes
                .iter()
                .map(|_| Constraint::Ratio(1, classes.len() as u32))
                .collect::<Vec<_>>(),
        )
        .split(area);

    let label_color = if app.latest.is_some() {
        Color::Green
    } else {
        Color::DarkGray
    };

    for (i, (name, count)) in classes.iter().enumerate() {
        let pct = (*count as f64 / total as f64) * 100.0;
        let label = format!(
            " {:<11} [{:>5} ({:>2}%)]",
            name,
            count,
            pct.round() as u64
        );
        let ratio = (pct / 100.0).clamp(0.0, 1.0);
        let color = match *name {
            "transfer" => Color::Green,
            "snm" => Color::Blue,
            "aspsm" => Color::Magenta,
            "asptm" => Color::Cyan,
            "mgmt" => Color::Yellow,
            _ => Color::DarkGray,
        };

        let row = inner[i];
        let g = Gauge::default()
            .gauge_style(
                Style::default()
                    .fg(color)
                    .bg(Color::Reset)
                    .add_modifier(Modifier::BOLD),
            )
            .ratio(ratio)
            .label(Span::styled(label, Style::default().fg(label_color)));
        f.render_widget(g, row);
    }

    // Outer border drawn last so it sits over the gauges.
    let outer = Block::default()
        .title(Span::styled(
            " M3UA by class (current second) ",
            Style::default().fg(Color::Yellow),
        ))
        .borders(Borders::ALL);
    f.render_widget(outer, area);
}

fn render_sparkline(f: &mut Frame, area: Rect, app: &App) {
    let data: Vec<(f64, f64)> = app
        .history
        .iter()
        .enumerate()
        .map(|(i, s)| (i as f64, s.total_tps))
        .collect();

    let y_max = data
        .iter()
        .map(|(_, y)| *y)
        .fold(1.0_f64, f64::max)
        .max(1.0);
    let y_max = (y_max * 1.1).max(10.0);

    let dataset = vec![Dataset::default()
        .name("total_tps")
        .marker(symbols::Marker::Braille)
        .graph_type(GraphType::Line)
        .style(Style::default().fg(Color::Cyan))
        .data(&data)];

    let x_max = (app.history.len().saturating_sub(1)).max(1) as f64;
    let chart = Chart::new(dataset)
        .block(
            Block::default()
                .title(Span::styled(
                    " TPS over last 60s ",
                    Style::default().fg(Color::Yellow),
                ))
                .borders(Borders::ALL),
        )
        .x_axis(
            ratatui::widgets::Axis::default()
                .title("samples (1s)")
                .style(Style::default().fg(Color::Gray))
                .bounds([0.0, x_max]),
        )
        .y_axis(
            ratatui::widgets::Axis::default()
                .title("tps")
                .style(Style::default().fg(Color::Gray))
                .bounds([0.0, y_max]),
        );

    f.render_widget(chart, area);
}

fn render_status(f: &mut Frame, area: Rect, app: &App) {
    let pause_tag = if app.paused {
        Span::styled(
            " PAUSED ",
            Style::default().fg(Color::Yellow).bg(Color::Black),
        )
    } else {
        Span::styled(" polling ", Style::default().fg(Color::Green))
    };

    let mut spans = vec![
        Span::raw(" [q] Quit  [r] Reset history  [p] Pause  "),
        pause_tag,
        Span::raw(format!(" interval {}ms ", app.interval_ms)),
    ];

    if app.errors > 0 {
        spans.push(Span::styled(
            format!("  errors: {} ", app.errors),
            Style::default()
                .fg(Color::Red)
                .add_modifier(Modifier::BOLD),
        ));
    }

    if app.latest.is_none() {
        spans.insert(
            0,
            Span::styled(
                " Collector unreachable, retrying... ",
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
        );
    }

    let last_poll = app
        .last_poll_at
        .map(|t| {
            let d = t.elapsed();
            format!("last poll {}ms ago", d.as_millis())
        })
        .unwrap_or_else(|| "no poll yet".to_string());

    spans.push(Span::styled(
        format!(
            "  {last_poll}  ts: {} ",
            fmt_ts(app.latest.as_ref().and_then(|m| m.ts))
        ),
        Style::default().fg(Color::DarkGray),
    ));

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray));
    let p = Paragraph::new(Line::from(spans))
        .block(block)
        .wrap(Wrap { trim: false });
    f.render_widget(p, area);
}
