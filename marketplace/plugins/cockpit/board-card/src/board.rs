use crate::ctx::{self, die};
use crate::json::{jq_cmp, Map, Value};
use crate::record::*;
use crate::time;
use crate::util;
use std::cmp::Ordering;
use std::collections::HashMap;

pub fn epic_projects() -> HashMap<String, Value> {
    let mut files = md_files(&directory_of_kind("epic"));
    files.extend(md_files(&archive_directory_of_kind("epic")));
    let mut map = HashMap::new();
    for (file, value) in front_matter_values("project", &files) {
        let parsed = Value::parse(&value).unwrap_or(Value::Null);
        map.insert(id_of_file(&file), parsed);
    }
    map
}

pub fn card_project(record: &mut Value, projects: &HashMap<String, Value>) {
    let id = record.get("id").str_or("").to_string();
    if !is_ticket_id(&id) {
        return;
    }
    let epic = match record.get("epic") {
        Value::Str(s) => s.clone(),
        _ => String::new(),
    };
    let project = projects.get(&epic).cloned().unwrap_or(Value::Null);
    let project = if project.truthy() { project } else { Value::Null };
    record.set("project", project);
}

fn working(value: &Value) -> Option<i64> {
    match value {
        Value::Str(s) => time::working_of(s),
        _ => None,
    }
}

const TIMED: &[&str] = &[
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
];

fn opt_gt(a: Option<i64>, b: Option<i64>) -> bool {
    match (a, b) {
        (Some(x), Some(y)) => x > y,
        (Some(_), None) => true,
        _ => false,
    }
}

pub fn derived(record: &mut Value, now: &str) {
    let id = record.get("id").str_or("").to_string();
    if !is_ticket_id(&id) {
        return;
    }
    let now_minutes = time::working_of(now);
    let dates = record.get("dates").alt(&Value::Null).clone();
    let dates = if dates.is_null() { Value::obj() } else { dates };
    let ready_for_cr = dates.get("Ready for CR").clone();
    let in_dev = working(dates.get("In Dev"));
    let dev_end = if ready_for_cr.is_null() { now_minutes } else { working(&ready_for_cr) };
    let moved = working(record.get("moved"));
    let status = record.get("status").clone();
    let back_in_dev = if status.as_str() == Some("In Dev")
        && !ready_for_cr.is_null()
        && moved.is_some()
        && now_minutes.is_some()
        && opt_gt(moved, working(&ready_for_cr))
    {
        (now_minutes.unwrap() - moved.unwrap()).max(0)
    } else {
        0
    };
    let dev_minutes = match (in_dev, dev_end) {
        (Some(start), Some(end)) => Some((end - start).max(0) + back_in_dev),
        _ => None,
    };
    let since = match status.as_str() {
        Some(column) if TIMED.contains(&column) => {
            let candidates: Vec<i64> = [working(dates.get(column)), moved].into_iter().flatten().collect();
            candidates.into_iter().max()
        }
        _ => None,
    };
    let days = match (since, now_minutes) {
        (Some(since), Some(now)) => ((now - since).max(0) as f64 / 510.0).round(),
        _ => 0.0,
    };
    let overrunning = match dev_minutes {
        None => false,
        Some(minutes) => {
            let minutes = Value::int(minutes);
            let timebox = record.get("timebox_mins").alt(&Value::int(0)).clone();
            let complexity = record.get("complexity").alt(&Value::int(0)).clone();
            if record.get("type").as_str() == Some("Timebox") && jq_cmp(&timebox, &Value::int(0)) == Ordering::Greater {
                jq_cmp(&minutes, &timebox) == Ordering::Greater
            } else if jq_cmp(&complexity, &Value::int(0)) == Ordering::Greater {
                match complexity.as_f64() {
                    Some(points) => jq_cmp(&minutes, &Value::num(points * 102.0)) == Ordering::Greater,
                    None => false,
                }
            } else {
                false
            }
        }
    };
    record.set("days_in_column", Value::num(days));
    record.set("overrunning", Value::Bool(overrunning));
}

