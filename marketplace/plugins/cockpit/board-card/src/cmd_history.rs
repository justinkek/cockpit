use crate::cmd_read::aliases_json;
use crate::cmd_write::{claim_lock, link_side, owner_of, renamed_to, require_unnamed};
use crate::ctx::{self, die, outln};
use crate::git::{self, with_lock};
use crate::json::{Map, Value};
use crate::record::*;
use crate::util;
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

pub fn card_aliases(id: &str) -> Vec<String> {
    let mut out = vec![id.to_string()];
    if kind_of(id) != "card" {
        return out;
    }
    if id.starts_with("FEAT-") || id.starts_with("BUG-") || id.starts_with("TIME-") {
        let n = number(id);
        for sibling in [format!("FEAT-{}", n), format!("BUG-{}", n), format!("TIME-{}", n)] {
            if sibling != id {
                out.push(sibling);
            }
        }
    }
    out.extend(aliases_to(id));
    out
}

fn folders(kind: &str) -> Vec<String> {
    if kind == "card" {
        vec!["tickets".to_string(), "cards".to_string()]
    } else {
        vec![folder_of_kind(kind)]
    }
}

pub fn record_paths(id: &str, main_only: bool) -> Vec<String> {
    let kind = kind_of(id);
    let folders = folders(kind);
    let mut paths = Vec::new();
    for alias in card_aliases(id) {
        if main_only {
            for folder in &folders {
                paths.push(format!("{}/{}.md", folder, alias));
                paths.push(format!("archive/{}/{}.md", folder, alias));
            }
            continue;
        }
        for folder in &folders {
            paths.push(format!("{}/{}.md", folder, alias));
            paths.push(format!("{}/{}.comments.jsonl", folder, alias));
        }
        paths.push(format!("attachments/{}", alias));
        for folder in &folders {
            paths.push(format!("archive/{}/{}.md", folder, alias));
            paths.push(format!("archive/{}/{}.comments.jsonl", folder, alias));
        }
        paths.push(format!("archive/attachments/{}", alias));
    }
    paths
}

fn require_history() {
    if !git::has_repo() {
        die(2, &format!("the board at {} keeps no history - run: board-card init", ctx::board_dir()));
    }
}

fn log(format: &str, paths: &[String], extra: &[&str]) -> git::Run {
    let format_arg = format!("--format={}", format);
    let mut args: Vec<&str> = vec!["log", &format_arg, "--date=format-local:%Y-%m-%dT%H:%M:%SZ"];
    args.extend(extra);
    args.push("--");
    for path in paths {
        args.push(path);
    }
    git::run_env(&args, &[("TZ", "UTC")])
}

struct Batch {
    child: std::process::Child,
    reader: BufReader<std::process::ChildStdout>,
}

impl Batch {
    fn start() -> Option<Batch> {
        let mut command = Command::new(git::program());
        command.arg("-C").arg(ctx::board_dir());
        for name in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR"] {
            command.env_remove(name);
        }
        command.args(["cat-file", "--batch"]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null());
        let mut child = command.spawn().ok()?;
        let stdout = child.stdout.take()?;
        Some(Batch { child, reader: BufReader::new(stdout) })
    }

    fn get(&mut self, spec: &str) -> Option<(String, Vec<u8>)> {
        let stdin = self.child.stdin.as_mut()?;
        stdin.write_all(format!("{}\n", spec).as_bytes()).ok()?;
        stdin.flush().ok()?;
        let mut header = String::new();
        self.reader.read_line(&mut header).ok()?;
        let header = header.trim_end_matches('\n');
        if header.ends_with(" missing") || header.ends_with(" ambiguous") || header.is_empty() {
            return None;
        }
        let mut parts = header.split(' ');
        let _oid = parts.next()?;
        let kind = parts.next()?.to_string();
        let size: usize = parts.next()?.parse().ok()?;
        let mut content = vec![0u8; size];
        self.reader.read_exact(&mut content).ok()?;
        let mut newline = [0u8; 1];
        self.reader.read_exact(&mut newline).ok()?;
        Some((kind, content))
    }

    fn tree_names(&mut self, spec: &str, prefix: &str, out: &mut Vec<String>) {
        let Some((kind, content)) = self.get(spec) else { return };
        if kind != "tree" {
            return;
        }
        let hash_len = if spec.split(':').next().map(|c| c.len() > 40).unwrap_or(false) { 32 } else { 20 };
        let mut at = 0;
        while at < content.len() {
            let Some(space) = content[at..].iter().position(|b| *b == b' ') else { break };
            let mode = String::from_utf8_lossy(&content[at..at + space]).into_owned();
            let rest = at + space + 1;
            let Some(nul) = content[rest..].iter().position(|b| *b == 0) else { break };
            let name = String::from_utf8_lossy(&content[rest..rest + nul]).into_owned();
            at = rest + nul + 1 + hash_len;
            let path = format!("{}/{}", prefix, name);
            if mode == "40000" {
                let commit = spec.split(':').next().unwrap_or("");
                self.tree_names(&format!("{}:{}", commit, path), &path, out);
            } else {
                out.push(path);
            }
        }
    }
}

