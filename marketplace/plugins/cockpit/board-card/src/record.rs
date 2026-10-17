use crate::ctx::{self, die};
use crate::json::{quote, Map, Value};
use crate::util;
use std::fs;
use std::path::Path;

pub const CARD_COLUMNS: &[&str] = &[
    "Backlog",
    "Ready for BR by AI",
    "In BR by AI",
    "Ready for BR",
    "In BR",
    "Ready for TR by AI",
    "In TR by AI",
    "Ready for TR",
    "In TR",
    "Ready for Sprint",
    "Sprint Backlog",
    "Daily Plan",
    "In Dev",
    "In CR by AI",
    "Ready for CR",
    "In CR",
    "Ready for FR",
    "In FR",
    "Ready for Validation",
    "Done",
];

pub const CARD_PARKED: &[&str] = &["Deprioritised"];

pub const CARD_STAMPED: &[&str] = &[
    "Ready for BR",
    "In BR",
    "Ready for TR by AI",
    "Ready for TR",
    "In TR",
    "Ready for Sprint",
    "In Dev",
    "Ready for CR",
    "In CR",
    "Ready for FR",
    "In FR",
    "Ready for Validation",
    "Done",
];

pub const EPIC_COLUMNS: &[&str] = &[
    "Backlog",
    "Ready for FD by AI",
    "In FD by AI",
    "Ready for FD",
    "In FD",
    "Ready for TD by AI",
    "In TD by AI",
    "Ready for TD",
    "In TD",
    "Ready for Ticket Breakdown by AI",
    "In Ticket Breakdown by AI",
    "Ready for Ticket Breakdown",
    "In Ticket Breakdown",
    "Ready for Dev",
    "Tickets In Dev",
    "Epic Done",
];

pub const WAITING_COLUMNS: &[&str] = &[
    "Ready for BR",
    "Ready for TR",
    "Ready for CR",
    "Ready for FR",
    "Ready for Validation",
    "Ready for FD",
    "Ready for TD",
    "Ready for Ticket Breakdown",
];

pub const FIBONACCI: &str = " 0 1 2 3 5 8 13 21 34 ";
pub const GATES: &str = " BR TR Dev CR FR Validation ";
pub const MODEL_STAGES: &str = " BR TR Dev CR ";
pub const RESERVED_KEYS: &str = " EPIC PRJ SPR REF MS FEAT BUG TIME ";

pub fn kind_arg(given: &str) -> String {
    if given == "ticket" {
        "card".to_string()
    } else {
        given.to_string()
    }
}

pub fn prefix_of_kind(kind: &str) -> &'static str {
    match kind {
        "card" => "TICKET",
        "epic" => "EPIC",
        "project" => "PRJ",
        "sprint" => "SPR",
        "reference" => "REF",
        "milestone" => "MS",
        other => die(2, &format!("kind is ticket, epic, project, sprint, reference or milestone, not '{}'", other)),
    }
}

pub fn prefix(id: &str) -> &str {
    id.split('-').next().unwrap_or("")
}

pub fn number(id: &str) -> &str {
    id.rsplit('-').next().unwrap_or("")
}

pub fn kind_of(id: &str) -> &'static str {
    let p = prefix(id);
    match p {
        "EPIC" => "epic",
        "PRJ" => "project",
        "SPR" => "sprint",
        "REF" => "reference",
        "MS" => "milestone",
        _ if (2..=4).contains(&p.len()) && p.bytes().all(|b| b.is_ascii_uppercase()) => "card",
        _ => die(2, &format!("no board holds ids starting '{}-'", p)),
    }
}

pub fn folder_of_kind(kind: &str) -> String {
    match kind {
        "card" => ctx::ticket_dir(),
        "epic" => "epics".to_string(),
        "project" => "projects".to_string(),
        "sprint" => "sprints".to_string(),
        "reference" => "references".to_string(),
        "milestone" => "milestones".to_string(),
        _ => String::new(),
    }
}

