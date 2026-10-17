use crate::board::{self, *};
use crate::cmd_misc;
use crate::cmd_read::{self, list_kind};
use crate::ctx::{self, die, outln};
use crate::git::with_lock;
use crate::json::{jq_cmp, unique_sorted, Map, Value};
use crate::record::*;
use crate::util;
use std::cmp::Ordering;
use std::fs;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};

pub fn value_or_exit(args: &[String], at: usize) -> String {
    match args.get(at + 1) {
        Some(value) => value.clone(),
        None => ctx::exit(1),
    }
}

pub fn read_stdin() -> String {
    let mut bytes = Vec::new();
    let _ = std::io::stdin().read_to_end(&mut bytes);
    let text = String::from_utf8_lossy(&bytes).into_owned();
    text.trim_end_matches('\n').to_string()
}

pub fn create_locked(kind: &str, name: &str, ticket_type: &str, status: &str, epic: &str, body: &str, fields: Map) -> String {
    let id = next_id(kind, epic);
    if kind == "card" {
        warn_epic_done(epic, &format!("added {} to it", id));
    }
    let stamp = now();
    let stamped = has_board(kind) && is_stamped(kind, status);
    let mut fields = fields;
    if kind == "epic" {
        let mut ranked = Map::new();
        ranked.insert("rank", Value::num(last_epic_rank() + 1.0));
        for (k, v) in fields.entries {
            ranked.insert(&k, v);
        }
        fields = ranked;
    }
    let mut record = Map::new();
    if kind == "card" {
        record.insert("id", Value::str(&id));
        record.insert("name", Value::str(name));
        record.insert("type", Value::str(ticket_type));
        record.insert("status", Value::str(status));
        record.insert("epic", Value::nullable(epic));
        for key in ["sprint", "due", "blocked"] {
            record.insert(key, Value::Null);
        }
        record.insert("dependent_on", Value::Arr(Vec::new()));
        record.insert("dependency_for", Value::Arr(Vec::new()));
        for key in ["complexity", "estimate", "session", "claimed_at", "prs", "cost_usd", "tokens_k"] {
            record.insert(key, Value::Null);
        }
        record.insert("created", Value::str(&stamp));
        record.insert("models", Value::obj());
        record.insert("back_from", Value::obj());
        record.insert("timebox_mins", Value::Null);
    } else if kind == "epic" && status != "Backlog" {
        record.insert("id", Value::str(&id));
        record.insert("name", Value::str(name));
        record.insert("status", Value::str(status));
        record.insert("created", Value::str(&stamp));
        record.insert("start", Value::str(&stamp.chars().take(10).collect::<String>()));
    } else {
        record.insert("id", Value::str(&id));
        record.insert("name", Value::str(name));
        record.insert("status", Value::nullable(status));
        record.insert("created", Value::str(&stamp));
    }
    let mut dates = Map::new();
    if stamped {
        dates.insert(status, Value::str(&stamp));
    }
    record.insert("dates", Value::Obj(dates));
    record.insert("body", Value::str(body));
    for (k, v) in fields.entries {
        record.insert(&k, v);
    }
    write_record(&id, Value::Obj(record), false, None);
    if !epic.is_empty() && kind == "card" {
        hold_card(&id);
    }
    id
}

pub fn create(args: &[String]) {
    let mut kind = "card".to_string();
    let mut name = String::new();
    let mut ticket_type = "Feature".to_string();
    let mut status = String::new();
    let mut epic = String::new();
    let mut project = String::new();
    let mut body = String::new();
    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut timebox: Option<String> = None;
    let (mut start, mut end, mut target, mut date) = (String::new(), String::new(), String::new(), String::new());
    let mut key_given = false;
    let mut at = 0;
    while at < args.len() {
        let option = args[at].clone();
        let value = || value_or_exit(args, at);
        match option.as_str() {
            "--kind" => kind = kind_arg(&value()),
            "--name" => name = value(),
            "--type" => ticket_type = value(),
            "--status" => status = value(),
            "--epic" => epic = value(),
            "--project" => project = value(),
            "--icon" => pairs.push(("icon".into(), value())),
            "--timebox-mins" => timebox = Some(value()),
            "--start" => {
                start = value();
                pairs.push(("start".into(), start.clone()));
            }
            "--end" => {
                end = value();
                pairs.push(("end".into(), end.clone()));
            }
            "--target" => {
                target = value();
                pairs.push(("target".into(), target.clone()));
            }
            "--date" => {
                date = value();
                pairs.push(("date".into(), date.clone()));
            }
            "--dev-days" => pairs.push(("dev_days".into(), value())),
            "--speed" => pairs.push(("speed".into(), value())),
            "--priority" => pairs.push(("priority".into(), value())),
            "--repo" => pairs.push(("repo".into(), value())),
            "--key" => {
                pairs.push(("key".into(), value()));
                key_given = true;
            }
            "--body" => {
                if args.get(at + 1).map(|s| s.as_str()) != Some("-") {
                    die(2, "--body reads stdin: pass --body -");
                }
                body = read_stdin();
            }
            other => die(2, &format!("create: unknown option '{}'", other)),
        }
        at += 2;
    }
    prefix_of_kind(&kind);
    if name.is_empty() {
        die(2, "create needs --name");
    }
    if status.is_empty() {
        status = match kind.as_str() {
            "card" | "epic" => "Backlog".to_string(),
            "project" => "Not started".to_string(),
            _ => String::new(),
        };
    }
    if matches!(kind.as_str(), "project" | "sprint" | "reference" | "milestone") {
        field_value(&kind, "status", &status, "");
    }
    if kind == "milestone" && date.is_empty() {
        die(2, "a milestone needs --date");
    }
    if kind == "project" && !key_given {
        die(2, "every project has a key its tickets are numbered by - pass --key <KEY>, 2 to 4 capital letters no other project has");
    }
    if kind == "card" && !matches!(ticket_type.as_str(), "Feature" | "Bug" | "Timebox") {
        die(2, &format!("type is Feature, Bug or Timebox, not '{}'", ticket_type));
    }
    if let Some(minutes) = timebox {
        pairs.push(("timebox_mins".into(), minutes));
    } else if kind == "card" && ticket_type == "Timebox" {
        pairs.push(("timebox_mins".into(), "60".into()));
    }
    require_column(&kind, &status);
    match kind.as_str() {
        "card" if epic.is_empty() => die(2, "every ticket has an epic - pass --epic <EPIC-n>, one of: board-card list --kind epic"),
        "epic" if project.is_empty() => die(2, "every epic has a project - pass --project <PRJ-n>, one of: board-card list --kind project"),
        _ => {}
    }
    let mut fields = Map::new();
    if !epic.is_empty() {
        epic = normalise_id(&epic);
        require_record(&epic);
        if kind_of(&epic) != "epic" {
            die(2, &format!("{} is not an epic", epic));
        }
    }
    if !project.is_empty() {
        if kind == "card" {
            die(2, "a ticket's project is its epic's - pass --epic <EPIC-n> with an epic of that project instead of --project");
        }
        if kind != "epic" {
            die(2, &format!("only an epic belongs to a project, and this is a {}", kind_name(&kind)));
        }
        project = normalise_id(&project);
        require_record(&project);
        if kind_of(&project) != "project" {
            die(2, &format!("{} is not a project", project));
        }
        fields.insert("project", Value::str(&project));
    }
    for (field, value) in &pairs {
        let json = field_value(&kind, field, value, "");
        fields.insert(field, json);
    }
    check_sprint_span(&start, &end);
    if kind == "sprint" {
        check_sprint_overlap(&start, &end, "");
    }
    check_epic_span(&start, &target);
    require_board();
    with_lock(|| {
        let id = create_locked(&kind, &name, &ticket_type, &status, &epic, &body, fields);
        outln(&id);
    });
}

fn held(record: &mut Value, target: &Value) {
    let released = |record: &mut Value| {
        let own = record.get("due_own").clone();
        record.set("due", own);
        record.del("due_from");
        record.del("due_own");
    };
    let day_of = |value: &Value| Value::Str(value.tostring().chars().take(10).collect());
    if !record.get("due_from").is_null() && record.get("due_from") != record.get("epic") {
        released(record);
    }
    let status = record.get("status").clone();
    if record.get("epic").is_null() || status.as_str() == Some("Done") || status.as_str() == Some("Deprioritised") {
        return;
    }
    if target.is_null() {
        if record.get("due_from") == record.get("epic") {
            released(record);
        }
    } else if record.get("due_from") == record.get("epic") {
        let own = record.get("due_own").clone();
        if !own.is_null() && jq_cmp(&day_of(&own), target) != Ordering::Greater {
            released(record);
        } else {
            record.set("due", target.clone());
        }
    } else if record.get("due").is_null() || jq_cmp(&day_of(record.get("due")), target) == Ordering::Greater {
        if !record.get("due").is_null() {
            let due = record.get("due").clone();
            record.set("due_own", due);
        }
        record.set("due", target.clone());
        let epic = record.get("epic").clone();
        record.set("due_from", epic);
    }
}