impl Drop for Batch {
    fn drop(&mut self) {
        drop(self.child.stdin.take());
        let _ = self.child.wait();
    }
}

fn is_main_path(path: &str) -> bool {
    let rest = path.strip_prefix("archive/").unwrap_or(path);
    let check = |text: &str| -> bool {
        let Some(slash) = text.find('/') else { return false };
        let folder = &text[..slash];
        if folder.is_empty() || !folder.bytes().all(|b| b.is_ascii_lowercase()) {
            return false;
        }
        let file = &text[slash + 1..];
        let Some(stem) = file.strip_suffix(".md") else { return false };
        is_id_shape(stem)
    };
    check(rest) || (path.starts_with("archive/") && check(path))
}

struct Version {
    commit: String,
    at: String,
    author: String,
    subject: String,
    archived: bool,
    record: Option<Value>,
    comments: Map,
    attachments: Vec<String>,
}

fn comments_of(text: &str) -> Map {
    let mut map = Map::new();
    for line in util::lines(text) {
        if line.is_empty() {
            continue;
        }
        let Ok(comment) = Value::parse(&line) else { ctx::exit(5) };
        let key = comment.get("id").tostring();
        map.insert(&key, comment);
    }
    map
}

fn changed(before: &Value, after: &Value) -> Vec<Value> {
    let mut keys: Vec<String> = Vec::new();
    for value in [before, after] {
        if let Value::Obj(map) = value {
            keys.extend(map.entries.iter().map(|(k, _)| k.clone()));
        }
    }
    keys.sort();
    keys.dedup();
    let skipped = ["updated", "moved", "moved_by", "dates", "body"];
    let mut out = Vec::new();
    for key in keys {
        if skipped.contains(&key.as_str()) {
            continue;
        }
        let from = before.get(&key).clone();
        let to = after.get(&key).clone();
        if from != to {
            let mut change = Map::new();
            change.insert("field", Value::str(&key));
            change.insert("from", from);
            change.insert("to", to);
            out.push(Value::Obj(change));
        }
    }
    out
}

fn comment_entry(action: &str, comment: &Value, text: &Value) -> Value {
    let mut entry = Map::new();
    entry.insert("action", Value::str(action));
    entry.insert("id", comment.get("id").clone());
    entry.insert("thread", comment.get("thread").clone());
    entry.insert("author", comment.get("author").clone());
    entry.insert("text", text.clone());
    Value::Obj(entry)
}