pub fn archive_folder_of_kind(kind: &str) -> String {
    match kind {
        "card" => ctx::archive_ticket_dir(),
        other => folder_of_kind(other),
    }
}

pub fn directory_of_kind(kind: &str) -> String {
    format!("{}/{}", ctx::board_dir(), folder_of_kind(kind))
}

pub fn archive_directory_of_kind(kind: &str) -> String {
    format!("{}/archive/{}", ctx::board_dir(), archive_folder_of_kind(kind))
}

pub fn kind_name(kind: &str) -> &str {
    if kind == "card" {
        "ticket"
    } else {
        kind
    }
}

pub fn walk_columns(kind: &str) -> &'static [&'static str] {
    match kind {
        "card" => CARD_COLUMNS,
        "epic" => EPIC_COLUMNS,
        _ => &[],
    }
}

pub fn parked_columns(kind: &str) -> &'static [&'static str] {
    match kind {
        "card" => CARD_PARKED,
        _ => &[],
    }
}

pub fn column_index(kind: &str, wanted: &str) -> Option<usize> {
    walk_columns(kind).iter().position(|c| *c == wanted)
}

pub fn is_parked(kind: &str, column: &str) -> bool {
    parked_columns(kind).contains(&column)
}

pub fn is_stamped(kind: &str, column: &str) -> bool {
    kind == "epic" || CARD_STAMPED.contains(&column)
}

pub fn has_board(kind: &str) -> bool {
    kind == "card" || kind == "epic"
}

pub fn require_column(kind: &str, column: &str) {
    if !has_board(kind) {
        return;
    }
    if column_index(kind, column).is_some() || is_parked(kind, column) {
        return;
    }
    let all: Vec<&str> = walk_columns(kind).iter().chain(parked_columns(kind).iter()).copied().collect();
    die(2, &format!("not a {} column: '{}' - one of: {}", kind, column, all.join(", ")));
}

pub fn is_id_shape(id: &str) -> bool {
    let Some((head, tail)) = id.split_once('-') else { return false };
    let mut chars = head.chars();
    match chars.next() {
        Some(c) if c.is_ascii_uppercase() => {}
        _ => return false,
    }
    if !chars.all(|c| c.is_ascii_uppercase() || c.is_ascii_digit()) {
        return false;
    }
    !tail.is_empty() && tail.bytes().all(|b| b.is_ascii_digit())
}

pub fn is_ticket_id(id: &str) -> bool {
    let Some((head, tail)) = id.split_once('-') else { return false };
    if !(2..=4).contains(&head.len()) || !head.bytes().all(|b| b.is_ascii_uppercase()) {
        return false;
    }
    if tail.is_empty() || !tail.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    !matches!(head, "EPIC" | "PRJ" | "SPR" | "REF" | "MS")
}

pub fn is_legacy_id(id: &str) -> bool {
    let Some((head, tail)) = id.split_once('-') else { return false };
    matches!(head, "FEAT" | "BUG" | "TIME") && !tail.is_empty() && tail.bytes().all(|b| b.is_ascii_digit())
}

pub fn upper(text: &str) -> String {
    text.chars().map(|c| c.to_ascii_uppercase()).collect()
}

pub fn lower(text: &str) -> String {
    text.chars().map(|c| c.to_ascii_lowercase()).collect()
}

pub fn normalise_id(given: &str) -> String {
    let id = upper(given);
    if !is_id_shape(&id) {
        die(2, &format!("not a board id: '{}'", given));
    }
    if kind_of(&id) == "card" && !exists(&record_file(&id)) && !exists(&archive_file(&id)) {
        if let Some(alias) = alias_of(&id) {
            return alias;
        }
    }
    id
}

pub fn exists(path: &str) -> bool {
    Path::new(path).is_file()
}

pub fn aliases_file() -> String {
    format!("{}/aliases", ctx::board_dir())
}