pub fn hold_card(id: &str) -> Option<String> {
    let before = read_record(id);
    let epic = before.get("epic").alt(&Value::Null).tostring_or_empty();
    let mut target = Value::Null;
    if !epic.is_empty() && exists(&record_file(&epic)) {
        target = read_record(&epic).get("target").clone();
        if !target.truthy() {
            target = Value::Null;
        }
    }
    let mut after = before.clone();
    held(&mut after, &target);
    if after == before {
        return None;
    }
    let due = after.get("due").alt(&Value::str("cleared")).tostring();
    write_record(id, after, false, None);
    Some(format!("{}\tdue {}", id, due))
}

trait OrEmpty {
    fn tostring_or_empty(&self) -> String;
}

impl OrEmpty for Value {
    fn tostring_or_empty(&self) -> String {
        match self {
            Value::Null | Value::Bool(false) => String::new(),
            other => other.tostring(),
        }
    }
}

pub fn ticket_files_naming(id: &str) -> Vec<String> {
    let needle = format!("\"{}\"", id);
    md_files(&directory_of_kind("card")).into_iter().filter(|f| util::read_text(f).map(|t| t.contains(&needle)).unwrap_or(false)).collect()
}

pub fn hold_epic_cards(epic: &str) {
    for file in ticket_files_naming(epic) {
        let card = id_of_file(&file);
        if parse_file(&file).get("epic").tostring_or_empty() != epic {
            continue;
        }
        if let Some(line) = hold_card(&card) {
            outln(&line);
        }
    }
}

pub fn ticket_rows() -> Vec<(String, Value, Value)> {
    let mut rows = Vec::new();
    for file in ticket_files_with_archive() {
        let one = std::slice::from_ref(&file);
        let epic = front_matter_values("epic", one).pop().map(|(_, v)| Value::parse(&v).unwrap_or(Value::Null)).unwrap_or(Value::Null);
        let epic = if epic.truthy() { epic } else { Value::Null };
        let created = front_matter_values("created", one).pop().map(|(_, v)| Value::parse(&v).unwrap_or(Value::str(""))).unwrap_or(Value::str(""));
        let created = if created.truthy() { created } else { Value::str("") };
        rows.push((id_of_file(&file), epic, created));
    }
    rows
}

pub fn tickets_in_order(select: impl Fn(&str, &Value, &Value) -> bool) -> Vec<String> {
    let projects = epic_projects();
    let mut rows: Vec<(String, Value, Value)> = ticket_rows()
        .into_iter()
        .filter_map(|(id, epic, created)| {
            let project = projects.get(epic.as_str().unwrap_or("")).cloned().unwrap_or(Value::Null);
            let project = if project.truthy() { project } else { Value::Null };
            if select(&id, &epic, &project) {
                Some((id, epic, created))
            } else {
                None
            }
        })
        .collect();
    rows.sort_by(|a, b| {
        jq_cmp(&a.2, &b.2).then_with(|| {
            let x: f64 = number(&a.0).parse().unwrap_or(f64::NAN);
            let y: f64 = number(&b.0).parse().unwrap_or(f64::NAN);
            x.partial_cmp(&y).unwrap_or(Ordering::Equal)
        })
    });
    rows.into_iter().map(|(id, _, _)| id).collect()
}

pub fn project_tickets(project: &str, prefix: &str) -> Vec<String> {
    let lead = format!("{}-", prefix);
    tickets_in_order(|id, _, p| p.as_str() == Some(project) && id.starts_with(&lead))
}

pub fn epic_tickets(epic: &str, key: &str) -> Vec<String> {
    let lead = format!("{}-", key);
    tickets_in_order(|id, e, _| e.as_str() == Some(epic) && !id.starts_with(&lead))
}

pub fn renumber_tickets(key: &str, ids: &[String]) {
    if ids.is_empty() {
        return;
    }
    let mut n = next_number("card", key);
    let lock = format!("{}/.lock", ctx::board_dir());
    for id in ids {
        let _ = Command::new("touch").arg(&lock).stdout(Stdio::null()).stderr(Stdio::null()).status();
        let to = format!("{}-{}", key, n);
        rename_card(id, &to);
        outln(&format!("{} -> {}", id, to));
        n += 1;
    }
}

pub fn follow_rename(from: &str, to: &str) {
    let needle = format!("\"{}\"", from);
    let mut files = md_files(&directory_of_kind("card"));
    files.extend(md_files(&directory_of_kind("reference")));
    files.extend(md_files(&archive_directory_of_kind("card")));
    files.extend(md_files(&archive_directory_of_kind("reference")));
    for file in files {
        let Some(text) = util::read_text(&file) else { continue };
        if !text.contains(&needle) {
            continue;
        }
        let other = id_of_file(&file);
        let mut record = parse_file(&file);
        for field in ["dependent_on", "dependency_for"] {
            if record.has(field) {
                if let Value::Arr(items) = record.get(field).clone() {
                    let mapped: Vec<Value> = items.into_iter().map(|v| if v.as_str() == Some(from) { Value::str(to) } else { v }).collect();
                    record.set(field, Value::Arr(mapped));
                }
            }
        }
        if record.get("card").as_str() == Some(from) {
            record.set("card", Value::str(to));
        }
        write_record(&other, record, false, Some(&file));
    }
    let lock_dir = ctx::claim_dir();
    let from_lock = format!("{}/{}", lock_dir, from);
    let to_lock = format!("{}/{}", lock_dir, to);
    if Path::new(&from_lock).is_dir() && !Path::new(&to_lock).exists() {
        let _ = fs::rename(&from_lock, &to_lock);
    }
    for marker in util::glob(&ctx::state_dir(), |name| name.ends_with(".ticket")) {
        if util::read_text(&marker).map(|t| t.trim_end_matches('\n').to_string()).as_deref() == Some(from) {
            let _ = util::write_file(&marker, &format!("{}\n", to));
        }
    }
}

pub fn move_attachments(from: &str, to: &str) {
    if !Path::new(from).is_dir() {
        return;
    }
    let _ = fs::remove_dir(to);
    if let Some(parent) = Path::new(to).parent() {
        let _ = fs::create_dir_all(parent);
    }
    let destination = if Path::new(to).is_dir() {
        format!("{}/{}", to, file_name(from))
    } else {
        to.to_string()
    };
    let _ = fs::rename(from, destination);
}

pub fn rename_card(from: &str, to: &str) {
    let main = directory_of_kind("card");
    let (folder, root) = if exists(&format!("{}/{}.md", main, from)) {
        (main, ctx::board_dir())
    } else {
        (archive_directory_of_kind("card"), format!("{}/archive", ctx::board_dir()))
    };
    let mut record = parse_file(&format!("{}/{}.md", folder, from));
    record.set("id", Value::str(to));
    write_record(to, record, false, Some(&format!("{}/{}.md", folder, to)));
    let _ = fs::remove_file(format!("{}/{}.md", folder, from));
    let comments = format!("{}/{}.comments.jsonl", folder, from);
    if exists(&comments) {
        let _ = fs::rename(&comments, format!("{}/{}.comments.jsonl", folder, to));
    }
    move_attachments(&format!("{}/attachments/{}", root, from), &format!("{}/attachments/{}", root, to));
    follow_rename(from, to);
    let mut froms = vec![from.to_string()];
    if from.starts_with("FEAT-") || from.starts_with("BUG-") || from.starts_with("TIME-") {
        let n = number(from);
        for sibling in [format!("FEAT-{}", n), format!("BUG-{}", n), format!("TIME-{}", n)] {
            if sibling != from && !exists(&record_file(&sibling)) && !exists(&archive_file(&sibling)) {
                froms.push(sibling);
            }
        }
    }
    record_alias(to, &froms);
}

pub fn renamed_to(from: &str, to: &str) {
    follow_rename(from, to);
    record_alias(to, &[from.to_string()]);
}

