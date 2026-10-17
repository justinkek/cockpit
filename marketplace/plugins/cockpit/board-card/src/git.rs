use crate::ctx::{self, die};
use crate::util;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Output, Stdio};

const CLEARED: &[&str] = &[
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
];

fn native(path: &Path) -> bool {
    let Ok(mut file) = fs::File::open(path) else { return false };
    let mut head = [0u8; 2];
    use std::io::Read;
    match file.read_exact(&mut head) {
        Ok(()) => &head != b"#!",
        Err(_) => false,
    }
}

fn find_git() -> String {
    let given = ctx::env("BOARD_CARD_GIT");
    if !given.is_empty() {
        return given;
    }
    for directory in ctx::env("PATH").split(':').filter(|d| !d.is_empty()) {
        let candidate = Path::new(directory).join("git");
        let executable = fs::metadata(&candidate).map(|m| {
            use std::os::unix::fs::PermissionsExt;
            m.is_file() && m.permissions().mode() & 0o111 != 0
        });
        if executable.unwrap_or(false) && native(&candidate) {
            return candidate.to_string_lossy().into_owned();
        }
    }
    "git".to_string()
}

pub fn program() -> String {
    static GIT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    GIT.get_or_init(find_git).clone()
}

pub fn bare(args: &[&str]) -> Command {
    let mut command = Command::new(program());
    for name in CLEARED {
        command.env_remove(name);
    }
    command.args(args);
    command
}

fn command(index: Option<&str>, args: &[&str]) -> Command {
    let mut command = Command::new(program());
    command.arg("-C").arg(ctx::board_dir());
    for name in CLEARED {
        command.env_remove(name);
    }
    if let Some(index) = index {
        command.env("GIT_INDEX_FILE", index);
    }
    command.args(args);
    command
}

pub struct Run {
    pub ok: bool,
    pub stdout: String,
    pub raw: Vec<u8>,
}

fn finish(output: std::io::Result<Output>) -> Run {
    match output {
        Ok(output) => Run {
            ok: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            raw: output.stdout,
        },
        Err(_) => Run { ok: false, stdout: String::new(), raw: Vec::new() },
    }
}

pub fn run(args: &[&str]) -> Run {
    finish(command(None, args).stdin(Stdio::null()).stderr(Stdio::null()).output())
}

pub fn run_loud(args: &[&str]) -> Run {
    finish(command(None, args).stdin(Stdio::null()).stderr(Stdio::inherit()).output())
}

pub fn run_env(args: &[&str], vars: &[(&str, &str)]) -> Run {
    let mut command = command(None, args);
    for (name, value) in vars {
        command.env(name, value);
    }
    finish(command.stdin(Stdio::null()).stderr(Stdio::null()).output())
}

pub fn run_index(index: &str, args: &[&str]) -> Run {
    finish(command(Some(index), args).stdin(Stdio::null()).stderr(Stdio::null()).output())
}

pub fn run_index_loud(index: &str, args: &[&str]) -> Run {
    finish(command(Some(index), args).stdin(Stdio::null()).stderr(Stdio::inherit()).output())
}

pub fn run_input(index: Option<&str>, args: &[&str], input: &[u8]) -> Run {
    let mut child = match command(index, args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit()).spawn() {
        Ok(child) => child,
        Err(_) => return Run { ok: false, stdout: String::new(), raw: Vec::new() },
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input);
    }
    finish(child.wait_with_output())
}

pub fn has_repo() -> bool {
    Path::new(&format!("{}/.git", ctx::board_dir())).is_dir()
}

pub fn git_dir() -> String {
    format!("{}/.git", ctx::board_root())
}

pub fn held_file() -> String {
    format!("{}/board-card-held", git_dir())
}

pub fn record_id_of(path: &str) -> Option<String> {
    fn from(rest: &str) -> Option<String> {
        let slash = rest.find('/')?;
        let folder = &rest[..slash];
        if folder.is_empty() || !folder.bytes().all(|b| b.is_ascii_lowercase()) {
            return None;
        }
        let tail = &rest[slash + 1..];
        let dash = tail.find('-')?;
        let head = tail[..dash].as_bytes();
        if head.is_empty() || !head[0].is_ascii_uppercase() || !head.iter().all(|b| b.is_ascii_uppercase() || b.is_ascii_digit()) {
            return None;
        }
        let after = &tail[dash + 1..];
        let digits = after.bytes().take_while(|b| b.is_ascii_digit()).count();
        if digits == 0 {
            return None;
        }
        match after.as_bytes().get(digits) {
            Some(b'.') | Some(b'/') => Some(tail[..dash + 1 + digits].to_string()),
            _ => None,
        }
    }
    if let Some(rest) = path.strip_prefix("archive/") {
        if let Some(id) = from(rest) {
            return Some(id);
        }
    }
    from(path)
}