fn history_json(paths: &[String]) -> Value {
    let log = log("%H%x09%h%x09%ad%x09%an%x09%s", paths, &[]);
    let mut batch = Batch::start();
    let mut versions: Vec<Version> = Vec::new();
    for line in util::lines(&log.stdout) {
        let mut parts = line.splitn(5, '\t');
        let full = parts.next().unwrap_or("").to_string();
        let commit = parts.next().unwrap_or("").to_string();
        let at = parts.next().unwrap_or("").to_string();
        let author = parts.next().unwrap_or("").to_string();
        let subject = parts.next().unwrap_or("").to_string();
        let mut files: Vec<(String, Option<Vec<u8>>)> = Vec::new();
        if let Some(batch) = batch.as_mut() {
            for path in paths {
                if path.starts_with("attachments/") || path.starts_with("archive/attachments/") {
                    let mut names = Vec::new();
                    batch.tree_names(&format!("{}:{}", full, path), path, &mut names);
                    for name in names {
                        files.push((name, None));
                    }
                } else if let Some((kind, content)) = batch.get(&format!("{}:{}", full, path)) {
                    if kind == "blob" {
                        files.push((path.clone(), Some(content)));
                    }
                }
            }
        }
        files.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
        files.dedup_by(|a, b| a.0 == b.0);
        let main = files.iter().find(|(p, _)| is_main_path(p));
        let record = main.map(|(_, content)| {
            let text = String::from_utf8_lossy(content.as_deref().unwrap_or(&[])).into_owned();
            parse_text(&text).unwrap_or_else(|_| ctx::exit(5))
        });
        let archived = main.map(|(p, _)| p.starts_with("archive/")).unwrap_or(false);
        let comments = files
            .iter()
            .find(|(p, _)| p.ends_with(".comments.jsonl"))
            .map(|(_, c)| comments_of(&String::from_utf8_lossy(c.as_deref().unwrap_or(&[]))))
            .unwrap_or_default();
        let attachments: Vec<String> = files
            .iter()
            .filter(|(p, _)| p.starts_with("attachments/") || p.starts_with("archive/attachments/"))
            .map(|(p, _)| p.rsplit('/').next().unwrap_or("").to_string())
            .collect();
        versions.push(Version { commit, at, author, subject, archived, record, comments, attachments });
    }
    drop(batch);
    let empty = Version {
        commit: String::new(),
        at: String::new(),
        author: String::new(),
        subject: String::new(),
        archived: false,
        record: None,
        comments: Map::new(),
        attachments: Vec::new(),
    };
    let mut out = Vec::new();
    for (i, now) in versions.iter().enumerate() {
        let was = versions.get(i + 1).unwrap_or(&empty);
        let null = Value::Null;
        let now_record = now.record.as_ref().unwrap_or(&null);
        let was_record = was.record.as_ref().unwrap_or(&null);
        let mut entry = Map::new();
        entry.insert("commit", Value::str(&now.commit));
        entry.insert("at", Value::str(&now.at));
        entry.insert("author", Value::str(&now.author));
        entry.insert("subject", Value::str(&now.subject));
        entry.insert("id", now_record.get("id").alt(was_record.get("id")).clone());
        entry.insert("session", now_record.get("session").alt(&Value::Null).clone());
        let moved_now = now_record.get("moved").alt(&Value::Null).clone();
        let moved_was = was_record.get("moved").alt(&Value::Null).clone();
        let by = if moved_now != moved_was { now_record.get("moved_by").alt(&Value::Null).clone() } else { Value::Null };
        entry.insert("by", by);
        entry.insert("created", Value::Bool(was.record.is_none() && now.record.is_some()));
        let mut changes = if was.record.is_none() { Vec::new() } else { changed(was_record, now_record) };
        if was.archived != now.archived && was.record.is_some() {
            let mut change = Map::new();
            change.insert("field", Value::str("archived"));
            change.insert("from", Value::Bool(was.archived));
            change.insert("to", Value::Bool(now.archived));
            changes.push(Value::Obj(change));
        }
        entry.insert("changes", Value::Arr(changes));
        let body_was = was_record.get("body").alt(&Value::str("")).clone();
        let body_now = now_record.get("body").alt(&Value::str("")).clone();
        let body = if body_was != body_now && was.record.is_some() {
            let mut body = Map::new();
            body.insert("from", body_was);
            body.insert("to", body_now);
            Value::Obj(body)
        } else {
            Value::Null
        };
        entry.insert("body", body);
        let mut comments = Vec::new();
        for (_, comment) in &now.comments.entries {
            let key = comment.get("id").tostring();
            let Some(old) = was.comments.get(&key) else {
                comments.push(comment_entry("added", comment, comment.get("text")));
                continue;
            };
            if comment.get("deleted").truthy() && !old.get("deleted").truthy() {
                comments.push(comment_entry("deleted", comment, old.get("text")));
            } else if comment.get("text") != old.get("text") {
                comments.push(comment_entry("edited", comment, comment.get("text")));
            } else if comment.get("resolved").truthy() != old.get("resolved").truthy() {
                let action = if comment.get("resolved").truthy() { "resolved" } else { "reopened" };
                comments.push(comment_entry(action, comment, comment.get("text")));
            }
        }
        for (_, comment) in &was.comments.entries {
            if now.comments.get(&comment.get("id").tostring()).is_none() {
                comments.push(comment_entry("removed", comment, comment.get("text")));
            }
        }
        entry.insert("comments", Value::Arr(comments));
        let mut attachments = Vec::new();
        for name in now.attachments.iter().filter(|n| !was.attachments.contains(n)) {
            let mut item = Map::new();
            item.insert("action", Value::str("added"));
            item.insert("name", Value::str(name));
            attachments.push(Value::Obj(item));
        }
        for name in was.attachments.iter().filter(|n| !now.attachments.contains(n)) {
            let mut item = Map::new();
            item.insert("action", Value::str("removed"));
            item.insert("name", Value::str(name));
            attachments.push(Value::Obj(item));
        }
        entry.insert("attachments", Value::Arr(attachments));
        out.push(Value::Obj(entry));
    }
    Value::Arr(out)
}