fn unnest_reference(record: &mut Value) {
    let is_reference = record.get("id").str_or("").starts_with("REF-");
    let Value::Obj(nested) = record.get("reference").clone() else { return };
    if !is_reference {
        return;
    }
    record.del("reference");
    for (key, value) in nested.entries {
        if ["points", "why", "description", "domain", "stack", "card"].contains(&key.as_str()) {
            let value = if key == "points" {
                match &value {
                    Value::Str(s) => Value::from_literal(s.trim()).unwrap_or(value.clone()),
                    _ => value.clone(),
                }
            } else {
                value
            };
            record.set(&key, value);
        } else {
            let mut inner = match record.get("reference").clone() {
                Value::Obj(map) => map,
                _ => Map::new(),
            };
            inner.insert(&key, value);
            record.set("reference", Value::Obj(inner));
        }
    }
}

fn open_epics_of_project(project: &str) -> Vec<String> {
    list_kind("epic")
        .into_iter()
        .filter(|e| e.get("project").as_str() == Some(project) && e.get("status").as_str() != Some("Epic Done"))
        .map(|e| e.get("id").tostring())
        .collect()
}

fn open_cards_of_project(project: &str) -> Vec<String> {
    list_kind("card")
        .into_iter()
        .filter(|c| {
            let status = c.get("status").as_str();
            c.get("project").as_str() == Some(project) && status != Some("Done") && status != Some("Deprioritised")
        })
        .map(|c| c.get("id").tostring())
        .collect()
}

fn warn_open_work(project: &str) {
    if ctx::closing_project() {
        return;
    }
    if read_record(project).get("status").str_or("") == "Done" {
        return;
    }
    let epics = open_epics_of_project(project).len();
    let cards = open_cards_of_project(project).len();
    if epics == 0 && cards == 0 {
        return;
    }
    ctx::warn(&format!(
        "{} still has {} open {} and {} open {} - marked it Done anyway",
        project,
        epics,
        util::plural(epics, "epic", "epics"),
        cards,
        util::plural(cards, "ticket", "tickets")
    ));
}

fn close_project(project: &str) {
    if read_record(project).get("status").str_or("") == "Done" {
        return;
    }
    let epics = open_epics_of_project(project);
    let cards = open_cards_of_project(project);
    for id in cards {
        hop(&id, "Deprioritised");
    }
    for id in epics {
        hop(&id, "Epic Done");
    }
}

fn merge_body(id: &str, edited: &str) -> String {
    let current = read_record(id).get("body").tostring();
    let base = ctx::with(|s| s.body_base.clone()).unwrap_or_default();
    let scratch = util::temp_dir();
    let write = |name: &str, text: &str| util::write_file(&format!("{}/{}", scratch, name), &format!("{}\n", text));
    write("edited", edited);
    write("base", &base);
    write("current", &current);
    let status = Command::new(crate::git::program())
        .args(["merge-file", "--quiet", "-L", "your edit", "-L", "where your edit started", "-L", "on the board now"])
        .arg(format!("{}/edited", scratch))
        .arg(format!("{}/base", scratch))
        .arg(format!("{}/current", scratch))
        .stdin(Stdio::null())
        .status();
    let conflicts = match status {
        Ok(status) => status.code().unwrap_or(255),
        Err(_) => 255,
    };
    if conflicts >= 128 || conflicts < 0 {
        let _ = fs::remove_dir_all(&scratch);
        die(2, &format!("could not merge the edit to {}'s body with what is on the board now", id));
    }
    let merged = util::read_text(&format!("{}/edited", scratch)).unwrap_or_default().trim_end_matches('\n').to_string();
    let _ = fs::remove_dir_all(&scratch);
    if conflicts > 0 {
        outln(&format!(
            "{}\tmerged the body with {} {} - both versions are kept between <<<<<<< and >>>>>>> lines",
            id,
            conflicts,
            util::plural(conflicts as usize, "conflict", "conflicts")
        ));
    } else {
        outln(&format!("{}\tmerged the body", id));
    }
    merged
}

fn update_value(id: &str, field: &str, value: Value) {
    update_record(id, |r| r.set(field, value));
}