pub fn parse_comments(path: &str) -> Vec<Value> {
    match util::read_text(path) {
        Some(text) => Value::parse_many(&text).unwrap_or_default(),
        None => Vec::new(),
    }
}

pub fn group_by_thread(comments: &[Value]) -> Vec<Vec<Value>> {
    let mut sorted: Vec<Value> = comments.to_vec();
    sorted.sort_by(|a, b| jq_cmp(a.get("thread"), b.get("thread")));
    let mut groups: Vec<Vec<Value>> = Vec::new();
    for comment in sorted {
        match groups.last_mut() {
            Some(group) if jq_cmp(group[0].get("thread"), comment.get("thread")) == Ordering::Equal => group.push(comment),
            _ => groups.push(vec![comment]),
        }
    }
    groups
}

pub fn threads(comments: &[Value], all: bool) -> Value {
    let mut out = Vec::new();
    for group in group_by_thread(comments) {
        let root = &group[0];
        if !all && root.get("resolved").truthy() {
            continue;
        }
        let mut kept = Vec::new();
        for comment in &group {
            if comment.get("deleted").truthy() {
                continue;
            }
            let mut entry = Map::new();
            entry.insert("id", comment.get("id").clone());
            entry.insert("author", comment.get("author").clone());
            entry.insert("at", comment.get("at").clone());
            entry.insert("text", comment.get("text").clone());
            if comment.get("edited").truthy() {
                entry.insert("edited", comment.get("edited").clone());
            }
            kept.push(Value::Obj(entry));
        }
        if kept.is_empty() {
            continue;
        }
        let mut thread = Map::new();
        thread.insert("thread", root.get("thread").clone());
        thread.insert("anchor", root.get("anchor").clone());
        thread.insert("resolved", root.get("resolved").alt(&Value::Bool(false)).clone());
        thread.insert("comments", Value::Arr(kept));
        out.push(Value::Obj(thread));
    }
    Value::Arr(out)
}

pub fn open_threads(id: &str) -> Value {
    let file = comments_file(id);
    if !exists(&file) {
        return Value::Arr(Vec::new());
    }
    threads(&parse_comments(&file), false)
}

pub fn open_thread_count(comments: &[Value]) -> usize {
    group_by_thread(comments)
        .iter()
        .filter(|group| !group[0].get("resolved").truthy() && group.iter().any(|c| !c.get("deleted").truthy()))
        .count()
}

pub const PROPERTY_FIELDS: &[(&str, &str)] = &[
    ("Name", "name"),
    ("Icon", "icon"),
    ("Status", "status"),
    ("Type", "type"),
    ("Epic", "epic"),
    ("Project", "project"),
    ("Sprint", "sprint"),
    ("Sprints", "sprint"),
    ("Due", "due"),
    ("Urgent", "urgent"),
    ("Labels", "labels"),
    ("Blocked", "blocked"),
    ("PRs", "prs"),
    ("Agent: Session Id", "session"),
    ("Complexity", "complexity"),
    ("Estimate", "estimate"),
    ("Timebox (mins)", "timebox_mins"),
    ("Dependent on", "dependent_on"),
    ("Dependency for", "dependency_for"),
    ("Session Cost (USD)", "cost_usd"),
    ("Session Tokens (k)", "tokens_k"),
    ("Cost", "cost_usd"),
    ("Tokens", "tokens_k"),
    ("Start Date", "start"),
    ("End Date", "end"),
    ("Dev Days", "dev_days"),
    ("Speed", "speed"),
    ("Priority", "priority"),
    ("Repo", "repo"),
    ("Target", "target"),
    ("Confidence", "confidence"),
    ("Learning", "learning"),
    ("Rank", "rank"),
    ("Date", "date"),
    ("Due from", "due_from"),
    ("Tracks", "tracks"),
    ("Track", "track"),
    ("Points", "points"),
    ("Why this score", "why"),
    ("Description", "description"),
    ("Domain", "domain"),
    ("Stack", "stack"),
    ("Ticket", "card"),
    ("Key", "key"),
];

