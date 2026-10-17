use crate::board::{self, *};
use crate::ctx::{self, die, outln};
use crate::json::Value;
use crate::record::*;
use crate::util;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

pub fn strip_heading(heading: &str) -> String {
    let stripped = heading.trim_start_matches('#');
    stripped.strip_prefix(' ').unwrap_or(stripped).to_string()
}

fn heading_level(line: &str) -> Option<usize> {
    let hashes = line.bytes().take_while(|b| *b == b'#').count();
    if hashes > 0 && line.as_bytes().get(hashes) == Some(&b' ') {
        Some(hashes)
    } else {
        None
    }
}

pub fn section_lines(body: &str, wanted: &str) -> Vec<(usize, String)> {
    let mut lines: Vec<&str> = body.split('\n').collect();
    if body.is_empty() {
        lines = vec![""];
    }
    let mut fenced = false;
    let mut inside = false;
    let mut depth = 0;
    let mut out = Vec::new();
    for (index, line) in lines.iter().enumerate() {
        if line.starts_with("```") {
            fenced = !fenced;
        }
        if !fenced {
            if let Some(level) = heading_level(line) {
                let title = &line[level + 1..];
                if inside && level <= depth {
                    inside = false;
                }
                if title == wanted {
                    inside = true;
                    depth = level;
                }
            }
        }
        if inside {
            out.push((index + 1, line.to_string()));
        }
    }
    out
}

pub fn show(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let rest: Vec<String> = args.iter().skip(1).cloned().collect();
    require_record(&id);
    let mut record = read_record(&id);
    if kind_of(&id) == "card" {
        board::card_project(&mut record, &board::epic_projects());
    }
    if rest.first().map(|s| s.as_str()) == Some("--json") {
        board::derived(&mut record, &board::now());
        outln(&record.pretty());
        return;
    }
    if rest.first().map(|s| s.as_str()) == Some("--section") {
        let heading = strip_heading(rest.get(1).map(|s| s.as_str()).unwrap_or(""));
        let body = record.get("body").tostring();
        let numbered = section_lines(&body, &heading);
        if numbered.is_empty() {
            die(7, &format!("{} has no section '{}'", id, heading));
        }
        for (_, line) in &numbered {
            outln(line);
        }
        let threads = open_threads(&id);
        let numbers: Vec<usize> = numbered.iter().map(|(n, _)| *n).collect();
        if let Value::Arr(items) = &threads {
            for thread in items {
                let Value::Str(anchor) = thread.get("anchor") else { continue };
                if !body.contains(anchor.as_str()) {
                    continue;
                }
                let before = body.split(anchor.as_str()).next().unwrap_or("");
                let line = before.matches('\n').count() + 1;
                if !numbers.contains(&line) {
                    continue;
                }
                for comment in thread.get("comments").as_array().cloned().unwrap_or_default() {
                    outln(&format!("[comment] {}: {}", comment.get("author").tostring(), comment.get("text").tostring()));
                }
            }
            for thread in items {
                if !thread.get("anchor").is_null() {
                    continue;
                }
                for comment in thread.get("comments").as_array().cloned().unwrap_or_default() {
                    outln(&format!("[comment on the page] {}: {}", comment.get("author").tostring(), comment.get("text").tostring()));
                }
            }
        }
        return;
    }
    let properties: Vec<String> = if rest.is_empty() {
        ["Name", "Status", "Type", "Epic", "Agent: Session Id", "PRs", "Complexity", "Dependent on", "Dependency for"]
            .iter()
            .map(|s| s.to_string())
            .collect()
    } else {
        rest
    };
    require_properties(&properties);
    for property in &properties {
        let value = property_value(&record, property);
        if !value.is_empty() {
            outln(&format!("{}\t{}", property, value));
        }
    }
}

pub fn records_in(directory: &str) -> Vec<Value> {
    let files = md_files(directory);
    let parsed: Vec<Option<Result<Value, ()>>> = util::par_map(&files, |file| {
        let text = util::read_text(file)?;
        if text.is_empty() {
            return None;
        }
        Some(parse_text(&text))
    });
    let mut records = Vec::new();
    for (file, result) in files.iter().zip(parsed) {
        match result {
            None => {}
            Some(Ok(record)) => records.push(record),
            Some(Err(_)) => {
                parse_file(file);
                die(8, &format!("a record in {} does not parse", directory));
            }
        }
    }
    records
}

pub fn comment_counts(directory: &str) -> HashMap<String, usize> {
    let mut counts = HashMap::new();
    for file in util::glob(directory, |name| name.ends_with(".comments.jsonl")) {
        let name = file_name(&file);
        let id = name.strip_suffix(".comments.jsonl").unwrap_or(name).to_string();
        let comments = board::parse_comments(&file);
        counts.insert(id, board::open_thread_count(&comments));
    }
    counts
}