pub fn set_locked(id: &str, field: &str, value: &str) {
    let kind = kind_of(id);
    match field {
        "complexity" => {
            if value.is_empty() {
                update_value(id, "complexity", Value::Null);
            } else {
                if !is_fibonacci(value) {
                    die(2, &format!("complexity is a Fibonacci number ({}), not '{}'", FIBONACCI, value));
                }
                let children = read_record(id).get("dependent_on").alt(&Value::Arr(Vec::new())).length();
                if value == "0" && children == 0 {
                    die(2, &format!("complexity 0 is for a split parent, and {} has no children", id));
                }
                if value != "0" && children > 0 {
                    die(2, &format!("{} is a split parent, so its complexity is 0", id));
                }
                update_value(id, "complexity", number_value(value));
            }
        }
        "estimate" => {
            if value.is_empty() {
                if kind != "card" {
                    die(2, &format!("only a ticket has an estimate, and {} is not a ticket", id));
                }
                update_value(id, "estimate", Value::Null);
            } else {
                if kind != "card" {
                    die(2, &format!("only a ticket has an estimate - an epic's is the sum of its tickets', and {} is not a ticket", id));
                }
                if !is_fibonacci(value) || value == "0" {
                    die(2, &format!("an estimate is a Fibonacci number above 0 ({}), not '{}' - clear it with '' instead", FIBONACCI, value));
                }
                if read_record(id).get("type").str_or("") == "Timebox" {
                    die(2, &format!("{} is a timebox, and a timebox carries no estimate", id));
                }
                update_value(id, "estimate", number_value(value));
            }
        }
        "type" => {
            if kind != "card" {
                die(2, &format!("only a ticket has a type, and {} is not a ticket", id));
            }
            if !matches!(value, "Feature" | "Bug" | "Timebox") {
                die(2, &format!("type is Feature, Bug or Timebox, not '{}'", value));
            }
            update_record(id, |r| {
                r.set("type", Value::str(value));
                if value == "Timebox" {
                    r.set("estimate", Value::Null);
                    if r.get("timebox_mins").is_null() {
                        r.set("timebox_mins", Value::int(60));
                    }
                }
            });
        }
        "key" => {
            let key = upper(value);
            let json = field_value("project", "key", &key, id);
            let old = read_record(id).get("key").tostring_or_empty();
            update_value(id, "key", json);
            if !old.is_empty() && old != key {
                let tickets = project_tickets(id, &old);
                renumber_tickets(&key, &tickets);
            }
        }
        "name" => {
            if value.is_empty() {
                die(2, "a record needs a name");
            }
            update_value(id, "name", Value::str(value));
        }
        "icon" | "timebox_mins" | "start" | "end" | "dev_days" | "speed" | "priority" | "repo" | "status" | "points" | "why"
        | "description" | "domain" | "stack" | "card" | "target" | "date" | "confidence" | "learning" | "tracks" | "track" => {
            let json = field_value(kind, field, value, "");
            let own = || read_record(id);
            match (kind, field) {
                ("sprint", "start") => {
                    let end = own().get("end").tostring_or_empty();
                    check_sprint_span(value, &end);
                    check_sprint_overlap(value, &end, id);
                }
                ("sprint", "end") => {
                    let start = own().get("start").tostring_or_empty();
                    check_sprint_span(&start, value);
                    check_sprint_overlap(&start, value, id);
                }
                ("epic", "target") => {
                    let start = own().get("start").tostring_or_empty();
                    check_epic_span(&start, value);
                }
                _ => {}
            }
            let was_status = own().get("status").tostring_or_empty();
            if kind == "project" && field == "status" && value == "Done" {
                warn_open_work(id);
                if ctx::closing_project() {
                    close_project(id);
                }
            }
            update_record(id, |r| {
                unnest_reference(r);
                r.set(field, json);
            });
            if kind == "project" && field == "tracks" && !value.is_empty() && was_status != "Done" {
                warn_shares_over(&format!("gave {} a share of {}", id, value));
            }
            if kind == "project" && field == "status" && was_status == "Done" && value != "Done" {
                warn_shares_over(&format!("reopened {}", id));
            }
            if field == "target" {
                hold_epic_cards(id);
            }
        }
        "epic" | "project" | "sprint" => {
            match (kind, field) {
                ("card", "project") => die(2, &format!("a ticket's project is its epic's - move {} to an epic of another project with: board-card set {} epic <EPIC-n>", id, id)),
                ("card", "epic") if value.is_empty() => die(2, &format!("every ticket has an epic - move {} to another with: board-card set {} epic <EPIC-n>", id, id)),
                ("epic", "project") if value.is_empty() => die(2, &format!("every epic has a project - move {} to another with: board-card set {} project <PRJ-n>", id, id)),
                _ => {}
            }
            let mut reference = String::new();
            if !value.is_empty() {
                reference = normalise_id(value);
                require_record(&reference);
                if kind_of(&reference) != field {
                    die(2, &format!("{} is not a {}", reference, field));
                }
                if field == "epic" && kind == "card" && reference != read_record(id).get("epic").tostring_or_empty() {
                    warn_epic_done(&reference, &format!("moved {} into it", id));
                }
            }
            let mut key = String::new();
            match (kind, field) {
                ("epic", "project") => {
                    let was = read_record(id).get("project").tostring_or_empty();
                    if !reference.is_empty() && reference != was {
                        key = key_of_project(&reference);
                    }
                }
                ("card", "epic") => {
                    let was = project_of_epic(&read_record(id).get("epic").tostring_or_empty());
                    if project_of_epic(&reference) != was {
                        key = ticket_key_for_epic(&reference);
                    }
                }
                _ => {}
            }
            update_value(id, field, Value::nullable(&reference));
            if field == "epic" && kind == "card" {
                if let Some(line) = hold_card(id) {
                    outln(&line);
                }
            }
            if !key.is_empty() {
                match kind {
                    "epic" => {
                        let tickets = epic_tickets(id, &key);
                        renumber_tickets(&key, &tickets);
                    }
                    "card" => {
                        if prefix(id) != key {
                            renumber_tickets(&key, &[id.to_string()]);
                        }
                    }
                    _ => {}
                }
            }
        }
        "due" => {
            let dated = value.len() >= 10 && time_prefix_ok(value);
            if !value.is_empty() && !dated {
                die(2, &format!("due is a date, not '{}'", value));
            }
            update_record(id, |r| {
                r.set("due", Value::nullable(value));
                r.del("due_from");
                r.del("due_own");
            });
        }
        "blocked" => {
            let at = now();
            let by = ctx::default_author();
            let day: String = at.chars().take(10).collect();
            update_record(id, |r| {
                let spans = match r.get("blocked_spans") {
                    Value::Null | Value::Bool(false) => Vec::new(),
                    Value::Arr(items) => items.clone(),
                    _ => Vec::new(),
                };
                let open = !spans.is_empty() && !spans.last().unwrap().has("to");
                if value.is_empty() {
                    if !r.get("blocked").is_null() && open {
                        let mut spans = spans.clone();
                        let last = spans.last_mut().unwrap();
                        last.set("to", Value::str(&day));
                        r.set("blocked_spans", Value::Arr(spans));
                    }
                    r.set("blocked", Value::Null);
                    r.del("blocked_at");
                    r.del("blocked_by");
                } else if r.get("blocked").as_str() == Some(value) {
                } else {
                    if r.get("blocked").is_null() && !open {
                        let mut spans = spans.clone();
                        let mut span = Map::new();
                        span.insert("from", Value::str(&day));
                        spans.push(Value::Obj(span));
                        r.set("blocked_spans", Value::Arr(spans));
                    }
                    r.set("blocked", Value::str(value));
                    r.set("blocked_at", Value::str(&at));
                    r.set("blocked_by", Value::str(&by));
                }
            });
        }
        "urgent" => {
            if kind != "card" {
                die(2, &format!("only a ticket is flagged urgent, and {} is not a ticket", id));
            }
            match value {
                "true" => update_value(id, "urgent", Value::Bool(true)),
                "" => update_record(id, |r| r.del("urgent")),
                other => die(2, &format!("urgent is true, or '' to take the flag off, not '{}'", other)),
            }
        }
        "labels" => {
            if !has_board(kind) {
                die(2, &format!("only a ticket or an epic carries labels, and {} is a {}", id, kind_name(kind)));
            }
            if value.contains('\n') {
                die(2, "labels are separated by commas, never by a new line");
            }
            let mut labels: Vec<String> = Vec::new();
            for label in value.split(',') {
                let label = label.trim();
                if !label.is_empty() && !labels.iter().any(|l| l == label) {
                    labels.push(label.to_string());
                }
            }
            update_record(id, |r| {
                if labels.is_empty() {
                    r.del("labels");
                } else {
                    r.set("labels", crate::json::arr_of_strings(&labels));
                }
            });
        }
        "session" | "prs" => update_value(id, field, Value::nullable(value)),
        "body" => {
            let value = if ctx::with(|s| s.body_base.is_some()) { merge_body(id, value) } else { value.to_string() };
            update_value(id, "body", Value::Str(value));
        }
        "rank" => {
            if !is_decimal(value, true) {
                die(2, &format!("rank is a number, not '{}'", value));
            }
            update_value(id, "rank", number_value(value));
        }
        "plan_rank" => die(2, &format!("an epic's place in the plan is its rank, the same one the Epics board orders it by - run: board-card set {} rank <n>", id)),
        _ if field.starts_with("models.") => {
            let stage = &field[7..];
            if !MODEL_STAGES.contains(&format!(" {} ", stage)) {
                die(2, &format!("a model is recorded for {}, not '{}'", MODEL_STAGES, stage));
            }
            update_record(id, |r| {
                let mut models = match r.get("models") {
                    Value::Obj(map) => map.clone(),
                    _ => Map::new(),
                };
                models.insert(stage, Value::nullable(value));
                models.entries.retain(|(_, v)| !v.is_null());
                r.set("models", Value::Obj(models));
            });
        }
        _ if field.starts_with("reference.") => {
            let sub = &field[10..];
            if ["points", "why", "description", "domain", "stack", "card"].contains(&sub) {
                set_locked(id, sub, value);
            } else {
                die(2, &format!("a reference ticket has points, why, description, domain, stack and card, not '{}'", sub));
            }
        }
        _ if field.starts_with("back_from.") => die(2, "a bounce counter moves through: board-card bounce"),
        _ => die(2, &format!("no settable field '{}' - one of: name, icon, type, epic, project, sprint, due, urgent, labels, blocked, prs, complexity, estimate, timebox_mins, start, end, target, date, confidence, learning, track, dev_days, speed, priority, repo, tracks, status of a project, points, why, description, domain, stack, ticket, session, body, rank, models.<stage>", field)),
    }
}

fn time_prefix_ok(value: &str) -> bool {
    let b = value.as_bytes();
    b.len() >= 10
        && b[0..4].iter().all(|c| c.is_ascii_digit())
        && b[4] == b'-'
        && b[5..7].iter().all(|c| c.is_ascii_digit())
        && b[7] == b'-'
        && b[8..10].iter().all(|c| c.is_ascii_digit())
}

pub fn set(args: &[String]) {
    let ids: Vec<String> = vec![normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""))];
    let at = 0;
    let field = args.get(at + 1).cloned().unwrap_or_default();
    let value = args.get(at + 2).cloned().unwrap_or_default();
    if args.len() < at + 3 {
        die(2, "usage: board-card set <id> <field> <value> [--close] | set <id> body <value> --base <file | ->");
    }
    let mut rest = at + 3;
    while rest < args.len() {
        match args[rest].as_str() {
            "--close" => {
                let all_projects = ids.iter().all(|id| kind_of(id) == "project");
                if !(all_projects && field == "status" && value == "Done") {
                    die(2, "only marking a project Done takes --close: board-card set <PRJ-n> status Done --close");
                }
                ctx::with_mut(|s| s.closing_project = true);
                rest += 1;
            }
            "--base" => {
                if field != "body" {
                    die(2, "only a body write takes --base: board-card set <id> body <value> --base <file | ->");
                }
                if rest + 1 >= args.len() {
                    die(2, "--base names the file holding the body the edit started from, or - for stdin");
                }
                let source = &args[rest + 1];
                let base = if source == "-" {
                    read_stdin()
                } else {
                    if !exists(source) {
                        die(2, &format!("no base file '{}'", source));
                    }
                    util::read_text(source).unwrap_or_default().trim_end_matches('\n').to_string()
                };
                ctx::with_mut(|s| s.body_base = Some(base));
                rest += 2;
            }
            other => die(2, &format!("set: unknown option '{}' - only --close, or --base on a body write", other)),
        }
    }
    let mut unique: Vec<String> = Vec::new();
    for id in ids {
        if !unique.contains(&id) {
            unique.push(id);
        }
    }
    for id in &unique {
        require_record(id);
    }
    with_lock(|| {
        for id in &unique {
            set_locked(id, &field, &value);
        }
    });
    for id in &unique {
        show_after_set(id, &field);
    }
}