fn field_of_property(property: &str) -> Option<&'static str> {
    PROPERTY_FIELDS.iter().find(|(p, _)| *p == property).map(|(_, f)| *f)
}

pub fn require_properties(properties: &[String]) {
    for property in properties {
        let known = field_of_property(property).is_some()
            || property.starts_with("Date: ")
            || property.starts_with("Model: ")
            || property.starts_with("Back from ");
        if !known {
            let names: Vec<&str> = PROPERTY_FIELDS.iter().map(|(p, _)| *p).collect();
            die(
                2,
                &format!("no property '{}' - one of: {}, Date: <column>, Model: <stage>, Back from <gate>", property, names.join(", ")),
            );
        }
    }
}

fn text_of(value: &Value, property: &str) -> String {
    match value {
        Value::Arr(items) => {
            let separator = if property == "Labels" { ", " } else { " " };
            items.iter().map(|v| match v {
                Value::Null => String::new(),
                other => other.tostring(),
            }).collect::<Vec<_>>().join(separator)
        }
        Value::Obj(map) => map.entries.iter().map(|(k, v)| format!("{}={}", k, v.tostring())).collect::<Vec<_>>().join(" "),
        other => other.tostring(),
    }
}

pub fn property_value(record: &Value, property: &str) -> String {
    let value = if let Some(column) = property.strip_prefix("Date: ") {
        record.get("dates").get(column).clone()
    } else if let Some(stage) = property.strip_prefix("Model: ") {
        record.get("models").get(stage).clone()
    } else if let Some(gate) = property.strip_prefix("Back from ") {
        record.get("back_from").get(gate).clone()
    } else {
        record.get(field_of_property(property).unwrap_or("")).clone()
    };
    if !value.truthy() {
        return String::new();
    }
    match &value {
        Value::Arr(items) if items.is_empty() => return String::new(),
        Value::Obj(map) if map.is_empty() => return String::new(),
        Value::Str(s) if s.is_empty() => return String::new(),
        _ => {}
    }
    text_of(&value, property)
}

pub fn property_of_field(field: &str) -> String {
    let name = match field {
        "complexity" => "Complexity",
        "estimate" => "Estimate",
        "timebox_mins" => "Timebox (mins)",
        "start" => "Start Date",
        "target" => "Target",
        "confidence" => "Confidence",
        "learning" => "Learning",
        "rank" => "Rank",
        "tracks" => "Tracks",
        "track" => "Track",
        "date" => "Date",
        "end" => "End Date",
        "dev_days" => "Dev Days",
        "speed" => "Speed",
        "status" => "Status",
        "priority" => "Priority",
        "repo" => "Repo",
        "points" => "Points",
        "why" => "Why this score",
        "description" => "Description",
        "domain" => "Domain",
        "stack" => "Stack",
        "card" => "Ticket",
        "key" => "Key",
        "name" => "Name",
        "icon" => "Icon",
        "type" => "Type",
        "epic" => "Epic",
        "project" => "Project",
        "session" => "Agent: Session Id",
        "blocked" => "Blocked",
        "urgent" => "Urgent",
        "labels" => "Labels",
        "prs" => "PRs",
        "due" => "Due",
        "sprint" => "Sprint",
        other => {
            if let Some(rest) = other.strip_prefix("reference.") {
                return property_of_field(rest);
            }
            if let Some(stage) = other.strip_prefix("models.") {
                return format!("Model: {}", stage);
            }
            if let Some(gate) = other.strip_prefix("back_from.") {
                return format!("Back from {}", gate);
            }
            ""
        }
    };
    name.to_string()
}

pub fn is_fibonacci(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit()) && FIBONACCI.contains(&format!(" {} ", value))
}

pub fn number_value(text: &str) -> Value {
    Value::from_literal(text).unwrap_or(Value::Null)
}

pub fn matches_digits(text: &str, positive: bool) -> bool {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    !positive || !text.starts_with('0')
}

