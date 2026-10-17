use std::cell::RefCell;
use std::io::Write;
use std::path::PathBuf;

pub struct State {
    pub board_dir: String,
    pub board_root: String,
    pub delay: String,
    pub scripts: PathBuf,
    pub action: String,
    pub flush_now: bool,
    pub closing_project: bool,
    pub body_base: Option<String>,
    pub flush_keys: String,
    pub lock_held: Option<String>,
    pub ticket_dir: String,
    pub archive_ticket_dir: String,
    pub out: String,
    pub to_stderr: bool,
    pub capture: Option<String>,
}

thread_local! {
    static STATE: RefCell<Option<State>> = const { RefCell::new(None) };
}

pub fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_default()
}

pub fn env_or(name: &str, default: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => default.to_string(),
    }
}

pub fn home() -> String {
    env("HOME")
}

fn scripts_dir() -> PathBuf {
    let given = env("BOARD_CARD_SCRIPTS");
    if !given.is_empty() {
        return PathBuf::from(given);
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(plugin) = exe.parent().and_then(|p| p.parent()).and_then(|p| p.parent()).and_then(|p| p.parent()) {
            return plugin.join("scripts");
        }
    }
    PathBuf::from(".")
}

pub fn ticket_dir_names(_board_dir: &str) -> (String, String) {
    ("cards".to_string(), "cards".to_string())
}

pub fn init(action: &str) {
    let board_dir = env_or("COCKPIT_BOARD_DIR", &format!("{}/.local/state/cockpit/board", home()));
    let board_root = if board_dir.starts_with('/') {
        board_dir.clone()
    } else {
        let cwd = std::env::var("PWD").ok().filter(|p| !p.is_empty()).unwrap_or_else(|| {
            std::env::current_dir().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default()
        });
        format!("{}/{}", cwd, board_dir)
    };
    let (ticket_dir, archive_ticket_dir) = ticket_dir_names(&board_dir);
    let state = State {
        board_dir,
        board_root,
        delay: env_or("COCKPIT_COMMIT_DELAY", "3"),
        scripts: scripts_dir(),
        action: action.to_string(),
        flush_now: false,
        closing_project: false,
        body_base: None,
        flush_keys: String::new(),
        lock_held: None,
        ticket_dir,
        archive_ticket_dir,
        out: String::new(),
        to_stderr: false,
        capture: None,
    };
    STATE.with(|s| *s.borrow_mut() = Some(state));
}

pub fn with<R>(f: impl FnOnce(&State) -> R) -> R {
    STATE.with(|s| f(s.borrow().as_ref().expect("state")))
}

pub fn with_mut<R>(f: impl FnOnce(&mut State) -> R) -> R {
    STATE.with(|s| f(s.borrow_mut().as_mut().expect("state")))
}

pub fn board_dir() -> String {
    with(|s| s.board_dir.clone())
}

pub fn board_root() -> String {
    with(|s| s.board_root.clone())
}

pub fn action() -> String {
    with(|s| s.action.clone())
}

pub fn delay() -> String {
    with(|s| s.delay.clone())
}

pub fn delay_is_zero() -> bool {
    let delay = delay();
    delay == "0"
}

pub fn flush_now() -> bool {
    with(|s| s.flush_now)
}

pub fn set_flush_now() {
    with_mut(|s| s.flush_now = true)
}

pub fn closing_project() -> bool {
    with(|s| s.closing_project)
}

pub fn scripts() -> PathBuf {
    with(|s| s.scripts.clone())
}

pub fn ticket_dir() -> String {
    with(|s| s.ticket_dir.clone())
}

pub fn archive_ticket_dir() -> String {
    with(|s| s.archive_ticket_dir.clone())
}

pub fn to_stderr(on: bool) {
    with_mut(|s| s.to_stderr = on);
}

pub fn capture_start() {
    with_mut(|s| s.capture = Some(String::new()));
}

pub fn capture_end() -> String {
    with_mut(|s| s.capture.take()).unwrap_or_default()
}

pub fn out(text: &str) {
    let captured = with_mut(|s| match s.capture.as_mut() {
        Some(buffer) if !s.to_stderr => {
            buffer.push_str(text);
            true
        }
        _ => false,
    });
    if captured {
        return;
    }
    if with(|s| s.to_stderr) {
        flush_out();
        let _ = std::io::stderr().lock().write_all(text.as_bytes());
        return;
    }
    with_mut(|s| s.out.push_str(text));
    flush_out_if_large();
}

pub fn outln(text: &str) {
    out(&format!("{}\n", text));
}

fn flush_out_if_large() {
    let large = with(|s| s.out.len() > 1 << 16);
    if large {
        flush_out();
    }
}

pub fn flush_out() {
    let text = with_mut(|s| std::mem::take(&mut s.out));
    if !text.is_empty() {
        let mut stdout = std::io::stdout().lock();
        let _ = stdout.write_all(text.as_bytes());
        let _ = stdout.flush();
    }
}

pub fn err(text: &str) {
    flush_out();
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(text.as_bytes());
    let _ = stderr.write_all(b"\n");
}

pub fn warn(text: &str) {
    err(&format!("board-card: warning: {}", text));
}

pub fn release_lock() {
    let held = with_mut(|s| s.lock_held.take());
    if let Some(path) = held {
        let _ = std::fs::remove_dir_all(&path);
    }
}

pub fn exit(status: i32) -> ! {
    flush_out();
    release_lock();
    std::process::exit(status)
}

pub fn die(status: i32, message: &str) -> ! {
    err(&format!("[board-card] {}", message));
    exit(status)
}

pub fn session_id() -> String {
    let first = env("CLAUDE_SESSION_ID");
    if !first.is_empty() {
        return first;
    }
    env("CLAUDE_CODE_SESSION_ID")
}

pub fn state_dir() -> String {
    env_or("TICKET_STATE_DIR", &format!("{}/.local/state/claude-ticket-sessions", home()))
}

pub fn claim_dir() -> String {
    env_or("TICKET_CLAIM_LOCK_DIR", &format!("{}/.local/state/claude-ticket-claims", home()))
}

pub fn claim_lock() -> String {
    env_or("TICKET_CLAIM_LOCK", &scripts().join("ticket-claim-lock").to_string_lossy())
}

pub fn done_usage() -> String {
    env_or("TICKET_DONE_USAGE", &scripts().join("ticket-done-usage").to_string_lossy())
}

pub fn default_author() -> String {
    let author = env("COCKPIT_AUTHOR");
    if !author.is_empty() {
        return author;
    }
    let session = session_id();
    if !session.is_empty() {
        let short: String = session.chars().take(8).collect();
        return format!("claude {}", short);
    }
    env_or("USER", "someone")
}