fn show_after_set(id: &str, field: &str) {
    let id = if exists(&record_file(id)) { id.to_string() } else { normalise_id(id) };
    let property = property_of_field(field);
    if !property.is_empty() {
        cmd_read::show(&[id, property]);
    }
}

fn hashes_len(text: &str) -> usize {
    text.bytes().take_while(|b| *b == b'#').count()
}

fn title_of(line: &str) -> &str {
    let hashes = hashes_len(line);
    if hashes > 0 && line.as_bytes().get(hashes) == Some(&b' ') {
        &line[hashes + 1..]
    } else {
        line
    }
}

pub fn section_body(body: &str, heading: &str, after: &str, before: &str, under: &str, content: &str) -> String {
    let source = format!("{}\n", body);
    let mut line: Vec<String> = vec![String::new()];
    let mut level: Vec<usize> = vec![0];
    let mut fenced = false;
    for text in util::lines(&source) {
        if text.starts_with("```") {
            fenced = !fenced;
        }
        let heading_level = if !fenced && hashes_len(&text) > 0 && text.as_bytes().get(hashes_len(&text)) == Some(&b' ') {
            text.find(' ').unwrap_or(0)
        } else {
            0
        };
        line.push(text);
        level.push(heading_level);
    }
    let mut total = line.len() - 1;
    let find = |line: &[String], level: &[usize], title: &str, from: usize, to: usize, deeper: usize| -> usize {
        for k in from..=to {
            if k >= line.len() {
                break;
            }
            if level[k] > deeper && title_of(&line[k]) == title {
                return k;
            }
        }
        0
    };
    let section_end = |level: &[usize], start: usize, to: usize| -> usize {
        for k in start + 1..=to {
            if level[k] > 0 && level[k] <= level[start] {
                return k - 1;
            }
        }
        to
    };
    let gap = if content.starts_with('\n') { "" } else { "\n" };
    let mut first = 1;
    let mut last = total;
    let mut floor = 0;
    let mut prefix = "##".to_string();
    if !under.is_empty() {
        let mut parent = find(&line, &level, under, 1, total, 0);
        if parent == 0 {
            if total > 0 && !line[total].is_empty() {
                total += 1;
                line.push(String::new());
                level.push(0);
            }
            total += 1;
            line.push(format!("## {}", under));
            level.push(2);
            parent = total;
        }
        first = parent + 1;
        last = section_end(&level, parent, total);
        floor = level[parent];
        prefix = "#".repeat(level[parent] + 1);
    }
    let mut out: Vec<String> = Vec::new();
    let target = find(&line, &level, heading, first, last, floor);
    if target > 0 {
        let stop = section_end(&level, target, last);
        for k in 1..=target {
            out.push(line[k].clone());
        }
        if !content.is_empty() {
            out.push(format!("{}{}", gap, content));
        }
        if stop < total && line[stop].is_empty() {
            out.push(String::new());
        }
        for k in stop + 1..=total {
            out.push(line[k].clone());
        }
        return out.join("\n");
    }
    let mut insert = last;
    if !before.is_empty() {
        let anchor = find(&line, &level, before, first, last, floor);
        if anchor > 0 {
            for k in 1..anchor {
                out.push(line[k].clone());
            }
            out.push(format!("{} {}", prefix, heading));
            if !content.is_empty() {
                out.push(format!("{}{}", gap, content));
            }
            out.push(String::new());
            for k in anchor..=total {
                out.push(line[k].clone());
            }
            return out.join("\n");
        }
    }
    if !after.is_empty() {
        let anchor = find(&line, &level, after, first, last, floor);
        if anchor > 0 {
            insert = section_end(&level, anchor, last);
        }
    }
    while insert >= first && insert > 0 && line[insert].is_empty() {
        insert -= 1;
    }
    if insert + 1 < first {
        insert = first - 1;
    }
    for k in 1..=insert {
        out.push(line[k].clone());
    }
    if insert > 0 {
        out.push(String::new());
    }
    out.push(format!("{} {}", prefix, heading));
    if !content.is_empty() {
        out.push(format!("{}{}", gap, content));
    }
    if insert < total {
        out.push(String::new());
    }
    for k in insert + 1..=total {
        if !(k == insert + 1 && line[k].is_empty()) {
            out.push(line[k].clone());
        }
    }
    out.join("\n")
}

pub fn section(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let heading = args.get(1).cloned().unwrap_or_default();
    if heading.is_empty() {
        die(2, "usage: board-card section <id> <heading> [--before <heading> | --after <heading>] [--under <heading>] < content");
    }
    let (mut after, mut under, mut before) = (String::new(), String::new(), String::new());
    let mut at = 2;
    while at < args.len() {
        let value = value_or_exit(args, at);
        match args[at].as_str() {
            "--after" => after = value,
            "--before" => before = value,
            "--under" => under = value,
            other => die(2, &format!("section: unknown option '{}'", other)),
        }
        at += 2;
    }
    let heading = cmd_read::strip_heading(&heading);
    let after = cmd_read::strip_heading(&after);
    let under = cmd_read::strip_heading(&under);
    let before = cmd_read::strip_heading(&before);
    require_record(&id);
    let content = read_stdin();
    with_lock(|| {
        let body = read_record(&id).get("body").tostring();
        let updated = section_body(&body, &heading, &after, &before, &under, &content);
        update_value(&id, "body", Value::Str(updated));
    });
    outln(&format!("{}\twrote section {}", id, heading));
}

pub fn bounce(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let gate = args.get(1).cloned().unwrap_or_default();
    if !GATES.contains(&format!(" {} ", gate)) {
        die(2, &format!("a bounce is back from one of:{}- not '{}'", GATES, gate));
    }
    require_record(&id);
    if kind_of(&id) == "card" && read_record(&id).get("status").str_or("") == "Done" {
        ctx::warn(&format!("{} is Done - bounced it anyway", id));
    }
    with_lock(|| {
        update_record(&id, |r| {
            let mut counts = match r.get("back_from") {
                Value::Obj(map) => map.clone(),
                _ => Map::new(),
            };
            let current = counts.get(&gate).cloned().unwrap_or(Value::Null);
            let current = if current.truthy() { current.as_f64().unwrap_or(0.0) } else { 0.0 };
            counts.insert(&gate, Value::num(current + 1.0));
            r.set("back_from", Value::Obj(counts));
        });
    });
    cmd_read::show(&[id, format!("Back from {}", gate)]);
}

pub fn hop(id: &str, column: &str) {
    let kind = kind_of(id);
    let record = read_record(id);
    let from = match record.get("status") {
        Value::Str(s) => s.clone(),
        other => other.compact(),
    };
    if from == column {
        return;
    }
    if kind == "card" && from == "Done" {
        ctx::warn(&format!("{} was Done - moved it anyway", id));
    }
    let stamped = is_stamped(kind, column);
    let starting = kind == "epic" && from == "Backlog";
    let stamp = now();
    let sprint = if kind == "card" && column == "Done" { sprint_covering(&stamp.chars().take(10).collect::<String>()) } else { String::new() };
    let mut updated = record.clone();
    updated.set("status", Value::str(column));
    if !sprint.is_empty() {
        updated.set("sprint", Value::str(&sprint));
    }
    updated.set("moved", Value::str(&stamp));
    updated.set("moved_by", Value::str(&ctx::default_author()));
    if stamped {
        let mut dates = match updated.get("dates") {
            Value::Obj(map) => map.clone(),
            Value::Null | Value::Bool(false) => Map::new(),
            _ => Map::new(),
        };
        if !dates.contains(column) {
            dates.insert(column, Value::str(&stamp));
            updated.set("dates", Value::Obj(dates));
        }
    }
    if starting && updated.get("start").is_null() {
        updated.set("start", Value::str(&stamp.chars().take(10).collect::<String>()));
    }
    if kind == "epic" && column == "Backlog" {
        updated.del("start");
    }
    write_record(id, updated, false, None);
    outln(&format!("{}\t{} -> {}", id, from, column));
    if kind == "card" && column == "In Dev" {
        start_epic_of(&record);
    }
}