pub fn alias_lines() -> Vec<String> {
    match fs::read(aliases_file()) {
        Ok(bytes) => util::lines(&String::from_utf8_lossy(&bytes)),
        Err(_) => Vec::new(),
    }
}

fn fields(line: &str) -> (&str, &str) {
    let mut parts = line.split('\t');
    let first = parts.next().unwrap_or("");
    let second = parts.next().unwrap_or("");
    (first, second)
}

pub fn alias_of(id: &str) -> Option<String> {
    for line in alias_lines() {
        let (from, to) = fields(&line);
        if from == id {
            return Some(to.to_string());
        }
    }
    None
}

pub fn aliases_to(id: &str) -> Vec<String> {
    alias_lines().into_iter().filter(|line| fields(line).1 == id).map(|line| fields(&line).0.to_string()).collect()
}

pub fn record_alias(to: &str, froms: &[String]) {
    let file = aliases_file();
    let mut lines: Vec<String> = Vec::new();
    if exists(&file) {
        for line in alias_lines() {
            let (first, second) = fields(&line);
            if first == to || froms.iter().any(|f| f == first) {
                continue;
            }
            if froms.iter().any(|f| f == second) {
                let mut parts: Vec<&str> = line.split('\t').collect();
                if parts.len() < 2 {
                    parts.push(to);
                } else {
                    parts[1] = to;
                }
                lines.push(parts.join("\t"));
            } else {
                lines.push(line.clone());
            }
        }
    }
    for from in froms {
        lines.push(format!("{}\t{}", from, to));
    }
    util::version_sort(&mut lines);
    let mut text = lines.join("\n");
    text.push('\n');
    let staging = format!("{}.new", file);
    if fs::write(&staging, text).is_err() || fs::rename(&staging, &file).is_err() {
        die(1, &format!("could not write {}", file));
    }
}

pub fn record_file(id: &str) -> String {
    format!("{}/{}.md", directory_of_kind(kind_of(id)), id)
}

pub fn comments_file(id: &str) -> String {
    format!("{}/{}.comments.jsonl", directory_of_kind(kind_of(id)), id)
}

pub fn archive_file(id: &str) -> String {
    format!("{}/{}.md", archive_directory_of_kind(kind_of(id)), id)
}

pub fn require_record(id: &str) {
    if exists(&record_file(id)) {
        read_record(id);
        return;
    }
    if exists(&archive_file(id)) {
        die(3, &format!("{} is archived - run: board-card unarchive {}", id, id));
    }
    die(3, &format!("no entity {} in {}", id, directory_of_kind(kind_of(id))));
}

pub fn require_board() {
    let dir = ctx::board_dir();
    if !Path::new(&format!("{}/cards", dir)).is_dir() {
        die(3, &format!("no board at {} - run: board-card init", dir));
    }
}

pub fn has_ticket_folder() -> bool {
    let dir = ctx::board_dir();
    Path::new(&format!("{}/cards", dir)).is_dir()
}

fn capture_nested(line: &str) -> Option<(String, String)> {
    let rest = line.strip_prefix("  ")?;
    if !rest.starts_with('"') {
        return None;
    }
    let bytes = rest.as_bytes();
    let mut at = 1;
    loop {
        if at >= bytes.len() {
            return None;
        }
        match bytes[at] {
            b'\\' => {
                if at + 1 >= bytes.len() {
                    return None;
                }
                at += 2;
            }
            b'"' => break,
            _ => at += 1,
        }
    }
    let key = &rest[..=at];
    let after = &rest[at + 1..];
    let value = after.strip_prefix(": ")?;
    Some((key.to_string(), value.to_string()))
}

fn capture_top(line: &str) -> Option<(String, Option<String>)> {
    let colon = line.find(':')?;
    let key = &line[..colon];
    if key.is_empty() || !key.bytes().all(|b| b.is_ascii_lowercase() || b == b'_') {
        return None;
    }
    let rest = &line[colon + 1..];
    if rest.is_empty() {
        return Some((key.to_string(), None));
    }
    let value = rest.strip_prefix(' ')?;
    Some((key.to_string(), Some(value.to_string())))
}

