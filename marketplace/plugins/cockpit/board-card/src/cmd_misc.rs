use crate::board::{self, *};
use crate::cmd_read::list_kind;
use crate::cmd_write::{create_locked, hold_card, hop, read_stdin};
use crate::ctx::{self, die, outln};
use crate::git::{self, with_lock};
use crate::json::{jq_cmp, Map, Value};
use crate::record::*;
use crate::time;
use crate::util;
use std::cmp::Ordering;
use std::fs;

const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

fn is_maintenance(record: &Value) -> bool {
    matches!(record.get("maintenance"), Value::Str(_))
        && match record.get("labels") {
            Value::Arr(items) => items.iter().any(|v| v.as_str() == Some("maintenance")),
            Value::Obj(map) => map.entries.iter().any(|(_, v)| v.as_str() == Some("maintenance")),
            _ => false,
        }
}

fn maintenance_files() -> Vec<String> {
    let mut files: Vec<String> = md_files(&directory_of_kind("epic"))
        .into_iter()
        .filter(|f| util::read_text(f).map(|t| util::lines(&t).iter().any(|l| l.starts_with("maintenance: "))).unwrap_or(false))
        .collect();
    util::version_sort(&mut files);
    files
}

fn open_maintenance_files() -> Vec<String> {
    let mut files: Vec<String> = maintenance_files()
        .into_iter()
        .filter(|f| !util::read_text(f).map(|t| t.contains("status: \"Epic Done\"")).unwrap_or(false))
        .collect();
    util::version_sort(&mut files);
    files
}

fn open_cards_of(epic: &str) -> Vec<String> {
    let needle = format!("\"{}\"", epic);
    let mut files: Vec<String> = md_files(&directory_of_kind("card"))
        .into_iter()
        .filter(|f| util::read_text(f).map(|t| t.contains(&needle)).unwrap_or(false))
        .collect();
    util::version_sort(&mut files);
    let mut out = Vec::new();
    for file in files {
        let record = parse_file(&file);
        let status = record.get("status").as_str();
        if record.get("epic").as_str() == Some(epic) && status != Some("Done") && status != Some("Deprioritised") {
            out.push(id_of_file(&file));
        }
    }
    out
}

pub fn close_maintenance_locked() {
    let today: String = now().chars().take(10).collect();
    let month: String = today.chars().take(7).collect();
    for file in open_maintenance_files() {
        let record = parse_file(&file);
        if !(is_maintenance(&record)
            && record.get("status").as_str() != Some("Epic Done")
            && jq_cmp(record.get("maintenance"), &Value::str(&month)) == Ordering::Less)
        {
            continue;
        }
        let epic = id_of_file(&file);
        let cards = open_cards_of(&epic);
        if !cards.is_empty() {
            let project = match record.get("project") {
                Value::Null | Value::Bool(false) => String::new(),
                other => other.tostring(),
            };
            if project.is_empty() || !exists(&record_file(&project)) {
                continue;
            }
            let target = maintenance_epic_for(&project, &today);
            for card in &cards {
                update_record(card, |r| r.set("epic", Value::str(&target)));
                hold_card(card);
                outln(&format!("{}\tepic {} -> {}", card, epic, target));
            }
        }
        hop(&epic, "Epic Done");
    }
}

fn maintenance_epic_of(project: &str, month: &str) -> Option<String> {
    for file in open_maintenance_files() {
        let record = parse_file(&file);
        if is_maintenance(&record)
            && record.get("project").as_str() == Some(project)
            && record.get("maintenance").as_str() == Some(month)
            && record.get("status").as_str() != Some("Epic Done")
        {
            return Some(id_of_file(&file));
        }
    }
    None
}