pub fn ids_of_paths(paths: &[String]) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    for path in paths {
        if let Some(id) = record_id_of(path) {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    ids
}

fn commit_identity() -> [&'static str; 6] {
    ["-c", "user.name=board-card", "-c", "user.email=board-card@localhost", "-c", "commit.gpgsign=false"]
}

pub fn commit_board(subject: &str) -> bool {
    if !has_repo() {
        return true;
    }
    let index_lock = format!("{}/.git/index.lock", ctx::board_dir());
    if util::older_than_minute(&index_lock) {
        let _ = fs::remove_file(&index_lock);
    }
    let added = command(None, &["add", "--all"]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::inherit()).status();
    if !matches!(added, Ok(status) if status.success()) {
        return false;
    }
    let staged = run(&["diff", "--cached", "--name-only", "--no-renames"]);
    let paths = util::lines(&staged.stdout);
    if staged.ok && paths.is_empty() {
        return true;
    }
    let ids = ids_of_paths(&paths);
    let message = if ids.is_empty() { subject.to_string() } else { format!("{} {}", subject, ids.join(" ")) };
    let mut args: Vec<&str> = commit_identity().to_vec();
    args.extend(["commit", "--quiet", "--no-verify", "--message", &message]);
    let status = command(None, &args).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::inherit()).status();
    matches!(status, Ok(status) if status.success())
}

pub fn dirty_paths() -> Vec<String> {
    let status = run(&["status", "--porcelain", "-z", "--untracked-files=all", "--no-renames"]);
    status
        .raw
        .split(|b| *b == 0)
        .filter(|entry| entry.len() > 3)
        .map(|entry| String::from_utf8_lossy(&entry[3..]).into_owned())
        .collect()
}

pub fn snapshot_tree() -> Option<String> {
    let git = git_dir();
    let index = format!("{}/board-card-snapshot", git);
    let real = format!("{}/index", git);
    if Path::new(&real).is_file() {
        fs::copy(&real, &index).ok()?;
    } else {
        let _ = fs::remove_file(&index);
    }
    if !run_index(&index, &["add", "--all"]).ok {
        return None;
    }
    let tree = run_index(&index, &["write-tree"]);
    if !tree.ok {
        return None;
    }
    Some(tree.stdout.trim().to_string())
}

pub fn head() -> Option<String> {
    let head = run(&["rev-parse", "--quiet", "--verify", "HEAD"]);
    if head.ok {
        Some(head.stdout.trim().to_string())
    } else {
        None
    }
}