pub fn parse_text(text: &str) -> Result<Value, ()> {
    let lines = util::lines(text);
    let marks: Vec<usize> = lines.iter().enumerate().filter(|(_, l)| l.as_str() == "---").map(|(i, _)| i).collect();
    let first = marks.first().map(|m| m + 1).unwrap_or(1);
    let front_end = marks.get(1).copied().unwrap_or(lines.len()).min(lines.len());
    let front: &[String] = if first < front_end { &lines[first..front_end] } else { &[] };
    let body_start = marks.get(1).map(|m| m + 1).unwrap_or(1).min(lines.len());
    let body_lines = &lines[body_start..];
    let body = body_lines.join("\n");
    let body = body.trim_start_matches('\n').trim_end_matches('\n').to_string();
    let mut state: Option<(Map, Option<String>)> = Some((Map::new(), None));
    for line in front {
        if line.starts_with("  ") {
            let Some((key, value)) = capture_nested(line) else {
                state = None;
                continue;
            };
            let key = match Value::parse(&key)? {
                Value::Str(s) => s,
                _ => return Err(()),
            };
            let value = Value::parse(&value)?;
            let Some((object, nested)) = state.as_mut() else { return Err(()) };
            let Some(nested) = nested.clone() else { return Err(()) };
            match object.get_mut(&nested) {
                Some(Value::Obj(inner)) => inner.insert(&key, value),
                Some(Value::Null) | None => {
                    let mut inner = Map::new();
                    inner.insert(&key, value);
                    object.insert(&nested, Value::Obj(inner));
                }
                _ => return Err(()),
            }
        } else {
            let Some((key, value)) = capture_top(line) else {
                state = None;
                continue;
            };
            let value_text = value.unwrap_or_default();
            let (mut object, _) = state.take().unwrap_or((Map::new(), None));
            if value_text.is_empty() {
                object.insert(&key, Value::obj());
                state = Some((object, Some(key)));
            } else {
                let parsed = Value::parse(&value_text)?;
                object.insert(&key, parsed);
                state = Some((object, None));
            }
        }
    }
    let mut object = match state {
        Some((object, _)) => object,
        None => Map::new(),
    };
    object.insert("body", Value::Str(body));
    Ok(Value::Obj(object))
}