fn maintenance_epic_for(project: &str, day: &str) -> String {
    let month: String = day.chars().take(7).collect();
    if let Some(id) = maintenance_epic_of(project, &month) {
        return id;
    }
    let index: usize = day.get(5..7).and_then(|m| m.parse::<usize>().ok()).unwrap_or(1);
    let name = format!("{} maintenance - {} {}", read_record(project).get("name").tostring(), MONTHS[index.clamp(1, 12) - 1], &day[0..4]);
    let mut fields = Map::new();
    fields.insert("project", Value::str(project));
    fields.insert("labels", Value::Arr(vec![Value::str("maintenance")]));
    fields.insert("maintenance", Value::str(&month));
    fields.insert("start", Value::str(day));
    create_locked("epic", &name, "", "Tickets In Dev", "", "", fields)
}

pub fn maintenance(args: &[String]) {
    let usage = "usage: board-card maintenance <PRJ-n> [--date YYYY-MM-DD] | maintenance --close";
    require_board();
    if args.first().map(|s| s.as_str()) == Some("--close") {
        if args.len() != 1 {
            die(2, usage);
        }
        with_lock(close_maintenance_locked);
        return;
    }
    let (mut project, mut day) = (String::new(), String::new());
    let mut at = 0;
    while at < args.len() {
        let arg = &args[at];
        if arg == "--date" {
            if at + 1 >= args.len() {
                die(2, "--date needs a day like 2026-10-12");
            }
            day = args[at + 1].clone();
            at += 2;
        } else if arg.starts_with('-') {
            die(2, usage);
        } else {
            if !project.is_empty() {
                die(2, usage);
            }
            project = arg.clone();
            at += 1;
        }
    }
    if project.is_empty() {
        die(2, usage);
    }
    let today: String = now().chars().take(10).collect();
    if day.is_empty() {
        day = today.clone();
    }
    date_value("a maintenance epic's day", &day);
    if day.chars().take(7).collect::<String>() < today.chars().take(7).collect::<String>() {
        day = today.clone();
    }
    let project = normalise_id(&project);
    if kind_of(&project) != "project" {
        die(2, &format!("a maintenance epic belongs to a project, and {} is not a project", project));
    }
    require_record(&project);
    if read_record(&project).get("status").str_or("") == "Done" {
        die(2, &format!("{} is Done, so it takes no maintenance epic - reopen it first with: board-card set {} status 'In progress'", project, project));
    }
    with_lock(|| {
        ctx::to_stderr(true);
        close_maintenance_locked();
        ctx::to_stderr(false);
        let id = maintenance_epic_for(&project, &day);
        outln(&id);
    });
}

fn views_file() -> String {
    format!("{}/views.json", ctx::board_dir())
}

fn views_text() -> String {
    util::read_text(&views_file()).unwrap_or_else(|| "[]\n".to_string())
}

fn views_value() -> Vec<Value> {
    match Value::parse(&views_text()) {
        Ok(Value::Arr(items)) => items,
        _ => Vec::new(),
    }
}

fn write_list(path: &str, items: Vec<Value>) {
    let staging = format!("{}.new", path);
    if items.is_empty() {
        let _ = fs::remove_file(path);
        let _ = fs::remove_file(&staging);
        return;
    }
    let text = format!("{}\n", Value::Arr(items).pretty());
    if !util::write_file(&staging, &text) || fs::rename(&staging, path).is_err() {
        die(1, &format!("could not write {}", path));
    }
}