pub fn history(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let mut as_json = false;
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "--json" => as_json = true,
            other => die(2, &format!("history takes an id and an optional --json, not '{}'", other)),
        }
    }
    require_history();
    if fs::metadata(git::held_file()).map(|m| m.len() > 0).unwrap_or(false) {
        ctx::with_mut(|s| s.flush_keys = git::key_of_id(&id));
        with_lock(|| {});
    }
    let paths = record_paths(&id, false);
    let plain = log("%h%x09%ad%x09%s", &paths, &[]);
    if !plain.ok || plain.stdout.trim().is_empty() {
        die(3, &format!("no history for {}", id));
    }
    if as_json {
        outln(&history_json(&paths).pretty());
        return;
    }
    ctx::out(&plain.stdout);
}

fn translate(path: &str) -> String {
    let main = ctx::ticket_dir();
    let archive = ctx::archive_ticket_dir();
    for folder in ["cards", "tickets"] {
        if let Some(rest) = path.strip_prefix(&format!("{}/", folder)) {
            return format!("{}/{}", main, rest);
        }
        if let Some(rest) = path.strip_prefix(&format!("archive/{}/", folder)) {
            return format!("archive/{}/{}", archive, rest);
        }
    }
    path.to_string()
}

fn rev(spec: &str) -> Option<String> {
    let run = git::run(&["rev-parse", "--quiet", "--verify", &format!("{}^{{commit}}", spec)]);
    if run.ok {
        Some(run.stdout.trim().to_string())
    } else {
        None
    }
}

fn live_cards(before_id: &str, archived: bool) -> HashMap<String, String> {
    let mut live = HashMap::new();
    for file in md_files(&directory_of_kind("card")) {
        let id = id_of_file(&file);
        if is_legacy_id(&id) {
            live.insert(number(&id).to_string(), id);
        }
    }
    if before_id.starts_with("FEAT-") || before_id.starts_with("BUG-") || before_id.starts_with("TIME-") {
        let n = before_id.split('-').nth(1).unwrap_or("").to_string();
        if archived {
            live.remove(&n);
        } else {
            live.insert(n, before_id.to_string());
        }
    }
    live
}