pub fn id_key(id: &str) -> (String, f64) {
    let mut parts = id.split('-');
    let prefix = parts.next().unwrap_or("").to_string();
    let number = parts.next().and_then(|n| n.parse().ok()).unwrap_or(f64::NAN);
    (prefix, number)
}

pub fn sort_by_id(records: &mut [Value]) {
    records.sort_by(|a, b| {
        let (pa, na) = id_key(a.get("id").str_or(""));
        let (pb, nb) = id_key(b.get("id").str_or(""));
        pa.as_bytes().cmp(pb.as_bytes()).then(na.partial_cmp(&nb).unwrap_or(std::cmp::Ordering::Equal))
    });
}

pub struct ListOptions {
    pub kind: String,
    pub status: String,
    pub epic: String,
    pub archived: bool,
}

pub fn list_records(options: &ListOptions) -> Vec<Value> {
    require_board();
    let directory = if options.archived { archive_directory_of_kind(&options.kind) } else { directory_of_kind(&options.kind) };
    let mut records = records_in(&directory);
    let counts = comment_counts(&directory);
    let projects = if options.kind == "card" { board::epic_projects() } else { HashMap::new() };
    for record in records.iter_mut() {
        board::card_project(record, &projects);
    }
    records.retain(|r| {
        (options.status.is_empty() || r.get("status").as_str() == Some(options.status.as_str()))
            && (options.epic.is_empty() || r.get("epic").as_str() == Some(options.epic.as_str()))
    });
    sort_by_id(&mut records);
    let now = board::now();
    for record in records.iter_mut() {
        board::derived(record, &now);
        let count = counts.get(record.get("id").str_or("")).copied().unwrap_or(0);
        record.set("comments", Value::int(count as i64));
    }
    records
}

pub fn list_kind(kind: &str) -> Vec<Value> {
    list_records(&ListOptions { kind: kind.to_string(), status: String::new(), epic: String::new(), archived: false })
}

pub fn list(args: &[String]) {
    let mut options = ListOptions { kind: "card".to_string(), status: String::new(), epic: String::new(), archived: false };
    let mut as_json = false;
    let mut at = 0;
    while at < args.len() {
        let next = || args.get(at + 1).cloned().unwrap_or_default();
        match args[at].as_str() {
            "--kind" => {
                options.kind = kind_arg(&next());
                at += 2;
            }
            "--status" => {
                options.status = next();
                at += 2;
            }
            "--epic" => {
                options.epic = normalise_id(&next());
                at += 2;
            }
            "--archived" => {
                options.archived = true;
                at += 1;
            }
            "--json" => {
                as_json = true;
                at += 1;
            }
            other => die(2, &format!("list: unknown option '{}'", other)),
        }
    }
    prefix_of_kind(&options.kind);
    if !options.status.is_empty() {
        require_column(&options.kind, &options.status);
    }
    let records = list_records(&options);
    if as_json {
        outln(&Value::Arr(records).pretty());
    } else {
        for record in &records {
            let status = record.get("status").alt(&Value::str("-")).clone();
            let session = record.get("session").alt(&Value::str("-")).clone();
            outln(&tsv(&[record.get("id").clone(), status, session, record.get("name").clone()]));
        }
    }
}

pub fn search(args: &[String]) {
    let text = args.first().cloned().unwrap_or_default();
    if text.is_empty() {
        die(2, "usage: board-card search <text> [--kind ticket|epic|project|sprint|reference|milestone]");
    }
    let mut kind = "card".to_string();
    let mut at = 1;
    while at < args.len() {
        match args[at].as_str() {
            "--kind" => {
                kind = kind_arg(&args.get(at + 1).cloned().unwrap_or_default());
                at += 2;
            }
            other => die(2, &format!("search: unknown option '{}'", other)),
        }
    }
    prefix_of_kind(&kind);
    require_board();
    let wanted = text.to_lowercase();
    let mut found: Vec<String> = Vec::new();
    for file in md_files(&directory_of_kind(&kind)) {
        let Some(content) = util::read_text(&file) else { continue };
        if !content.to_lowercase().contains(&wanted) {
            continue;
        }
        let lines = util::lines(&content);
        let mut inside = false;
        for (index, line) in lines.iter().enumerate() {
            if index == 0 {
                inside = line == "---";
                if inside {
                    continue;
                }
            } else if inside {
                if line == "---" {
                    inside = false;
                }
                continue;
            }
            if line.to_lowercase().contains(&wanted) {
                found.push(id_of_file(&file));
                break;
            }
        }
    }
    found.sort_by(|a, b| {
        let (pa, na) = id_key(a);
        let (pb, nb) = id_key(b);
        pa.as_bytes().cmp(pb.as_bytes()).then(na.partial_cmp(&nb).unwrap_or(std::cmp::Ordering::Equal)).then(a.cmp(b))
    });
    for id in found {
        outln(&id);
    }
}