pub fn is_decimal(text: &str, signed: bool) -> bool {
    let body = if signed { text.strip_prefix('-').unwrap_or(text) } else { text };
    let (whole, fraction) = match body.split_once('.') {
        Some((w, f)) => (w, Some(f)),
        None => (body, None),
    };
    if whole.is_empty() || !whole.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    match fraction {
        Some(f) => !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit()),
        None => true,
    }
}

pub fn date_value(what: &str, value: &str) -> Value {
    if !value.is_empty() && !time::is_day(value) {
        die(2, &format!("{} is a date like 2026-10-12, not '{}'", what, value));
    }
    Value::nullable(value)
}

const EMOJI_SHOWN: &[(u32, u32)] = &[
    (8986, 8987), (9193, 9196), (9200, 9200), (9203, 9203), (9725, 9726), (9748, 9749), (9800, 9811), (9855, 9855), (9875, 9875),
    (9889, 9889), (9898, 9899), (9917, 9918), (9924, 9925), (9934, 9934), (9940, 9940), (9962, 9962), (9970, 9971), (9973, 9973), (9978, 9978),
    (9981, 9981), (9989, 9989), (9994, 9995), (10024, 10024), (10060, 10060), (10062, 10062), (10067, 10069), (10071, 10071), (10133, 10135),
    (10160, 10160), (10175, 10175), (11035, 11036), (11088, 11088), (11093, 11093),
];

const EMOJI_AS_TEXT: &[(u32, u32)] = &[
    (169, 169), (174, 174), (8252, 8252), (8265, 8265), (8482, 8482), (8505, 8505), (8596, 8601), (8617, 8618), (9000, 9000),
    (9167, 9167), (9197, 9199), (9201, 9202), (9208, 9210), (9410, 9410), (9642, 9643), (9654, 9654), (9664, 9664), (9723, 9724), (9728, 9732),
    (9742, 9742), (9745, 9745), (9752, 9752), (9757, 9757), (9760, 9760), (9762, 9763), (9766, 9766), (9770, 9770), (9774, 9775), (9784, 9786),
    (9792, 9792), (9794, 9794), (9823, 9824), (9827, 9827), (9829, 9830), (9832, 9832), (9851, 9851), (9854, 9854), (9874, 9874), (9876, 9879),
    (9881, 9881), (9883, 9884), (9888, 9888), (9895, 9895), (9904, 9905), (9928, 9928), (9935, 9935), (9937, 9937), (9939, 9939), (9961, 9961),
    (9968, 9969), (9972, 9972), (9975, 9977), (9986, 9986), (9992, 9993), (9996, 9997), (9999, 9999), (10002, 10002), (10004, 10004),
    (10006, 10006), (10013, 10013), (10017, 10017), (10035, 10036), (10052, 10052), (10055, 10055), (10083, 10084), (10145, 10145),
    (10548, 10549), (11013, 11015), (12336, 12336), (12349, 12349), (12951, 12951), (12953, 12953),
];

fn within(point: u32, ranges: &[(u32, u32)]) -> bool {
    ranges.iter().any(|(a, b)| point >= *a && point <= *b)
}

pub fn check_icon(value: &str) {
    let points: Vec<u32> = value.chars().map(|c| c as u32).collect();
    let pictograph = |p: u32| within(p, EMOJI_SHOWN) || ((126976..=129791).contains(&p) && !(127462..=127487).contains(&p) && !(127995..=127999).contains(&p));
    let flag = |p: u32| (127462..=127487).contains(&p);
    let modifier = |p: u32| p == 65038 || p == 65039 || p == 8419 || (127995..=127999).contains(&p) || (917536..=917631).contains(&p);
    let keycap = |p: u32| p == 35 || p == 42 || (48..=57).contains(&p);
    let mut classes = Vec::new();
    for (at, point) in points.iter().enumerate() {
        let p = *point;
        let class = if pictograph(p) {
            "pictograph"
        } else if within(p, EMOJI_AS_TEXT) {
            if points.get(at + 1) == Some(&65039) || (at > 0 && points[at - 1] == 8205) {
                "pictograph"
            } else {
                "text"
            }
        } else if flag(p) {
            "flag"
        } else if p == 8205 {
            "joiner"
        } else if modifier(p) {
            "modifier"
        } else if keycap(p) {
            "keycap"
        } else {
            "text"
        };
        classes.push(class);
    }
    let count = |name: &str| classes.iter().filter(|c| **c == name).count();
    let (pictographs, flags, keys, joins) = (count("pictograph"), count("flag"), count("keycap"), count("joiner"));
    let ok = classes.iter().all(|c| *c != "text")
        && if flags > 0 {
            flags == 2 && pictographs + keys + joins == 0
        } else if keys > 0 {
            keys == 1 && pictographs + joins == 0 && points.contains(&8419)
        } else {
            pictographs == joins + 1
        };
    if !ok {
        die(2, &format!("an icon is one emoji, not '{}'", value));
    }
}