pub fn views(args: &[String]) {
    let verb = args.first().cloned().unwrap_or_default();
    require_board();
    match verb.as_str() {
        "" | "--json" => {
            if args.len() > 1 {
                die(2, "usage: board-card views [--json]");
            }
            if verb == "--json" {
                ctx::out(&views_text());
            } else {
                for view in views_value() {
                    outln(&format!("{}\t{}", view.get("kind").tostring(), view.get("name").tostring()));
                }
            }
            return;
        }
        "save" | "delete" => {}
        _ => die(2, "usage: board-card views [--json] | views save [--kind ticket|epic] [--] <name> < <json> | views delete [--kind ticket|epic] [--] <name>"),
    }
    let mut name = String::new();
    let mut kind = "card".to_string();
    let mut at = 1;
    while at < args.len() {
        match args[at].as_str() {
            "--kind" => {
                if at + 1 >= args.len() {
                    die(2, "--kind needs ticket or epic");
                }
                kind = kind_arg(&args[at + 1]);
                at += 2;
            }
            "--" => {
                let rest = &args[at + 1..];
                if rest.len() > 1 {
                    die(2, &format!("a view takes one name after --, not {}", rest.len()));
                }
                if !name.is_empty() && !rest.is_empty() {
                    die(2, &format!("a view takes one name, not '{}' and '{}'", name, rest[0]));
                }
                if let Some(given) = rest.first() {
                    name = given.clone();
                }
                break;
            }
            other => {
                if !name.is_empty() {
                    die(2, &format!("a view takes one name, not '{}' and '{}'", name, other));
                }
                name = other.to_string();
                at += 1;
            }
        }
    }
    if name.is_empty() {
        die(2, "a view needs a name");
    }
    if name.contains('\n') {
        die(2, &format!("a view's name is one line, not '{}'", name));
    }
    if kind != "card" && kind != "epic" {
        die(2, &format!("a view belongs to the ticket board or the epics board, not '{}'", kind));
    }
    let matches = |view: &Value| view.get("name").as_str() == Some(name.as_str()) && view.get("kind").as_str() == Some(kind.as_str());
    if verb == "delete" {
        if !views_value().iter().any(matches) {
            die(3, &format!("no {} view is called '{}'", kind, name));
        }
        with_lock(|| {
            let kept: Vec<Value> = views_value().into_iter().filter(|v| !matches(v)).collect();
            write_list(&views_file(), kept);
        });
        return;
    }
    let input = read_stdin();
    let view = match Value::parse_many(&input) {
        Ok(values) if values.len() == 1 && matches!(values[0], Value::Obj(_)) => values.into_iter().next().unwrap(),
        _ => die(2, "a view is one JSON object on stdin"),
    };
    with_lock(|| {
        let mut kept: Vec<Value> = views_value().into_iter().filter(|v| !matches(v)).collect();
        let mut entry = Map::new();
        entry.insert("name", Value::str(&name));
        entry.insert("kind", Value::str(&kind));
        entry.insert("view", view);
        kept.push(Value::Obj(entry));
        write_list(&views_file(), kept);
    });
}

fn breaks_file() -> String {
    format!("{}/breaks", ctx::board_dir())
}

fn breaks_text() -> String {
    util::read_text(&breaks_file()).unwrap_or_else(|| "[]\n".to_string())
}

pub fn breaks_value() -> Vec<Value> {
    match Value::parse(&breaks_text()) {
        Ok(Value::Arr(items)) => items,
        _ => Vec::new(),
    }
}

fn break_number(value: &Value) -> f64 {
    value.tostring().trim_start_matches('b').parse().unwrap_or(f64::NAN)
}