fn follow(record: &mut Value, live: &HashMap<String, String>, aliases: &Value) {
    let follow_one = |value: &Value| -> Value {
        let Value::Str(id) = value else { return value.clone() };
        let alias = aliases.get(id);
        if !alias.is_null() {
            return alias.clone();
        }
        if is_legacy_id(id) {
            if let Some(found) = live.get(number(id)) {
                return Value::str(found);
            }
        }
        value.clone()
    };
    for field in ["dependent_on", "dependency_for"] {
        if let Value::Arr(items) = record.get(field).clone() {
            record.set(field, Value::Arr(items.iter().map(follow_one).collect()));
        }
    }
    if !record.get("card").is_null() {
        let followed = follow_one(record.get("card"));
        record.set("card", followed);
    }
}

fn ids_of(record: &Value, field: &str) -> Vec<String> {
    match record.get(field) {
        Value::Arr(items) => items.iter().map(|v| v.tostring()).collect(),
        _ => Vec::new(),
    }
}

fn minus(a: &[String], b: &[String]) -> Vec<String> {
    a.iter().filter(|x| !b.contains(x)).cloned().collect()
}

fn owner(id: &str) -> String {
    if !ctx::env("TICKET_CLAIM_LOCK").is_empty() {
        return owner_of(id);
    }
    let directory = ctx::claim_dir();
    let _ = fs::create_dir_all(&directory);
    if let Ok(entries) = fs::read_dir(&directory) {
        let now = std::time::SystemTime::now();
        for entry in entries.flatten() {
            let Ok(meta) = entry.metadata() else { continue };
            if !meta.is_dir() {
                continue;
            }
            let age = meta.modified().ok().and_then(|m| now.duration_since(m).ok()).map(|d| d.as_secs() / 86400).unwrap_or(0);
            if age > 1 {
                let _ = fs::remove_dir_all(entry.path());
            }
        }
    }
    let file = format!("{}/{}/session", directory, id);
    util::read_text(&file).map(|t| t.trim_end_matches('\n').to_string()).unwrap_or_default()
}

struct Entry {
    full: String,
    short: String,
    line: String,
    files: Vec<String>,
}

struct Walk {
    child: Option<std::process::Child>,
    reader: Option<BufReader<std::process::ChildStdout>>,
    pending: Option<String>,
    entries: Vec<Entry>,
}

impl Walk {
    fn start() -> Walk {
        let mut command = git::bare(&["-C", &ctx::board_dir(), "log", "--format=%x01%H%x09%h%x09%s", "--name-only", "--no-renames"]);
        command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
        match command.spawn() {
            Ok(mut child) => {
                let reader = child.stdout.take().map(BufReader::new);
                Walk { child: Some(child), reader, pending: None, entries: Vec::new() }
            }
            Err(_) => Walk { child: None, reader: None, pending: None, entries: Vec::new() },
        }
    }

    fn read_line(&mut self) -> Option<String> {
        let reader = self.reader.as_mut()?;
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) | Err(_) => None,
            Ok(_) => Some(line.trim_end_matches('\n').to_string()),
        }
    }

    fn more(&mut self) -> bool {
        let header = match self.pending.take() {
            Some(header) => header,
            None => loop {
                match self.read_line() {
                    Some(line) if line.starts_with('\u{1}') => break line,
                    Some(_) => continue,
                    None => return false,
                }
            },
        };
        let mut parts = header[1..].splitn(3, '\t');
        let full = parts.next().unwrap_or("").to_string();
        let short = parts.next().unwrap_or("").to_string();
        let subject = parts.next().unwrap_or("").to_string();
        let mut files = Vec::new();
        while let Some(line) = self.read_line() {
            if line.starts_with('\u{1}') {
                self.pending = Some(line);
                break;
            }
            if !line.is_empty() {
                files.push(line);
            }
        }
        let line = format!("{} {}", short, subject);
        self.entries.push(Entry { full, short, line, files });
        true
    }

    fn last_touching(&mut self, paths: &[String]) -> Option<usize> {
        let mut index = 0;
        loop {
            while index >= self.entries.len() {
                if !self.more() {
                    return None;
                }
            }
            if touches(&self.entries[index].files, paths) {
                return Some(index);
            }
            index += 1;
        }
    }

    fn find(&mut self, full: &str) -> Option<usize> {
        let mut index = 0;
        loop {
            while index >= self.entries.len() {
                if !self.more() {
                    return None;
                }
            }
            if self.entries[index].full == full {
                return Some(index);
            }
            index += 1;
        }
    }
}