pub fn sprint_records() -> Vec<Value> {
    md_files(&directory_of_kind("sprint")).iter().map(|f| parse_file(f)).collect()
}

fn sprint_number(record: &Value) -> f64 {
    record.get("id").str_or("").split('-').nth(1).and_then(|n| n.parse().ok()).unwrap_or(f64::NAN)
}

fn day_prefix(value: &Value) -> String {
    let text = value.tostring();
    text.chars().take(10).collect()
}

fn dated(record: &Value) -> bool {
    let has = |key: &str| match record.get(key) {
        Value::Null => false,
        Value::Str(s) => !s.is_empty(),
        _ => true,
    };
    has("start") && has("end")
}

fn sort_by_number(records: &mut [Value]) {
    records.sort_by(|a, b| sprint_number(a).partial_cmp(&sprint_number(b)).unwrap_or(Ordering::Equal));
}

pub fn check_sprint_span(start: &str, end: &str) {
    if !start.is_empty() && !end.is_empty() && end < start {
        die(2, &format!("a sprint ends on or after the day it starts, and {} is before {}", end, start));
    }
}

pub fn check_sprint_overlap(start: &str, end: &str, own: &str) {
    if start.is_empty() || end.is_empty() {
        return;
    }
    let mut overlapping: Vec<Value> = sprint_records()
        .into_iter()
        .filter(|s| {
            s.get("id").str_or("") != own && dated(s) && day_prefix(s.get("start")).as_str() <= end && day_prefix(s.get("end")).as_str() >= start
        })
        .collect();
    sort_by_number(&mut overlapping);
    if let Some(other) = overlapping.first() {
        die(
            2,
            &format!(
                "{} already runs {} to {}, and {} to {} overlaps it - a day belongs to one sprint at most",
                other.get("id").tostring(),
                day_prefix(other.get("start")),
                day_prefix(other.get("end")),
                start,
                end
            ),
        );
    }
}

pub fn sprint_covering(day: &str) -> String {
    let mut covering: Vec<Value> = sprint_records()
        .into_iter()
        .filter(|s| dated(s) && day_prefix(s.get("start")).as_str() <= day && day_prefix(s.get("end")).as_str() >= day)
        .collect();
    sort_by_number(&mut covering);
    match covering.first() {
        Some(sprint) => match sprint.get("id") {
            Value::Null | Value::Bool(false) => String::new(),
            other => other.tostring(),
        },
        None => String::new(),
    }
}

pub fn check_epic_span(start: &str, target: &str) {
    if !start.is_empty() && !target.is_empty() && target < start {
        die(2, &format!("an epic's target is on or after its start, and {} is before {}", target, start));
    }
}

pub fn project_files() -> Vec<String> {
    let mut files = md_files(&directory_of_kind("project"));
    files.extend(md_files(&archive_directory_of_kind("project")));
    files
}

pub fn key_holder(key: &str) -> String {
    let wanted = format!("\"{}\"", key);
    for file in project_files() {
        let values = front_matter_values("key", std::slice::from_ref(&file));
        let joined: Vec<String> = values.into_iter().map(|(_, v)| v).collect();
        if joined.join("\n") == wanted {
            return id_of_file(&file);
        }
    }
    String::new()
}