pub fn breaks(args: &[String]) {
    let usage = "usage: board-card breaks [--json] | breaks add <from> <to> [--name <text>] [--id <bn>] | breaks remove <id | index>";
    let verb = args.first().cloned().unwrap_or_default();
    require_board();
    match verb.as_str() {
        "" | "--json" => {
            if args.len() > 1 {
                die(2, usage);
            }
            if verb == "--json" {
                ctx::out(&breaks_text());
            } else {
                for item in breaks_value() {
                    let name = item.get("name").alt(&Value::str("")).clone();
                    outln(&tsv(&[item.get("id").clone(), item.get("from").clone(), item.get("to").clone(), name]));
                }
            }
        }
        "add" => {
            if args.len() < 3 {
                die(2, usage);
            }
            let from = args[1].clone();
            let to = args[2].clone();
            let (mut name, mut id) = (String::new(), String::new());
            let mut at = 3;
            while at < args.len() {
                match args[at].as_str() {
                    "--project" => die(2, "a break is the whole board's - put a project on hold by giving it no share of the tracks: board-card set <PRJ-n> tracks ''"),
                    "--name" => {
                        if at + 1 >= args.len() {
                            die(2, "--name needs a name");
                        }
                        name = args[at + 1].clone();
                        at += 2;
                    }
                    "--id" => {
                        if at + 1 >= args.len() {
                            die(2, "--id needs a break's id, like b3");
                        }
                        id = lower(&args[at + 1]);
                        at += 2;
                    }
                    _ => die(2, usage),
                }
            }
            if !time::is_day(&from) {
                die(2, &format!("a break's start is a date like 2026-10-12, not '{}'", from));
            }
            if !time::is_day(&to) {
                die(2, &format!("a break's end is a date like 2026-10-12, not '{}'", to));
            }
            if to < from {
                die(2, &format!("a break ends on or after it starts, and {} is before {}", to, from));
            }
            if name.contains('\n') {
                die(2, &format!("a break's name is one line, not '{}'", name));
            }
            if !id.is_empty() && !(id.starts_with('b') && matches_digits(&id[1..], true)) {
                die(2, &format!("a break's id is b and a number, like b3, not '{}'", id));
            }
            with_lock(|| {
                let mut items = breaks_value();
                let id = if !id.is_empty() {
                    if items.iter().any(|b| b.get("id").as_str() == Some(id.as_str())) {
                        die(2, &format!("a break is already called {}", id));
                    }
                    id.clone()
                } else {
                    let highest = items.iter().map(|b| break_number(b.get("id"))).fold(None, |acc: Option<f64>, n| match acc {
                        Some(a) if a >= n || n.is_nan() => Some(a),
                        _ => Some(n),
                    });
                    format!("b{}", crate::json::format_double(highest.unwrap_or(0.0) + 1.0))
                };
                let mut entry = Map::new();
                entry.insert("id", Value::str(&id));
                entry.insert("from", Value::str(&from));
                entry.insert("to", Value::str(&to));
                entry.insert("name", Value::nullable(&name));
                items.push(Value::Obj(entry));
                items.sort_by(|a, b| {
                    jq_cmp(a.get("from"), b.get("from"))
                        .then_with(|| jq_cmp(a.get("to"), b.get("to")))
                        .then_with(|| break_number(a.get("id")).partial_cmp(&break_number(b.get("id"))).unwrap_or(Ordering::Equal))
                });
                write_list(&breaks_file(), items);
                outln(&id);
            });
        }
        "remove" => {
            if args.len() != 2 {
                die(2, usage);
            }
            let given = &args[1];
            let id = if matches_digits(given, true) {
                let index: usize = given.parse().unwrap_or(0);
                let items = breaks_value();
                let found = items.get(index.wrapping_sub(1)).map(|b| b.get("id").clone()).unwrap_or(Value::Null);
                let found = if found.truthy() { found.tostring() } else { String::new() };
                if found.is_empty() {
                    die(3, &format!("no break at {} - the list has {}", given, items.len()));
                }
                found
            } else {
                let id = lower(given);
                if !breaks_value().iter().any(|b| b.get("id").as_str() == Some(id.as_str())) {
                    die(3, &format!("no break is called '{}'", given));
                }
                id
            };
            with_lock(|| {
                let kept: Vec<Value> = breaks_value().into_iter().filter(|b| b.get("id").as_str() != Some(id.as_str())).collect();
                write_list(&breaks_file(), kept);
            });
            outln(&id);
        }
        _ => die(2, usage),
    }
}

pub fn tracks(args: &[String]) {
    require_board();
    if !args.is_empty() {
        if args.len() != 1 {
            die(2, "usage: board-card tracks [<n> | '']");
        }
        let value = args[0].clone();
        if !value.is_empty() && !matches_digits(&value, true) {
            die(2, &format!("the board's tracks are a whole number above 0, not '{}' - clear them with '' to read them as the projects' shares added up", value));
        }
        with_lock(|| {
            let file = format!("{}/tracks", ctx::board_dir());
            if value.is_empty() {
                let _ = fs::remove_file(&file);
                return;
            }
            if !util::write_file(&file, &format!("{}\n", value)) {
                die(1, &format!("could not write {}", file));
            }
            warn_shares_over(&format!("set the board's count to {}", value));
        });
    }
    let tracks = board_tracks();
    if tracks.is_empty() {
        outln(&shares_total().to_string());
    } else {
        outln(&tracks);
    }
}