impl Drop for Walk {
    fn drop(&mut self) {
        drop(self.reader.take());
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

fn under(file: &str, path: &str) -> bool {
    file == path || (file.starts_with(path) && file.as_bytes().get(path.len()) == Some(&b'/'))
}

fn touches(files: &[String], paths: &[String]) -> bool {
    files.iter().any(|f| paths.iter().any(|p| under(f, p)))
}

struct Undoing {
    since: String,
    until: String,
    walk: Walk,
    batch: Option<Batch>,
    until_resolved: Option<Option<String>>,
    since_resolved: Option<Option<String>>,
    since_changed: Option<Vec<String>>,
}

impl Undoing {
    fn until(&mut self) -> Option<String> {
        if self.until_resolved.is_none() {
            self.until_resolved = Some(rev(&self.until));
        }
        self.until_resolved.clone().unwrap()
    }

    fn since(&mut self) -> Option<String> {
        if self.since_resolved.is_none() {
            self.since_resolved = Some(rev(&self.since));
        }
        self.since_resolved.clone().unwrap()
    }

    fn changed_since(&mut self, base: &str) -> Vec<String> {
        if self.since_changed.is_none() {
            let run = git::run(&["diff", "--name-only", "--no-renames", base, "HEAD"]);
            self.since_changed = Some(util::lines(&run.stdout));
        }
        self.since_changed.clone().unwrap()
    }

    fn blob(&mut self, spec: &str) -> Option<Vec<u8>> {
        if self.batch.is_none() {
            self.batch = Batch::start();
        }
        let (kind, content) = self.batch.as_mut()?.get(spec)?;
        if kind == "blob" {
            Some(content)
        } else {
            None
        }
    }
}

struct Plan {
    before_id: String,
    archived: bool,
    changed: Vec<(String, Option<Vec<u8>>)>,
    restored: Value,
    links: Vec<(String, String, bool)>,
    session: String,
    owner: String,
    subject: String,
}

fn plan_undo(id: &str, undoing: &mut Undoing) -> Plan {
    let paths = record_paths(id, false);
    let Some(index) = undoing.walk.last_touching(&paths) else {
        die(2, &format!("{} has no committed version to go back to", id))
    };
    let commit = undoing.walk.entries[index].full.clone();
    if !undoing.until.is_empty() {
        let Some(resolved) = undoing.until() else { die(2, &format!("the board has no commit '{}'", undoing.until)) };
        if resolved != commit {
            die(2, &format!("{} changed after that, in {} - undoing it now would take that change back too", id, undoing.walk.entries[index].line));
        }
    }
    let (base, subject, changed_paths) = if !undoing.since.is_empty() {
        let since = undoing.since.clone();
        let Some(base) = undoing.since() else { die(2, &format!("the board has no commit '{}'", since)) };
        let Some(base_index) = undoing.walk.find(&base).filter(|b| *b >= index) else {
            die(2, &format!("{} is not in {}'s history", since, id))
        };
        let count = undoing.walk.entries[index..base_index].iter().filter(|e| touches(&e.files, &paths)).count();
        if count == 0 {
            die(2, &format!("nothing to undo on {}: it has not changed since {}", id, since));
        }
        let short = undoing.walk.entries[base_index].short.clone();
        let changed: Vec<String> = undoing.changed_since(&base).into_iter().filter(|f| paths.iter().any(|p| under(f, p))).collect();
        (base, format!("{} changes since {}", count, short), changed)
    } else {
        let entry = &undoing.walk.entries[index];
        let changed: Vec<String> = entry.files.iter().filter(|f| paths.iter().any(|p| under(f, p))).cloned().collect();
        (format!("{}^", commit), entry.line.clone(), changed)
    };
    let mut before_file = String::new();
    let mut before_text: Vec<u8> = Vec::new();
    for path in record_paths(id, true) {
        if let Some(content) = undoing.blob(&format!("{}:{}", base, path)) {
            before_file = path;
            before_text = content;
        }
    }
    if before_file.is_empty() {
        die(2, &format!("{} has no version before {}, which made it", id, subject));
    }
    let before_id = id_of_file(&before_file);
    let archived = before_file.starts_with("archive/");
    let mut current_file = record_file(id);
    if !exists(&current_file) {
        current_file = archive_file(id);
    }
    let current = parse_file(&current_file);
    let Ok(mut restored) = parse_text(&String::from_utf8_lossy(&before_text)) else {
        die(8, &format!("{} as it stood before {} does not parse", before_file, subject))
    };
    let live = live_cards(&before_id, archived);
    follow(&mut restored, &live, &aliases_json());
    let board_prefix = format!("{}/", ctx::board_dir());
    let current_relative = current_file.strip_prefix(&board_prefix).unwrap_or(&current_file).to_string();
    let all_md = !changed_paths.is_empty()
        && changed_paths.iter().all(|p| {
            let rest = p.strip_prefix("archive/").unwrap_or(p);
            let check = |text: &str| -> bool {
                let Some(slash) = text.find('/') else { return false };
                let folder = &text[..slash];
                let Some(stem) = text[slash + 1..].strip_suffix(".md") else { return false };
                let Some((head, tail)) = stem.split_once('-') else { return false };
                !folder.is_empty()
                    && folder.bytes().all(|b| b.is_ascii_lowercase())
                    && !head.is_empty()
                    && head.bytes().all(|b| b.is_ascii_uppercase())
                    && !tail.is_empty()
                    && tail.bytes().all(|b| b.is_ascii_digit())
            };
            check(rest) || (p.starts_with("archive/") && check(p))
        });
    if translate(&before_file) == current_relative && all_md && same_but_updated(&current, &restored) {
        die(2, &format!("nothing to undo on {}: before {} it held what it holds now, once renamed tickets are followed", id, subject));
    }
    let owner = owner(id);
    let mut session = String::new();
    let mut links: Vec<(String, String, bool)> = Vec::new();
    if archived {
        if current_file != archive_file(id) {
            require_unnamed(id);
        }
    } else {
        for field in ["epic", "project", "sprint", "card"] {
            let wanted = restored.get(field);
            if !wanted.is_null() && wanted != current.get(field) {
                let reference = wanted.tostring();
                if !exists(&record_file(&reference)) {
                    die(2, &format!("undoing {} would bring back {}, which is not on the board", subject, reference));
                }
            }
        }
        let (rd, cd) = (ids_of(&restored, "dependent_on"), ids_of(&current, "dependent_on"));
        let (rf, cf) = (ids_of(&restored, "dependency_for"), ids_of(&current, "dependency_for"));
        for other in minus(&rd, &cd) {
            links.push((other, "dependency_for".into(), true));
        }
        for other in minus(&cd, &rd) {
            links.push((other, "dependency_for".into(), false));
        }
        for other in minus(&rf, &cf) {
            links.push((other, "dependent_on".into(), true));
        }
        for other in minus(&cf, &rf) {
            links.push((other, "dependent_on".into(), false));
        }
        for (other, _, add) in &links {
            if *add && !exists(&record_file(other)) {
                die(2, &format!("undoing {} would link {} to {}, which is not on the board", subject, before_id, other));
            }
        }
        session = match restored.get("session") {
            Value::Null | Value::Bool(false) => String::new(),
            other => other.tostring(),
        };
        if !session.is_empty() && !owner.is_empty() && owner != session {
            die(1, &format!("{} is held by session {}", id, owner));
        }
    }
    let changed: Vec<(String, Option<Vec<u8>>)> = changed_paths
        .into_iter()
        .map(|path| {
            let content = undoing.blob(&format!("{}:{}", base, path));
            (path, content)
        })
        .collect();
    Plan { before_id, archived, changed, restored, links, session, owner, subject }
}

fn apply_undo(id: &str, plan: Plan) {
    let board = ctx::board_dir();
    let mut targets: Vec<(String, Option<Vec<u8>>)> = Vec::new();
    for (path, content) in &plan.changed {
        let target = translate(path);
        match targets.iter_mut().find(|(t, _)| *t == target) {
            Some(slot) => {
                if slot.1.is_none() {
                    slot.1 = content.clone();
                }
            }
            None => targets.push((target, content.clone())),
        }
    }
    for (target, content) in &targets {
        let full = format!("{}/{}", board, target);
        match content {
            Some(content) => {
                if let Some(parent) = Path::new(&full).parent() {
                    let _ = fs::create_dir_all(parent);
                }
                let _ = fs::write(&full, content);
            }
            None => {
                let _ = fs::remove_file(&full);
                let is_attachment = (target.starts_with("attachments/") && target.matches('/').count() >= 2)
                    || (target.starts_with("archive/attachments/") && target.matches('/').count() >= 3);
                if is_attachment {
                    if let Some(parent) = Path::new(&full).parent() {
                        let _ = fs::remove_dir(parent);
                    }
                }
            }
        }
    }
    if !plan.archived {
        write_record(&plan.before_id, plan.restored.clone(), true, None);
    }
    if plan.before_id != id {
        renamed_to(id, &plan.before_id);
    }
    for (other, field, add) in &plan.links {
        if *add {
            link_side(other, field, &plan.before_id, true);
        } else if exists(&record_file(other)) {
            link_side(other, field, &plan.before_id, false);
        }
    }
    if plan.session.is_empty() && !plan.owner.is_empty() {
        claim_lock("release", &plan.before_id, Some(&plan.owner));
    } else if !plan.session.is_empty() && plan.owner.is_empty() {
        claim_lock("take", &plan.before_id, Some(&plan.session));
    }
    outln(&format!("{}\tundid {}", plan.before_id, plan.subject));
}

pub fn undo(args: &[String]) {
    let mut ids: Vec<String> = Vec::new();
    let mut at = 0;
    while at < args.len() && !args[at].starts_with("--") {
        let id = normalise_id(&args[at]);
        if !ids.contains(&id) {
            ids.push(id);
        }
        at += 1;
    }
    if ids.is_empty() {
        normalise_id("");
    }
    let first = ids[0].clone();
    let (mut since, mut until) = (String::new(), String::new());
    while at < args.len() {
        match args[at].as_str() {
            "--since" => {
                let value = args.get(at + 1).cloned().unwrap_or_default();
                if value.is_empty() {
                    die(2, &format!("--since needs a commit from: board-card history {}", first));
                }
                since = value;
                at += 2;
            }
            "--until" => {
                let value = args.get(at + 1).cloned().unwrap_or_default();
                if value.is_empty() {
                    die(2, "--until needs the last commit the change made");
                }
                until = value;
                at += 2;
            }
            other => die(2, &format!("undo takes an id, an optional --since <commit> and an optional --until <commit>, not '{}'", other)),
        }
    }
    if !until.is_empty() && since.is_empty() {
        die(2, "--until goes with --since");
    }
    require_history();
    ctx::set_flush_now();
    for id in &ids {
        if !exists(&record_file(id)) && exists(&archive_file(id)) {
            parse_file(&archive_file(id));
        } else {
            require_record(id);
        }
    }
    with_lock(|| {
        let mut undoing = Undoing {
            since: since.clone(),
            until: until.clone(),
            walk: Walk::start(),
            batch: None,
            until_resolved: None,
            since_resolved: None,
            since_changed: None,
        };
        if ids.len() > 1 {
            for id in &ids {
                plan_undo(id, &mut undoing);
            }
        }
        for id in &ids {
            let plan = plan_undo(id, &mut undoing);
            apply_undo(id, plan);
        }
    });
}