pub fn check_key(key: &str, project: &str) {
    if key.is_empty() {
        die(2, "a project keeps its key, as its tickets are numbered by it");
    }
    if !((2..=4).contains(&key.len()) && key.bytes().all(|b| b.is_ascii_uppercase())) {
        die(2, &format!("a key is 2 to 4 capital letters, like COC, not '{}'", key));
    }
    if RESERVED_KEYS.contains(&format!(" {} ", key)) {
        die(2, &format!("{}- already starts the board's other ids, so it cannot be a project's key", key));
    }
    let holder = key_holder(key);
    if !holder.is_empty() && holder != project {
        die(2, &format!("{} already has the key {}", holder, key));
    }
}

pub fn field_value(kind: &str, field: &str, value: &str, own: &str) -> Value {
    match field {
        "icon" => {
            if !value.is_empty() {
                check_icon(value);
            }
            Value::nullable(value)
        }
        "timebox_mins" => {
            if kind != "card" {
                die(2, &format!("only a ticket has a timebox, and this is a {}", kind_name(kind)));
            }
            if !value.is_empty() && !matches_digits(value, true) {
                die(2, &format!("a timebox is a whole number of minutes, not '{}'", value));
            }
            if value.is_empty() { Value::Null } else { number_value(value) }
        }
        "start" | "end" => {
            if kind == "epic" && field == "start" {
                die(2, "an epic's start is stamped the day it leaves Backlog, cleared when it moves back, and never set by hand");
            }
            if kind != "sprint" {
                die(2, &format!("only a sprint has a {} date, and this is a {}", field, kind_name(kind)));
            }
            date_value(&format!("a {}'s {}", kind, field), value)
        }
        "target" => {
            if kind != "epic" {
                die(2, &format!("only an epic has a target date, and this is a {}", kind_name(kind)));
            }
            date_value("an epic's target", value)
        }
        "date" => {
            if kind != "milestone" {
                die(2, &format!("only a milestone has a date, and this is a {}", kind_name(kind)));
            }
            if value.is_empty() {
                die(2, "a milestone keeps its date - archive it to take it off the plan");
            }
            date_value("a milestone's date", value)
        }
        "confidence" => {
            if kind != "epic" {
                die(2, &format!("only an epic has a confidence, and this is a {}", kind_name(kind)));
            }
            if !value.is_empty() && !["On track", "At risk - plan in place", "At risk - no plan"].contains(&value) {
                die(2, &format!("an epic's confidence is On track, At risk - plan in place or At risk - no plan, not '{}'", value));
            }
            Value::nullable(value)
        }
        "learning" => {
            if kind != "epic" {
                die(2, &format!("only an epic has a learning, and this is a {}", kind_name(kind)));
            }
            Value::nullable(value)
        }
        "dev_days" | "speed" => {
            if kind != "sprint" {
                die(2, &format!("only a sprint has {}, and this is a {}", field, kind_name(kind)));
            }
            if !value.is_empty() && !is_decimal(value, false) {
                die(2, &format!("a sprint's {} is a number, not '{}'", field, value));
            }
            if value.is_empty() { Value::Null } else { number_value(value) }
        }
        "status" => {
            match kind {
                "project" => {}
                "sprint" | "reference" | "milestone" => {
                    if !value.is_empty() {
                        die(2, &format!("a {} has no status - set it to '' to clear one it was given", kind));
                    }
                    return Value::Null;
                }
                _ => die(2, "status changes through: board-card move or board-card walk"),
            }
            if !["Not started", "In progress", "Done"].contains(&value) {
                die(2, &format!("a project's status is Not started, In progress or Done, not '{}'", value));
            }
            Value::nullable(value)
        }
        "priority" => {
            if kind != "project" {
                die(2, &format!("only a project has a priority, and this is a {}", kind_name(kind)));
            }
            if !value.is_empty() && !matches_digits(value, false) {
                die(2, &format!("a project's priority is a whole number, not '{}'", value));
            }
            if value.is_empty() { Value::Null } else { number_value(value) }
        }
        "tracks" => {
            if kind != "project" {
                die(2, &format!("only a project has a share of the tracks - the board's own count is set with: board-card tracks <n> - and this is a {}", kind_name(kind)));
            }
            if !value.is_empty() && !matches_digits(value, true) {
                die(2, &format!("a project's share of the tracks is a whole number above 0, not '{}' - clear it with '' to give it none", value));
            }
            if value.is_empty() { Value::Null } else { number_value(value) }
        }
        "track" => {
            if kind != "epic" {
                die(2, &format!("only an epic is pinned to a track, and this is a {}", kind_name(kind)));
            }
            if !value.is_empty() && !matches_digits(value, true) {
                die(2, &format!("a track is a whole number above 0, not '{}' - clear it with '' to let the plan place the epic", value));
            }
            if value.is_empty() { Value::Null } else { number_value(value) }
        }
        "repo" => {
            if kind != "project" {
                die(2, &format!("only a project has a repo, and this is a {}", kind_name(kind)));
            }
            let url = value.strip_prefix("https://").or_else(|| value.strip_prefix("http://"));
            let ok = matches!(url, Some(rest) if !rest.is_empty() && !rest.chars().any(|c| c.is_whitespace()));
            if !value.is_empty() && !ok {
                die(2, &format!("a project's repo is a URL, not '{}'", value));
            }
            Value::nullable(value)
        }
        "points" => {
            if kind != "reference" {
                die(2, &format!("only a reference ticket has points, and this is a {}", kind_name(kind)));
            }
            if !value.is_empty() && !is_fibonacci(value) {
                die(2, &format!("points are a Fibonacci number ({}), not '{}'", FIBONACCI, value));
            }
            if value.is_empty() { Value::Null } else { number_value(value) }
        }
        "why" | "description" | "stack" => {
            if kind != "reference" {
                die(2, &format!("only a reference ticket has {}, and this is a {}", field, kind_name(kind)));
            }
            Value::nullable(value)
        }
        "domain" => {
            if kind != "reference" {
                die(2, &format!("only a reference ticket has a domain, and this is a {}", kind_name(kind)));
            }
            if !["", "Tech", "Bizdev"].contains(&value) {
                die(2, &format!("a domain is Tech or Bizdev, not '{}'", value));
            }
            Value::nullable(value)
        }
        "card" => {
            if kind != "reference" {
                die(2, &format!("only a reference ticket names the ticket it was taken from, and this is a {}", kind_name(kind)));
            }
            if value.is_empty() {
                return Value::Null;
            }
            let id = normalise_id(value);
            if kind_of(&id) != "card" {
                die(2, &format!("{} is not a ticket", id));
            }
            require_record(&id);
            Value::str(&id)
        }
        "key" => {
            if kind != "project" {
                die(2, &format!("only a project has a key, and this is a {}", kind_name(kind)));
            }
            let key = upper(value);
            check_key(&key, own);
            Value::nullable(&key)
        }
        _ => die(2, &format!("no field '{}' on a {}", field, kind)),
    }
}