fn at_seconds(value: &Value) -> i64 {
    match value {
        Value::Str(s) => time::epoch(s).unwrap_or(0),
        _ => 0,
    }
}

pub fn inbox(args: &[String]) {
    let mut as_json = false;
    let mut reading = false;
    let mut stamp = String::new();
    let mut author = String::new();
    let mut limit = "100".to_string();
    let mut at = 0;
    while at < args.len() {
        match args[at].as_str() {
            "--json" => {
                as_json = true;
                at += 1;
            }
            "--read" => {
                reading = true;
                at += 1;
                if at < args.len() && !args[at].starts_with("--") {
                    stamp = args[at].clone();
                    at += 1;
                }
            }
            "--author" => {
                let value = args.get(at + 1).cloned().unwrap_or_default();
                if value.is_empty() {
                    die(2, "--author needs a name");
                }
                author = value;
                at += 2;
            }
            "--limit" => {
                let value = args.get(at + 1).cloned().unwrap_or_default();
                if value.is_empty() {
                    die(2, "--limit needs a number");
                }
                limit = value;
                at += 2;
            }
            other => die(2, &format!("inbox: unknown option '{}'", other)),
        }
    }
    require_board();
    if reading {
        if stamp.is_empty() {
            stamp = now();
        }
        let b = stamp.as_bytes();
        let shaped = b.len() >= 16
            && b[0..4].iter().all(|c| c.is_ascii_digit())
            && b[4] == b'-'
            && b[5..7].iter().all(|c| c.is_ascii_digit())
            && b[7] == b'-'
            && b[8..10].iter().all(|c| c.is_ascii_digit())
            && b[10] == b'T'
            && b[11..13].iter().all(|c| c.is_ascii_digit())
            && b[13] == b':'
            && b[14..16].iter().all(|c| c.is_ascii_digit());
        if !shaped {
            die(2, &format!("not a time: '{}' - write it as 2026-10-14T09:30:00Z", stamp));
        }
        with_lock(|| {
            let _ = util::write_file(&format!("{}/inbox-seen", ctx::board_dir()), &format!("{}\n", stamp));
        });
        outln(&format!("read the inbox up to {}", stamp));
        return;
    }
    if !matches_digits(&limit, false) {
        die(2, "--limit needs a number");
    }
    let limit: usize = limit.parse().unwrap_or(usize::MAX);
    if author.is_empty() {
        author = ctx::default_author();
    }
    let mut records = list_kind("card");
    records.extend(list_kind("epic"));
    let mut comments: Vec<Value> = Vec::new();
    for kind in ["card", "epic"] {
        for file in util::glob(&directory_of_kind(kind), |n| n.ends_with(".comments.jsonl")) {
            let name = file_name(&file);
            let record = name.strip_suffix(".comments.jsonl").unwrap_or(name).to_string();
            for mut comment in board::parse_comments(&file) {
                comment.set("record", Value::str(&record));
                comments.push(comment);
            }
        }
    }
    let seen = util::read_text(&format!("{}/inbox-seen", ctx::board_dir())).map(|t| t.trim_end_matches('\n').to_string()).unwrap_or_default();
    let now = now();
    let mut by: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
    for record in &records {
        by.insert(record.get("id").tostring(), record.clone());
    }
    let mut resolved: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
    for comment in &comments {
        if comment.get("id") == comment.get("thread") {
            let key = format!("{} {}", comment.get("record").tostring(), comment.get("thread").tostring());
            resolved.insert(key, comment.get("resolved").alt(&Value::Bool(false)).clone());
        }
    }
    let since = if seen.is_empty() { at_seconds(&Value::str(&now)) - 7 * 86400 } else { at_seconds(&Value::str(&seen)) };
    let mut items: Vec<Value> = Vec::new();
    for comment in &comments {
        let record_id = comment.get("record").tostring();
        if comment.get("deleted").truthy() || comment.get("author").as_str() == Some(author.as_str()) {
            continue;
        }
        let Some(record) = by.get(&record_id) else { continue };
        let mut item = Map::new();
        item.insert("kind", Value::str("comment"));
        item.insert("id", Value::str(&record_id));
        item.insert("name", record.get("name").clone());
        item.insert("status", record.get("status").clone());
        item.insert("at", comment.get("at").clone());
        item.insert("author", comment.get("author").clone());
        item.insert("text", comment.get("text").clone());
        item.insert("thread", comment.get("thread").clone());
        item.insert("comment", comment.get("id").clone());
        item.insert("anchor", comment.get("anchor").clone());
        let key = format!("{} {}", record_id, comment.get("thread").tostring());
        item.insert("resolved", resolved.get(&key).cloned().filter(|v| v.truthy()).unwrap_or(Value::Bool(false)));
        items.push(Value::Obj(item));
    }
    for record in &records {
        let Value::Str(status) = record.get("status") else { continue };
        if !crate::record::WAITING_COLUMNS.contains(&status.as_str()) {
            continue;
        }
        let at = record.get("dates").get(status).alt(record.get("moved")).alt(record.get("created")).clone();
        let mut item = Map::new();
        item.insert("kind", Value::str("waiting"));
        item.insert("id", record.get("id").clone());
        item.insert("name", record.get("name").clone());
        item.insert("status", record.get("status").clone());
        item.insert("at", at);
        item.insert("by", record.get("moved_by").clone());
        items.push(Value::Obj(item));
    }
    for record in &records {
        let blocked = record.get("blocked").alt(&Value::str("")).clone();
        if blocked == Value::str("") {
            continue;
        }
        let at = record.get("blocked_at").alt(record.get("moved")).alt(record.get("created")).clone();
        let mut item = Map::new();
        item.insert("kind", Value::str("blocked"));
        item.insert("id", record.get("id").clone());
        item.insert("name", record.get("name").clone());
        item.insert("status", record.get("status").clone());
        item.insert("at", at);
        item.insert("text", record.get("blocked").clone());
        item.insert("by", record.get("blocked_by").clone());
        items.push(Value::Obj(item));
    }
    for item in items.iter_mut() {
        let unread = at_seconds(item.get("at")) > since && item.get("by").as_str() != Some(author.as_str());
        item.set("unread", Value::Bool(unread));
    }
    items.sort_by_key(|item| at_seconds(item.get("at")));
    items.reverse();
    let unread = items.iter().filter(|i| i.get("unread").truthy()).count();
    items.truncate(limit);
    let mut inbox = Map::new();
    inbox.insert("me", Value::str(&author));
    inbox.insert("seen", Value::nullable(&seen));
    inbox.insert("now", Value::str(&now));
    inbox.insert("unread", Value::int(unread as i64));
    inbox.insert("items", Value::Arr(items.clone()));
    if as_json {
        outln(&Value::Obj(inbox).pretty());
        return;
    }
    for item in items {
        let mark = if item.get("unread").truthy() { "*" } else { " " };
        let detail = match item.get("kind").as_str() {
            Some("comment") => {
                let text = item.get("text").tostring();
                let first = text.split('\n').next().unwrap_or("").to_string();
                Value::Str(format!("{}: {}", item.get("author").tostring(), first))
            }
            Some("blocked") => item.get("text").clone(),
            _ => Value::Str(format!("waiting in {}", item.get("status").tostring())),
        };
        outln(&tsv(&[Value::str(mark), item.get("at").clone(), item.get("kind").clone(), item.get("id").clone(), detail]));
    }
}

pub fn flush(args: &[String]) {
    match args.first().map(|s| s.as_str()) {
        None | Some("") => {}
        Some("--now") => ctx::set_flush_now(),
        Some(other) => die(2, &format!("flush takes nothing but --now, not '{}'", other)),
    }
    let held = git::held_file();
    let has_held = fs::metadata(&held).map(|m| m.len() > 0).unwrap_or(false);
    if !git::has_repo() || !has_held {
        return;
    }
    with_lock(|| {});
}