fn start_epic_of(record: &Value) {
    if record.get("type").as_str() == Some("Timebox") {
        return;
    }
    let epic = record.get("epic").tostring_or_empty();
    if epic.is_empty() || !exists(&record_file(&epic)) {
        return;
    }
    if read_record(&epic).get("status").tostring() != "Ready for Dev" {
        return;
    }
    hop(&epic, "Tickets In Dev");
}

pub fn move_records(args: &[String]) {
    if args.len() < 2 {
        die(2, "usage: board-card move <id>... <column>");
    }
    let column = args.last().cloned().unwrap();
    if column.is_empty() {
        die(2, "usage: board-card move <id>... <column>");
    }
    let mut ids: Vec<String> = Vec::new();
    let mut kind = "";
    for given in &args[..args.len() - 1] {
        let id = normalise_id(given);
        if ids.contains(&id) {
            continue;
        }
        if !kind.is_empty() && kind_of(&id) != kind {
            die(2, &format!("one move takes records of one kind, and {} is not a {}", id, kind));
        }
        kind = kind_of(&id);
        ids.push(id);
    }
    if !has_board(kind) {
        die(2, &format!("a {} has no columns", kind));
    }
    require_column(kind, &column);
    for id in &ids {
        require_record(id);
    }
    with_lock(|| {
        for id in &ids {
            hop(id, &column);
        }
        cmd_misc::close_maintenance_locked();
    });
}

pub fn walk(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let kind = kind_of(&id);
    if !has_board(kind) {
        die(2, &format!("a {} has no columns", kind));
    }
    let target = args.get(1).cloned().unwrap_or_default();
    if target.is_empty() {
        die(2, "usage: board-card walk <id> <column> [--skip <column>]...");
    }
    let mut skips: Vec<String> = Vec::new();
    let mut at = 2;
    while at < args.len() {
        match args[at].as_str() {
            "--skip" => {
                let skip = args.get(at + 1).cloned().unwrap_or_default();
                require_column(kind, &skip);
                if matches!(skip.as_str(), "In Dev" | "Done" | "Epic Done") {
                    die(2, &format!("{} cannot be skipped", skip));
                }
                if at + 1 >= args.len() {
                    ctx::exit(1);
                }
                skips.push(skip);
                at += 2;
            }
            other => die(2, &format!("walk: unknown option '{}'", other)),
        }
    }
    require_column(kind, &target);
    require_record(&id);
    with_lock(|| {
        let current = match read_record(&id).get("status") {
            Value::Str(s) => s.clone(),
            other => other.compact(),
        };
        if is_parked(kind, &current) || is_parked(kind, &target) {
            let which = if is_parked(kind, &current) { &current } else { &target };
            die(2, &format!("a walk does not pass through {} - use: board-card move", which));
        }
        let Some(from_index) = column_index(kind, &current) else {
            die(2, &format!("{} sits in '{}', which is not a {} column", id, current, kind))
        };
        let target_index = column_index(kind, &target).unwrap();
        if target_index < from_index {
            die(4, &format!("{} sits in {}, so {} is behind it - a walk only goes forward", id, current, target));
        }
        if target_index == from_index {
            outln(&format!("{}\talready in {}", id, current));
            return;
        }
        for i in from_index + 1..=target_index {
            let column = walk_columns(kind)[i];
            if i < target_index && skips.iter().any(|s| s == column) {
                continue;
            }
            hop(&id, column);
        }
        cmd_misc::close_maintenance_locked();
    });
}

fn epic_dependencies() -> Vec<(String, Vec<String>)> {
    md_files(&directory_of_kind("epic"))
        .iter()
        .map(|file| {
            let record = parse_file(file);
            let deps = match record.get("dependent_on") {
                Value::Arr(items) => items.iter().map(|v| v.tostring()).collect(),
                _ => Vec::new(),
            };
            (record.get("id").tostring(), deps)
        })
        .collect()
}

fn refuse_epic_cycle(parent: &str, child: &str) {
    let graph = epic_dependencies();
    let neighbours = |at: &str| -> Vec<String> {
        let mut found: Option<&Vec<String>> = None;
        for (id, deps) in &graph {
            if id == at {
                found = Some(deps);
            }
        }
        found.cloned().unwrap_or_default()
    };
    fn reach(seen: &mut Vec<String>, to: &str, neighbours: &dyn Fn(&str) -> Vec<String>) -> Option<Vec<String>> {
        let at = seen.last().unwrap().clone();
        if at == to {
            return Some(seen.clone());
        }
        for next in neighbours(&at) {
            if seen.contains(&next) {
                continue;
            }
            seen.push(next);
            if let Some(path) = reach(seen, to, neighbours) {
                return Some(path);
            }
            seen.pop();
        }
        None
    }
    let mut seen = vec![child.to_string()];
    if let Some(path) = reach(&mut seen, parent, &neighbours) {
        die(2, &format!("{} already depends on {} ({}), so {} depending on {} would make a cycle", child, parent, path.join(" -> "), parent, child));
    }
}

fn add_link(list: &Value, item: &str) -> Value {
    let mut items = match list {
        Value::Arr(items) => items.clone(),
        Value::Null | Value::Bool(false) => Vec::new(),
        other => vec![other.clone()],
    };
    items.push(Value::str(item));
    Value::Arr(unique_sorted(items))
}

fn remove_link(list: &Value, item: &str) -> Value {
    let items = match list {
        Value::Arr(items) => items.clone(),
        _ => Vec::new(),
    };
    Value::Arr(items.into_iter().filter(|v| v.as_str() != Some(item)).collect())
}

pub fn link_side(id: &str, field: &str, other: &str, add: bool) {
    let kind = kind_of(id);
    update_record(id, |r| {
        if add {
            let list = add_link(r.get(field), other);
            r.set(field, list);
            if field == "dependent_on" && kind == "card" {
                r.set("complexity", Value::int(0));
            }
        } else {
            let list = remove_link(r.get(field), other);
            r.set(field, list);
            if field == "dependent_on" && kind == "card" && r.get("dependent_on").length() == 0 && r.get("complexity") == &Value::int(0) {
                r.set("complexity", Value::Null);
            }
        }
    });
}

pub fn link(action: &str, args: &[String]) {
    let parent = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let child = normalise_id(args.get(1).map(|s| s.as_str()).unwrap_or(""));
    let kind = kind_of(&parent);
    if parent == child {
        die(2, &format!("a {} cannot depend on itself", kind_name(kind)));
    }
    match (kind, kind_of(&child)) {
        ("card", "card") | ("epic", "epic") => {}
        _ => die(2, "only tickets depend on tickets and epics on epics"),
    }
    require_record(&parent);
    require_record(&child);
    with_lock(|| {
        if action == "link" {
            if kind == "epic" {
                refuse_epic_cycle(&parent, &child);
            }
            link_side(&parent, "dependent_on", &child, true);
            link_side(&child, "dependency_for", &parent, true);
        } else {
            link_side(&parent, "dependent_on", &child, false);
            link_side(&child, "dependency_for", &parent, false);
        }
    });
    if kind == "epic" {
        cmd_read::show(&[parent, "Dependent on".into()]);
    } else {
        cmd_read::show(&[parent, "Dependent on".into(), "Complexity".into()]);
    }
}

pub fn claim_lock(verb: &str, id: &str, session: Option<&str>) -> (bool, String) {
    let mut command = Command::new(ctx::claim_lock());
    command.arg(verb).arg(id).stdin(Stdio::null()).stderr(Stdio::inherit());
    if let Some(session) = session {
        command.env("CLAUDE_SESSION_ID", session).env("CLAUDE_CODE_SESSION_ID", session);
    }
    match command.output() {
        Ok(output) => (output.status.success(), String::from_utf8_lossy(&output.stdout).trim_end_matches('\n').to_string()),
        Err(_) => (false, String::new()),
    }
}

fn claim_owner(id: &str) -> String {
    let mut command = Command::new(ctx::claim_lock());
    command.arg("owner").arg(id).stdin(Stdio::null()).stderr(Stdio::null());
    match command.output() {
        Ok(output) => String::from_utf8_lossy(&output.stdout).trim_end_matches('\n').to_string(),
        Err(_) => String::new(),
    }
}

pub fn owner_of(id: &str) -> String {
    claim_owner(id)
}