pub fn commit_paths(subject: &str, tree: &str, paths: &[String]) -> bool {
    if paths.is_empty() {
        return true;
    }
    let head = head();
    let base = match &head {
        Some(head) => head.clone(),
        None => run(&["hash-object", "-t", "tree", "/dev/null"]).stdout.trim().to_string(),
    };
    let mut args: Vec<&str> = vec!["--literal-pathspecs", "diff-tree", "-z", "-r", "--raw", "--no-renames", &base, tree, "--"];
    for path in paths {
        args.push(path);
    }
    let diff = run(&args);
    let mut entries: Vec<u8> = Vec::new();
    let mut ids: Vec<String> = Vec::new();
    let mut parts = diff.raw.split(|b| *b == 0).filter(|p| !p.is_empty());
    let mut any = false;
    while let (Some(meta), Some(path)) = (parts.next(), parts.next()) {
        let meta = String::from_utf8_lossy(meta);
        let path = String::from_utf8_lossy(path).into_owned();
        let fields: Vec<&str> = meta.trim_start_matches(':').split(' ').collect();
        if fields.len() < 5 {
            continue;
        }
        let (old_sha, new_mode, new_sha, status) = (fields[2], fields[1], fields[3], fields[4]);
        if status == "D" {
            entries.extend_from_slice(format!("0 {}\t{}", old_sha, path).as_bytes());
        } else {
            entries.extend_from_slice(format!("{} {}\t{}", new_mode, new_sha, path).as_bytes());
        }
        entries.push(0);
        any = true;
        if let Some(id) = record_id_of(&path) {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    if !any {
        return true;
    }
    let git = git_dir();
    let lock = format!("{}/index.lock", git);
    if Path::new(&lock).exists() && util::older_than_minute(&lock) {
        let _ = fs::remove_file(&lock);
    }
    if fs::OpenOptions::new().write(true).create_new(true).open(&lock).is_err() {
        return false;
    }
    let real = format!("{}/index", git);
    let message = if ids.is_empty() { subject.to_string() } else { format!("{} {}", subject, ids.join(" ")) };
    let built = (|| -> Option<()> {
        if Path::new(&real).is_file() {
            fs::copy(&real, &lock).ok()?;
        }
        let read = match &head {
            Some(head) => run_index_loud(&lock, &["read-tree", "-m", head]),
            None => run_index_loud(&lock, &["read-tree", "--empty"]),
        };
        if !read.ok {
            return None;
        }
        if !run_input(Some(&lock), &["update-index", "-z", "--index-info"], &entries).ok {
            return None;
        }
        let written = run_index_loud(&lock, &["write-tree"]);
        if !written.ok {
            return None;
        }
        let built = written.stdout.trim().to_string();
        let mut args: Vec<&str> = commit_identity().to_vec();
        args.extend(["commit-tree", &built]);
        if let Some(head) = &head {
            args.extend(["-p", head]);
        }
        args.extend(["-m", &message]);
        let commit = run_loud(&args);
        if !commit.ok {
            return None;
        }
        let commit = commit.stdout.trim().to_string();
        let reflog = format!("commit: {}", subject);
        let old = head.clone().unwrap_or_default();
        if !run_loud(&["update-ref", "-m", &reflog, "HEAD", &commit, &old]).ok {
            return None;
        }
        fs::rename(&lock, &real).ok()?;
        Some(())
    })();
    if built.is_some() {
        return true;
    }
    let _ = fs::remove_file(&lock);
    false
}

pub struct Line {
    pub batch: String,
    pub stamp: i64,
    pub verb: String,
    pub path: String,
}

pub struct Held {
    pub lines: Vec<Line>,
}

pub fn key_of_id(id: &str) -> String {
    if id.starts_with("FEAT-") || id.starts_with("BUG-") || id.starts_with("TIME-") {
        format!("card-{}", crate::record::number(id))
    } else {
        id.to_string()
    }
}

pub fn key_of_path(path: &str) -> String {
    match record_id_of(path) {
        Some(id) => key_of_id(&id),
        None => path.to_string(),
    }
}

impl Held {
    pub fn load() -> Held {
        let mut lines = Vec::new();
        if let Some(text) = util::read_text(&held_file()) {
            for line in util::lines(&text) {
                let mut parts = line.splitn(4, '\t');
                let batch = parts.next().unwrap_or("").to_string();
                let stamp = parts.next().unwrap_or("0").parse().unwrap_or(0);
                let verb = parts.next().unwrap_or("").to_string();
                let path = parts.next().unwrap_or("").to_string();
                lines.push(Line { batch, stamp, verb, path });
            }
        }
        Held { lines }
    }

    pub fn save(&self) {
        let file = held_file();
        if self.lines.is_empty() {
            let _ = fs::remove_file(&file);
            return;
        }
        let mut text = String::new();
        for line in &self.lines {
            text.push_str(&format!("{}\t{}\t{}\t{}\n", line.batch, line.stamp, line.verb, line.path));
        }
        let _ = util::write_file(&file, &text);
    }

    pub fn batches(&self) -> Vec<String> {
        let mut ids: Vec<String> = Vec::new();
        for line in &self.lines {
            if !ids.contains(&line.batch) {
                ids.push(line.batch.clone());
            }
        }
        ids
    }

    pub fn info(&self, batch: &str) -> (Vec<String>, String, Vec<String>, i64) {
        let mut paths: Vec<String> = Vec::new();
        let mut actions: Vec<String> = Vec::new();
        let mut keys: Vec<String> = Vec::new();
        let mut last = 0;
        for line in self.lines.iter().filter(|l| l.batch == batch) {
            if line.stamp > last {
                last = line.stamp;
            }
            if !actions.contains(&line.verb) {
                actions.push(line.verb.clone());
            }
            if paths.contains(&line.path) {
                continue;
            }
            paths.push(line.path.clone());
            let key = key_of_path(&line.path);
            if !keys.contains(&key) {
                keys.push(key);
            }
        }
        (paths, actions.join(", "), keys, last)
    }

    pub fn commit_batch(&mut self, batch: &str, tree: &str) -> bool {
        let (paths, actions, _, _) = self.info(batch);
        if !commit_paths(&actions, tree, &paths) {
            return false;
        }
        self.lines.retain(|l| l.batch != batch);
        self.save();
        true
    }
}

fn delay_seconds() -> f64 {
    ctx::delay().parse().unwrap_or(f64::NAN)
}

pub fn flush_held(held: &mut Held, dirty: &[String], tree: &str, now: i64) -> bool {
    let mut failed = false;
    let flush_keys = ctx::with(|s| s.flush_keys.clone());
    let delay = delay_seconds();
    for batch in held.batches() {
        let (_, _, keys, last) = held.info(&batch);
        let mut due = ctx::flush_now() || ctx::delay_is_zero() || ((now - last) as f64) >= delay;
        if !flush_keys.is_empty() && keys.contains(&flush_keys) {
            due = true;
        }
        if due && !held.commit_batch(&batch, tree) {
            failed = true;
        }
    }
    let held_paths: Vec<&String> = held.lines.iter().map(|l| &l.path).collect();
    let unrecorded: Vec<String> = dirty.iter().filter(|p| !held_paths.contains(p)).cloned().collect();
    if !commit_paths("unrecorded", tree, &unrecorded) {
        failed = true;
    }
    !failed
}

fn spawn_flusher() {
    let Ok(exe) = std::env::current_exe() else { return };
    let mut command = Command::new(exe);
    command
        .arg("flush")
        .env("BOARD_CARD_FLUSH_AFTER", ctx::delay())
        .env("BOARD_CARD_SCRIPTS", ctx::scripts())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    use std::os::unix::process::CommandExt;
    command.process_group(0);
    let _ = command.spawn();
}

pub fn hold_write(held: &mut Held, before: &str, stamp: i64, changed: &[String]) -> bool {
    let mut keys: Vec<String> = Vec::new();
    for path in changed {
        let key = key_of_path(path);
        if !keys.contains(&key) {
            keys.push(key);
        }
    }
    let mut overlapping: Vec<String> = Vec::new();
    for batch in held.batches() {
        let (_, _, batch_keys, _) = held.info(&batch);
        if changed.iter().any(|p| batch_keys.contains(&key_of_path(p))) {
            overlapping.push(batch);
        }
    }
    let mut target: Option<String> = None;
    if overlapping.len() == 1 && keys.len() == 1 {
        let (_, _, batch_keys, _) = held.info(&overlapping[0]);
        if batch_keys == keys {
            target = Some(overlapping[0].clone());
        }
    }
    let batch = match target {
        Some(batch) => batch,
        None => {
            for batch in &overlapping {
                if !held.commit_batch(batch, before) {
                    return false;
                }
            }
            format!("{}.{}", stamp, std::process::id())
        }
    };
    let action = ctx::action();
    for path in changed {
        held.lines.push(Line { batch: batch.clone(), stamp, verb: action.clone(), path: path.clone() });
    }
    held.save();
    spawn_flusher();
    true
}

pub fn with_lock(body: impl FnOnce()) {
    let lock = format!("{}/.lock", ctx::board_dir());
    let mut tries = 0;
    loop {
        if fs::create_dir(&lock).is_ok() {
            break;
        }
        tries += 1;
        if tries >= 50 {
            if util::older_than_minute(&lock) {
                let _ = fs::remove_dir_all(&lock);
                continue;
            }
            die(5, &format!("board is locked by another writer: {}", lock));
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    ctx::with_mut(|s| s.lock_held = Some(lock.clone()));
    let repo = has_repo();
    let mut held = Held { lines: Vec::new() };
    let mut before = String::new();
    if repo {
        held = Held::load();
        let dirty = dirty_paths();
        if !held.lines.is_empty() || !dirty.is_empty() {
            before = snapshot_tree().unwrap_or_default();
            if !before.is_empty() {
                flush_held(&mut held, &dirty, &before, crate::time::unix_now());
            }
        } else {
            before = "HEAD".to_string();
        }
    }
    body();
    if repo && ctx::action() != "flush" {
        let board = ctx::board_dir();
        if ctx::delay_is_zero() || ctx::flush_now() {
            if !commit_board(&ctx::action()) {
                die(6, &format!("wrote to {} but could not commit it", board));
            }
        } else if !before.is_empty() {
            let changed: Vec<String> = if !held.lines.is_empty() {
                let Some(after) = snapshot_tree() else { die(6, &format!("wrote to {} but could not commit it", board)) };
                let diff = run(&["diff-tree", "-z", "-r", "--name-only", "--no-renames", &before, &after]);
                diff.raw.split(|b| *b == 0).filter(|p| !p.is_empty()).map(|p| String::from_utf8_lossy(p).into_owned()).collect()
            } else {
                dirty_paths()
            };
            if !changed.is_empty() && !hold_write(&mut held, &before, crate::time::unix_now(), &changed) {
                die(6, &format!("wrote to {} but could not commit it", board));
            }
        }
    }
    ctx::release_lock();
}