pub fn now() -> String {
    time::now_stamp()
}

pub fn shares() -> Vec<(String, i64)> {
    let mut out = Vec::new();
    for file in md_files(&directory_of_kind("project")) {
        let one = std::slice::from_ref(&file);
        let status: Vec<String> = front_matter_values("status", one).into_iter().map(|(_, v)| v).collect();
        if status.join("\n") == "\"Done\"" {
            continue;
        }
        let tracks = front_matter_values("tracks", one)
            .into_iter()
            .map(|(_, v)| v)
            .find(|v| matches_digits(v, false));
        if let Some(value) = tracks {
            out.push((id_of_file(&file), value.parse().unwrap_or(0)));
        }
    }
    out
}

pub fn shares_total() -> i64 {
    shares().iter().map(|(_, v)| v).sum()
}

pub fn board_tracks() -> String {
    match util::read_text(&format!("{}/tracks", ctx::board_dir())) {
        Some(text) => text.trim_end_matches('\n').to_string(),
        None => String::new(),
    }
}

pub fn warn_shares_over(doing: &str) {
    let board = board_tracks();
    if board.is_empty() {
        return;
    }
    let total = shares_total();
    let board_number: f64 = board.trim().parse().unwrap_or(f64::NAN);
    if !((total as f64) <= board_number) {
        ctx::warn(&format!("the projects' shares add up to {}, over the board's {} tracks - {} anyway", total, board, doing));
    }
}