pub fn statuses(args: &[String]) {
    let mut kind = "card".to_string();
    if args.first().map(|s| s.as_str()) == Some("--kind") {
        kind = kind_arg(&args.get(1).cloned().unwrap_or_default());
    }
    if !has_board(&kind) {
        die(2, "only tickets and epics have columns");
    }
    for column in walk_columns(&kind).iter().chain(parked_columns(&kind).iter()) {
        outln(column);
    }
}

pub fn path(args: &[String]) {
    match args.first() {
        Some(given) if !given.is_empty() => {
            let id = normalise_id(given);
            if !exists(&record_file(&id)) && exists(&archive_file(&id)) {
                outln(&archive_file(&id));
            } else {
                outln(&record_file(&id));
            }
        }
        _ => outln(&ctx::board_dir()),
    }
}

pub fn aliases_json() -> Value {
    let mut map = crate::json::Map::new();
    for line in alias_lines() {
        let mut parts = line.split('\t');
        let from = parts.next().unwrap_or("").to_string();
        let to = parts.next().map(Value::str).unwrap_or(Value::Null);
        map.insert(&from, to);
    }
    Value::Obj(map)
}

pub fn aliases(args: &[String]) {
    match args.first().map(|s| s.as_str()) {
        None | Some("") if args.len() <= 1 => {
            if let Some(text) = util::read_text(&aliases_file()) {
                ctx::out(&text);
            }
        }
        Some("--json") => outln(&aliases_json().pretty()),
        _ => die(2, "usage: board-card aliases [--json]"),
    }
}

fn hash_bytes(hash: &mut u64, bytes: &[u8]) {
    for byte in bytes {
        *hash ^= *byte as u64;
        *hash = hash.wrapping_mul(0x100000001b3);
    }
}

fn pruned(name: &str) -> bool {
    if name == ".git" || name == ".lock" {
        return true;
    }
    if let Some(rest) = name.strip_prefix('.') {
        if let Some(dot) = rest.rfind('.') {
            return rest[dot + 1..].chars().count() == 6;
        }
    }
    false
}

fn collect_files(directory: &Path, out: &mut Vec<(String, u64, u64)>) {
    let Ok(entries) = fs::read_dir(directory) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if pruned(&name) {
            continue;
        }
        let path = entry.path();
        let Ok(kind) = entry.file_type() else { continue };
        if kind.is_dir() {
            collect_files(&path, out);
        } else if kind.is_file() {
            let Ok(bytes) = fs::read(&path) else { continue };
            let mut hash: u64 = 0xcbf29ce484222325;
            hash_bytes(&mut hash, &bytes);
            out.push((path.to_string_lossy().into_owned(), bytes.len() as u64, hash));
        }
    }
}

pub fn revision() {
    require_board();
    let mut files = Vec::new();
    collect_files(Path::new(&ctx::board_dir()), &mut files);
    files.sort();
    let mut hash: u64 = 0xcbf29ce484222325;
    for (path, size, content) in files {
        hash_bytes(&mut hash, path.as_bytes());
        hash_bytes(&mut hash, &size.to_le_bytes());
        hash_bytes(&mut hash, &content.to_le_bytes());
    }
    outln(&format!("{}", hash >> 32));
}

pub fn comments(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let mut all = false;
    let mut as_json = false;
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "--all" => all = true,
            "--json" => as_json = true,
            other => die(2, &format!("comments: unknown option '{}'", other)),
        }
    }
    require_record(&id);
    let file = comments_file(&id);
    let threads = if exists(&file) { board::threads(&board::parse_comments(&file), all) } else { Value::Arr(Vec::new()) };
    if as_json {
        outln(&threads.pretty());
        return;
    }
    for thread in threads.as_array().cloned().unwrap_or_default() {
        let resolved = if thread.get("resolved").truthy() { " (resolved)" } else { "" };
        let place = match thread.get("anchor") {
            anchor if anchor.truthy() => format!("\"{}\"", anchor.tostring()),
            _ => "the page".to_string(),
        };
        outln(&format!("{}{} on {}", thread.get("thread").tostring(), resolved, place));
        for comment in thread.get("comments").as_array().cloned().unwrap_or_default() {
            let text = comment.get("text").tostring().replace('\n', "\n    ");
            outln(&format!("  {} {}: {}", comment.get("id").tostring(), comment.get("author").tostring(), text));
        }
    }
}

pub fn attachments(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let mut directory = format!("{}/attachments/{}", ctx::board_dir(), id);
    if !exists(&record_file(&id)) {
        if !exists(&archive_file(&id)) {
            die(3, &format!("no entity {} in {}", id, directory_of_kind(kind_of(&id))));
        }
        directory = format!("{}/archive/attachments/{}", ctx::board_dir(), id);
    }
    let Ok(entries) = fs::read_dir(&directory) else { return };
    let mut names: Vec<String> = entries
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
        .map(|e| format!("{}/{}", directory, e.file_name().to_string_lossy()))
        .collect();
    names.sort();
    for name in names {
        outln(&name);
    }
}