pub fn claim(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    require_record(&id);
    let me = ctx::session_id();
    if me.is_empty() {
        die(2, "no session id - set CLAUDE_SESSION_ID or CLAUDE_CODE_SESSION_ID");
    }
    if !claim_lock("take", &id, None).0 {
        die(1, &format!("{} is held by session {}", id, claim_owner_loud(&id)));
    }
    with_lock(|| {
        let stamp = now();
        update_record(&id, |r| {
            r.set("session", Value::str(&me));
            r.set("claimed_at", Value::str(&stamp));
        });
    });
    outln(&format!("claimed {}", id));
}

fn claim_owner_loud(id: &str) -> String {
    let mut command = Command::new(ctx::claim_lock());
    command.arg("owner").arg(id).stdin(Stdio::null()).stderr(Stdio::inherit());
    match command.output() {
        Ok(output) => String::from_utf8_lossy(&output.stdout).trim_end_matches('\n').to_string(),
        Err(_) => String::new(),
    }
}

pub fn release(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    require_record(&id);
    if !claim_lock("release", &id, None).0 {
        die(1, &format!("{} is held by session {}, not this one", id, claim_owner_loud(&id)));
    }
    with_lock(|| {
        update_record(&id, |r| {
            r.set("session", Value::Null);
            r.set("claimed_at", Value::Null);
        });
    });
    outln(&format!("released {}", id));
}

pub fn release_session(args: &[String]) {
    let session = args.first().cloned().unwrap_or_default();
    if session.is_empty() {
        die(2, "usage: board-card release-session <session-id>");
    }
    if !has_ticket_folder() {
        return;
    }
    with_lock(|| {
        for kind in ["card", "epic"] {
            for record in list_kind(kind) {
                if record.get("session").as_str() != Some(session.as_str()) {
                    continue;
                }
                let id = record.get("id").tostring();
                update_record(&id, |r| {
                    r.set("session", Value::Null);
                    r.set("claimed_at", Value::Null);
                });
                outln(&format!("released {}", id));
            }
        }
    });
}

fn comment_lines(file: &str) -> Vec<Value> {
    board::parse_comments(file)
}

fn write_comments(file: &str, id: &str, comments: &[Value]) {
    let directory = Path::new(file).parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
    let Some(temporary) = util::temp_file(&directory, &format!(".{}.comments.", id)) else {
        die(1, &format!("could not write {}", file));
    };
    let mut text = String::new();
    for comment in comments {
        text.push_str(&comment.compact());
        text.push('\n');
    }
    if !util::write_file(&temporary, &text) || fs::rename(&temporary, file).is_err() {
        let _ = fs::remove_file(&temporary);
        die(1, &format!("could not write {}", file));
    }
}

fn comment_locked(id: &str, anchor: &str, reply: &str, author: &str, text: &str) {
    let file = comments_file(id);
    let count = util::read_text(&file).map(|t| t.matches('\n').count()).unwrap_or(0);
    let comment_id = format!("c{}", count + 1);
    let mut thread = comment_id.clone();
    let mut anchor = anchor.to_string();
    if !reply.is_empty() {
        thread = String::new();
        if exists(&file) {
            let found: Vec<String> = comment_lines(&file).iter().filter(|c| c.get("id").as_str() == Some(reply)).map(|c| c.get("thread").tostring()).collect();
            thread = found.join("\n");
        }
        if thread.is_empty() || thread == comment_id {
            die(3, &format!("no comment {} on {}", reply, id));
        }
        anchor = String::new();
    }
    let mut line = Map::new();
    line.insert("id", Value::str(&comment_id));
    line.insert("thread", Value::str(&thread));
    line.insert("anchor", Value::nullable(&anchor));
    line.insert("author", Value::str(author));
    line.insert("at", Value::str(&now()));
    line.insert("text", Value::str(text));
    line.insert("resolved", Value::Bool(false));
    let mut handle = match fs::OpenOptions::new().create(true).append(true).open(&file) {
        Ok(handle) => handle,
        Err(_) => die(1, &format!("could not write {}", file)),
    };
    use std::io::Write;
    let _ = handle.write_all(format!("{}\n", Value::Obj(line).compact()).as_bytes());
    touch_record(id);
    outln(&comment_id);
}

fn rewrite_comment_locked(id: &str, comment_id: &str, author: &str, edit: bool, text: &str) {
    let file = comments_file(id);
    let comments = if exists(&file) { comment_lines(&file) } else { Vec::new() };
    if !exists(&file) || !comments.iter().any(|c| c.get("id").as_str() == Some(comment_id) && !c.get("deleted").truthy()) {
        die(3, &format!("no comment {} on {}", comment_id, id));
    }
    if !comments.iter().any(|c| c.get("id").as_str() == Some(comment_id) && c.get("author").as_str() == Some(author)) {
        let authors: Vec<String> = comments.iter().filter(|c| c.get("id").as_str() == Some(comment_id)).map(|c| c.get("author").tostring()).collect();
        die(2, &format!("{} on {} was written by {}, so only they can change it", comment_id, id, authors.join("\n")));
    }
    let stamp = now();
    let rewritten: Vec<Value> = comments
        .into_iter()
        .map(|mut c| {
            if c.get("id").as_str() != Some(comment_id) {
                return c;
            }
            if edit {
                c.set("text", Value::str(text));
                c.set("edited", Value::str(&stamp));
            } else {
                c.set("text", Value::str(""));
                c.set("deleted", Value::Bool(true));
            }
            c
        })
        .collect();
    write_comments(&file, id, &rewritten);
    touch_record(id);
}

pub fn comment(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let (mut anchor, mut reply, mut edit, mut author) = (String::new(), String::new(), String::new(), String::new());
    let mut at = 1;
    while at < args.len() {
        match args[at].as_str() {
            "--anchor" => anchor = args.get(at + 1).cloned().unwrap_or_default(),
            "--reply" => reply = args.get(at + 1).cloned().unwrap_or_default(),
            "--edit" => {
                edit = args.get(at + 1).cloned().unwrap_or_default();
                if edit.is_empty() {
                    die(2, "--edit needs a comment id");
                }
            }
            "--author" => author = args.get(at + 1).cloned().unwrap_or_default(),
            other => die(2, &format!("comment: unknown option '{}'", other)),
        }
        if at + 1 >= args.len() {
            ctx::exit(1);
        }
        at += 2;
    }
    require_record(&id);
    let text = read_stdin();
    if text.is_empty() {
        die(2, "a comment needs text on stdin");
    }
    if !edit.is_empty() {
        if !anchor.is_empty() || !reply.is_empty() {
            die(2, "an edit keeps the comment where it is - drop --anchor and --reply");
        }
        if author.is_empty() {
            author = ctx::default_author();
        }
        with_lock(|| rewrite_comment_locked(&id, &edit, &author, true, &text));
        outln(&format!("edited {} on {}", edit, id));
        return;
    }
    if !anchor.is_empty() {
        let body = read_record(&id).get("body").tostring();
        if !body.contains(&anchor) {
            die(2, &format!("the anchor text is not in {}'s body: '{}'", id, anchor));
        }
    }
    if author.is_empty() {
        author = ctx::default_author();
    }
    with_lock(|| comment_locked(&id, &anchor, &reply, &author, &text));
}

fn resolve_locked(id: &str, comment_id: &str, resolved: bool) {
    let file = comments_file(id);
    let comments = if exists(&file) { comment_lines(&file) } else { Vec::new() };
    let is_thread = |c: &Value| c.get("id").as_str() == Some(comment_id) && c.get("id") == c.get("thread");
    if !exists(&file) || !comments.iter().any(is_thread) {
        die(3, &format!("no thread {} on {}", comment_id, id));
    }
    if comments.iter().any(|c| c.get("id").as_str() == Some(comment_id) && c.get("resolved").alt(&Value::Bool(false)) == &Value::Bool(resolved)) {
        return;
    }
    let rewritten: Vec<Value> = comments
        .into_iter()
        .map(|mut c| {
            if c.get("id").as_str() == Some(comment_id) {
                c.set("resolved", Value::Bool(resolved));
            }
            c
        })
        .collect();
    write_comments(&file, id, &rewritten);
    touch_record(id);
}

pub fn resolve(args: &[String], resolved: bool) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let comment_id = args.get(1).cloned().unwrap_or_default();
    let verb = if resolved { "resolve" } else { "reopen" };
    if comment_id.is_empty() {
        die(2, &format!("usage: board-card {} <id> <comment-id>", verb));
    }
    require_record(&id);
    with_lock(|| resolve_locked(&id, &comment_id, resolved));
    outln(&format!("{} {} on {}", if resolved { "resolved" } else { "reopened" }, comment_id, id));
}