pub fn file_name(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

pub fn parse_file(path: &str) -> Value {
    let text = match fs::read(path) {
        Ok(bytes) => String::from_utf8_lossy(&bytes).into_owned(),
        Err(_) => die(8, &format!("{} does not parse - fix its front matter by hand: {}", file_name(path), path)),
    };
    match parse_text(&text) {
        Ok(value) => value,
        Err(_) => die(8, &format!("{} does not parse - fix its front matter by hand: {}", file_name(path), path)),
    }
}

pub fn read_record(id: &str) -> Value {
    parse_file(&record_file(id))
}

const ORDER: &[&str] = &[
    "id", "name", "icon", "type", "status", "epic", "project", "sprint", "due", "urgent", "labels", "blocked",
    "dependent_on", "dependency_for", "complexity", "estimate", "session", "claimed_at", "prs", "cost_usd", "tokens_k",
    "created", "moved", "updated", "rank", "models", "back_from", "reference", "dates",
];

pub fn render(record: &Value) -> String {
    let map = record.as_obj().cloned().unwrap_or_default();
    let mut keys: Vec<String> = ORDER.iter().map(|k| k.to_string()).collect();
    for key in map.keys_sorted() {
        if !ORDER.contains(&key.as_str()) && key != "body" {
            keys.push(key);
        }
    }
    let mut lines = vec!["---".to_string()];
    for key in &keys {
        let Some(value) = map.get(key) else { continue };
        match value {
            Value::Obj(inner) if !inner.is_empty() => {
                lines.push(format!("{}:", key));
                for (k, v) in &inner.entries {
                    lines.push(format!("  {}: {}", quote(k), v.compact()));
                }
            }
            other => lines.push(format!("{}: {}", key, other.compact())),
        }
    }
    lines.push("---".to_string());
    let body = record.get("body");
    let empty = match body {
        Value::Null => true,
        Value::Str(s) => s.is_empty(),
        _ => false,
    };
    if !empty {
        lines.push(String::new());
        lines.push(body.tostring());
    }
    let mut text = lines.join("\n");
    text.push('\n');
    text
}

fn without_updated(value: &Value) -> Value {
    let mut copy = value.clone();
    copy.del("updated");
    copy
}

pub fn same_but_updated(a: &Value, b: &Value) -> bool {
    without_updated(a) == without_updated(b)
}

pub fn write_record(id: &str, record: Value, touch: bool, file: Option<&str>) {
    let file = file.map(|f| f.to_string()).unwrap_or_else(|| record_file(id));
    let mut record = record;
    if !matches!(record, Value::Obj(_)) {
        die(2, &format!("refused to write {} with nothing in it", id));
    }
    let body = match record.get("body") {
        Value::Null | Value::Bool(false) => String::new(),
        Value::Str(s) => s.clone(),
        _ => die(2, &format!("refused to write {} with nothing in it", id)),
    };
    record.set("body", Value::Str(body.trim_start_matches('\n').trim_end_matches('\n').to_string()));
    if exists(&file) {
        let current = parse_file(&file);
        if !touch && same_but_updated(&current, &record) {
            return;
        }
    }
    let directory = Path::new(&file).parent().map(|p| p.to_path_buf()).unwrap_or_default();
    let _ = fs::create_dir_all(&directory);
    record.set("updated", Value::Str(crate::time::now_stamp()));
    let text = render(&record);
    let directory_text = directory.to_string_lossy().into_owned();
    let temporary = match util::temp_file(&directory_text, &format!(".{}.", id)) {
        Some(path) => path,
        None => die(2, &format!("could not write {}: {} refused a new file", id, directory_text)),
    };
    if fs::write(&temporary, text).is_err() {
        let _ = fs::remove_file(&temporary);
        die(2, &format!("refused to write {} with nothing in it", id));
    }
    if fs::rename(&temporary, &file).is_err() {
        let _ = fs::remove_file(&temporary);
        die(1, &format!("could not write {}", file));
    }
}

pub fn touch_record(id: &str) {
    let record = read_record(id);
    write_record(id, record, true, None);
}

pub fn update_record(id: &str, change: impl FnOnce(&mut Value)) {
    let mut record = read_record(id);
    change(&mut record);
    write_record(id, record, false, None);
}

pub fn md_files(directory: &str) -> Vec<String> {
    util::glob(directory, |name| name.ends_with(".md"))
}

pub fn front_matter_values(key: &str, files: &[String]) -> Vec<(String, String)> {
    let prefix = format!("{}: ", key);
    let mut found = Vec::new();
    for file in files {
        let Ok(bytes) = fs::read(file) else { continue };
        let text = String::from_utf8_lossy(&bytes);
        let mut fences = 0;
        for line in util::lines(&text) {
            if line == "---" {
                fences += 1;
                continue;
            }
            if fences == 1 && line.starts_with(&prefix) {
                found.push((file.clone(), line[prefix.len()..].to_string()));
            }
        }
    }
    found
}

pub fn id_of_file(path: &str) -> String {
    let name = file_name(path);
    name.strip_suffix(".md").unwrap_or(name).to_string()
}

pub fn ticket_files_with_archive() -> Vec<String> {
    let mut files = md_files(&directory_of_kind("card"));
    files.extend(md_files(&archive_directory_of_kind("card")));
    files
}