pub fn warn_epic_done(epic: &str, doing: &str) {
    if epic.is_empty() || !exists(&record_file(epic)) {
        return;
    }
    if read_record(epic).get("status").str_or("") != "Epic Done" {
        return;
    }
    ctx::warn(&format!("{} is in Epic Done - {} anyway", epic, doing));
}

pub fn project_of_epic(epic: &str) -> String {
    let mut file = record_file(epic);
    if !exists(&file) {
        file = archive_file(epic);
    }
    if !exists(&file) {
        return String::new();
    }
    match parse_file(&file).get("project") {
        Value::Null | Value::Bool(false) => String::new(),
        other => other.tostring(),
    }
}

pub fn key_of_project(project: &str) -> String {
    if project.is_empty() {
        return String::new();
    }
    let mut file = record_file(project);
    if !exists(&file) {
        file = archive_file(project);
    }
    if !exists(&file) {
        return String::new();
    }
    match parse_file(&file).get("key") {
        Value::Null | Value::Bool(false) => String::new(),
        other => other.tostring(),
    }
}

pub fn ticket_key_for_epic(epic: &str) -> String {
    let project = project_of_epic(epic);
    if project.is_empty() {
        die(2, &format!("{} has no project, so a ticket under it has no key to be numbered by - give it one with: board-card set {} project <PRJ-n>", epic, epic));
    }
    let key = key_of_project(&project);
    if key.is_empty() {
        die(2, &format!("{} has no key, so a ticket under it has nothing to be numbered by - give it one with: board-card set {} key <KEY>, or run: board-card migrate", project, project));
    }
    key
}

pub fn next_number(kind: &str, prefix: &str) -> i64 {
    let mut highest: i64 = 0;
    let lead = format!("{}-", prefix);
    let mut files = md_files(&directory_of_kind(kind));
    files.extend(md_files(&archive_directory_of_kind(kind)));
    for file in files {
        let name = file_name(&file);
        if !name.starts_with(&lead) {
            continue;
        }
        let stem = name.strip_suffix(".md").unwrap_or(name);
        let number = stem.rsplit('-').next().unwrap_or("");
        if number.is_empty() || !number.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let n: i64 = number.parse().unwrap_or(0);
        if n > highest {
            highest = n;
        }
    }
    for line in alias_lines() {
        let from = line.split('\t').next().unwrap_or("");
        if let Some(number) = from.strip_prefix(&lead) {
            if !number.is_empty() && number.bytes().all(|b| b.is_ascii_digit()) {
                let n: i64 = number.parse().unwrap_or(0);
                if n > highest {
                    highest = n;
                }
            }
        }
    }
    highest + 1
}

pub fn next_id(kind: &str, epic: &str) -> String {
    let prefix = if kind == "card" { ticket_key_for_epic(epic) } else { prefix_of_kind(kind).to_string() };
    format!("{}-{}", prefix, next_number(kind, &prefix))
}

pub fn last_epic_rank() -> f64 {
    let files = md_files(&directory_of_kind("epic"));
    let mut best: Option<f64> = None;
    for (_, value) in front_matter_values("rank", &files) {
        let trimmed = value.trim();
        let parsed: Option<f64> = match Value::from_literal(trimmed) {
            Some(v) => v.as_f64(),
            None => None,
        };
        if let Some(n) = parsed {
            best = Some(match best {
                Some(b) if b >= n => b,
                _ => n,
            });
        }
    }
    best.unwrap_or(0.0).floor()
}

pub fn tsv(fields: &[Value]) -> String {
    fields
        .iter()
        .map(|v| match v {
            Value::Null => String::new(),
            Value::Str(s) => s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r"),
            other => other.tostring(),
        })
        .collect::<Vec<_>>()
        .join("\t")
}