pub fn uncomment(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let comment_id = args.get(1).cloned().unwrap_or_default();
    if comment_id.is_empty() {
        die(2, "usage: board-card uncomment <id> <comment-id> [--author <name>]");
    }
    let mut author = String::new();
    let mut at = 2;
    while at < args.len() {
        match args[at].as_str() {
            "--author" => author = value_or_exit(args, at),
            other => die(2, &format!("uncomment: unknown option '{}'", other)),
        }
        at += 2;
    }
    require_record(&id);
    if author.is_empty() {
        author = ctx::default_author();
    }
    with_lock(|| rewrite_comment_locked(&id, &comment_id, &author, false, ""));
    outln(&format!("deleted {} on {}", comment_id, id));
}

pub fn attach(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let source = args.get(1).cloned().unwrap_or_default();
    if !exists(&source) {
        die(2, &format!("usage: board-card attach <id> <file> - no file at '{}'", source));
    }
    require_record(&id);
    let name = Path::new(source.trim_end_matches('/')).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    with_lock(|| {
        let directory = format!("{}/attachments/{}", ctx::board_dir(), id);
        let target = format!("{}/{}", directory, name);
        if let (Ok(a), Ok(b)) = (fs::read(&source), fs::read(&target)) {
            if a == b {
                return;
            }
        }
        let _ = fs::create_dir_all(&directory);
        if fs::copy(&source, &target).is_err() {
            die(1, &format!("could not copy {} to {}", source, target));
        }
        touch_record(&id);
    });
    outln(&format!("attachments/{}/{}", id, name));
}

pub fn usage(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    require_record(&id);
    let output = Command::new(ctx::done_usage()).arg(&id).stdin(Stdio::inherit()).stderr(Stdio::inherit()).output();
    let output = match output {
        Ok(output) => output,
        Err(_) => ctx::exit(127),
    };
    if !output.status.success() {
        ctx::exit(output.status.code().unwrap_or(1));
    }
    let usage = String::from_utf8_lossy(&output.stdout).trim_end_matches('\n').to_string();
    let Ok(parsed) = Value::parse(&usage) else { ctx::exit(2) };
    with_lock(|| {
        update_record(&id, |r| {
            r.set("cost_usd", parsed.get("cost_usd").clone());
            r.set("tokens_k", parsed.get("tokens_k").clone());
        });
    });
    outln(&usage);
}

fn archive_locked(id: &str, archiving: bool) {
    let kind = kind_of(id);
    let main_folder = format!("{}/{}", ctx::board_dir(), folder_of_kind(kind));
    let archive_folder = format!("{}/archive/{}", ctx::board_dir(), archive_folder_of_kind(kind));
    let board = ctx::board_dir();
    let archive = format!("{}/archive", board);
    let (from_folder, to_folder, from_root, to_root) = if archiving {
        touch_record(id);
        (main_folder, archive_folder, board.clone(), archive.clone())
    } else {
        (archive_folder, main_folder, archive.clone(), board.clone())
    };
    let _ = fs::create_dir_all(&to_folder);
    if fs::rename(format!("{}/{}.md", from_folder, id), format!("{}/{}.md", to_folder, id)).is_err() {
        die(1, &format!("could not move {}", id));
    }
    let comments = format!("{}/{}.comments.jsonl", from_folder, id);
    if exists(&comments) {
        let _ = fs::rename(&comments, format!("{}/{}.comments.jsonl", to_folder, id));
    }
    move_attachments(&format!("{}/attachments/{}", from_root, id), &format!("{}/attachments/{}", to_root, id));
    if !archiving {
        touch_record(id);
    }
    outln(&format!("{} {}", if archiving { "archived" } else { "unarchived" }, id));
}

pub fn naming_records(id: &str) -> Vec<String> {
    let needle = format!("\"{}\"", id);
    let mut files = Vec::new();
    for kind in ["card", "epic", "project", "sprint", "reference"] {
        files.extend(md_files(&directory_of_kind(kind)));
    }
    let mut out = Vec::new();
    for file in files {
        let Some(text) = util::read_text(&file) else { continue };
        if !text.contains(&needle) {
            continue;
        }
        let record = parse_file(&file);
        let mut fields: Vec<&str> = Vec::new();
        for field in ["epic", "project", "sprint", "card"] {
            if record.get(field).as_str() == Some(id) {
                fields.push(field);
            }
        }
        for field in ["dependent_on", "dependency_for"] {
            if let Value::Arr(items) = record.get(field) {
                if items.iter().any(|v| v.as_str() == Some(id)) {
                    fields.push(field);
                }
            }
        }
        if !fields.is_empty() && record.get("id").as_str() != Some(id) {
            out.push(format!("{} ({})", record.get("id").tostring(), fields.join(", ")));
        }
    }
    out
}

pub fn require_unnamed(id: &str) {
    let record = read_record(id);
    let mut links: Vec<String> = Vec::new();
    for field in ["dependent_on", "dependency_for"] {
        if let Value::Arr(items) = record.get(field) {
            links.extend(items.iter().map(|v| v.tostring()));
        }
    }
    if !links.is_empty() {
        die(2, &format!("{} is linked to {} - run board-card unlink first", id, links.join(", ")));
    }
    let named = naming_records(id);
    if !named.is_empty() {
        die(2, &format!("{} is still named by {} - point them elsewhere first", id, named.join(", ")));
    }
}

pub fn archive(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    require_record(&id);
    require_unnamed(&id);
    with_lock(|| archive_locked(&id, true));
}

pub fn unarchive(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    if !exists(&archive_file(&id)) {
        die(3, &format!("no archived record {}", id));
    }
    if Path::new(&record_file(&id)).exists() {
        die(2, &format!("{} is on the board already", id));
    }
    with_lock(|| archive_locked(&id, false));
}

pub fn duplicate(args: &[String]) {
    let id = normalise_id(args.first().map(|s| s.as_str()).unwrap_or(""));
    let (mut name, mut status) = (String::new(), String::new());
    let mut at = 1;
    while at < args.len() {
        match args[at].as_str() {
            "--name" => name = value_or_exit(args, at),
            "--status" => status = value_or_exit(args, at),
            other => die(2, &format!("duplicate: unknown option '{}'", other)),
        }
        at += 2;
    }
    let kind = kind_of(&id);
    if !has_board(kind) {
        die(2, &format!("only a ticket or an epic is duplicated, and {} is a {}", id, kind_name(kind)));
    }
    require_record(&id);
    let field = if kind == "card" { "epic" } else { "project" };
    let home = read_record(&id).get(field).tostring_or_empty();
    if home.is_empty() {
        die(2, &format!("{} has no {}, and a copy needs one - give {} one first with: board-card set {} {} <id>", id, field, id, id, field));
    }
    if !exists(&record_file(&home)) {
        die(2, &format!("{}'s {} {} is not on the board, and a copy needs one - give {} another first with: board-card set {} {} <id>", id, field, home, id, id, field));
    }
    if name.is_empty() {
        name = format!("Copy of {}", read_record(&id).get("name").tostring());
    }
    if status.is_empty() {
        status = walk_columns(kind)[0].to_string();
    }
    require_column(kind, &status);
    with_lock(|| {
        let source = read_record(&id);
        let mut epic = source.get("epic").tostring_or_empty();
        if !epic.is_empty() && !exists(&record_file(&epic)) {
            epic = String::new();
        }
        let mut project = if kind == "epic" { source.get("project").tostring_or_empty() } else { String::new() };
        if !project.is_empty() && !exists(&record_file(&project)) {
            project = String::new();
        }
        let mut fields = Map::new();
        let complexity = if source.get("complexity") == &Value::int(0) { Value::Null } else { source.get("complexity").clone() };
        for (key, value) in [
            ("project", Value::nullable(&project)),
            ("icon", source.get("icon").clone()),
            ("timebox_mins", source.get("timebox_mins").clone()),
            ("estimate", source.get("estimate").clone()),
            ("complexity", complexity),
        ] {
            if !value.is_null() {
                fields.insert(key, value);
            }
        }
        let ticket_type = source.get("type").tostring_or_empty();
        let body = source.get("body").tostring_or_empty();
        let new_id = create_locked(kind, &name, &ticket_type, &status, &epic, &body, fields);
        outln(&new_id);
    });
}
