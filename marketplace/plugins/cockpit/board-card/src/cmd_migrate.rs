use crate::board::*;
use crate::cmd_misc::{self, breaks_value};
use crate::cmd_read::list_kind;
use crate::cmd_write::{renumber_tickets, ticket_rows};
use crate::ctx::{self, die, outln};
use crate::git::{self, with_lock};
use crate::json::{jq_cmp, Map, Value};
use crate::record::*;
use crate::util;
use std::cmp::Ordering;
use std::fs;

fn key_candidates(name: &str) -> Vec<String> {
    let cleaned: String = name.chars().map(|c| c.to_ascii_uppercase()).map(|c| if c.is_ascii_uppercase() { c } else { ' ' }).collect();
    let words: Vec<&str> = cleaned.split_whitespace().collect();
    let initials: String = words.iter().filter_map(|w| w.chars().next()).collect();
    let joined: String = words.concat();
    let mut out = Vec::new();
    if words.len() > 1 && initials.len() >= 2 {
        out.push(initials.chars().take(4).collect());
    }
    if joined.len() >= 3 {
        out.push(joined[..3].to_string());
    }
    if joined.len() >= 4 {
        out.push(joined[..4].to_string());
    }
    if joined.len() >= 2 {
        out.push(joined[..2].to_string());
    }
    out
}

fn migrate_keys(given: &[(String, String)]) {
    let mut files = project_files();
    util::version_sort(&mut files);
    for file in files {
        let project = id_of_file(&file);
        if !matches!(parse_file(&file).get("key"), Value::Null | Value::Bool(false)) {
            continue;
        }
        let mut key = String::new();
        for (p, k) in given {
            if *p == project {
                key = k.clone();
            }
        }
        if key.is_empty() {
            let name = parse_file(&file).get("name").alt(&Value::str("")).tostring();
            for candidate in key_candidates(&name) {
                if RESERVED_KEYS.contains(&format!(" {} ", candidate)) {
                    continue;
                }
                if !key_holder(&candidate).is_empty() {
                    continue;
                }
                if given.iter().any(|(_, k)| *k == candidate) {
                    continue;
                }
                key = candidate;
                break;
            }
            if key.is_empty() {
                die(2, &format!("no key could be made from {}'s name - give it one with: board-card migrate --key {}=<KEY>", project, project));
            }
        }
        check_key(&key, &project);
        let mut record = parse_file(&file);
        record.set("key", Value::str(&key));
        write_record(&project, record, false, Some(&file));
        outln(&format!("{}\tkey {}", project, key));
    }
}

fn migrate_numbers() {
    let projects = epic_projects();
    let mut rows: Vec<(String, String, Value)> = ticket_rows()
        .into_iter()
        .filter(|(id, _, _)| is_legacy_id(id))
        .map(|(id, epic, created)| {
            let project = projects.get(epic.as_str().unwrap_or("")).cloned().unwrap_or(Value::Null);
            let project = if project.truthy() { project.tostring() } else { String::new() };
            (id, project, created)
        })
        .collect();
    rows.sort_by(|a, b| {
        a.1.as_bytes()
            .cmp(b.1.as_bytes())
            .then_with(|| jq_cmp(&a.2, &b.2))
            .then_with(|| number(&a.0).parse::<f64>().unwrap_or(f64::NAN).partial_cmp(&number(&b.0).parse::<f64>().unwrap_or(f64::NAN)).unwrap_or(Ordering::Equal))
    });
    for (id, project, _) in rows {
        if project.is_empty() {
            outln(&format!("{}\tkeeps its id, as it has no project to be numbered by - give it an epic and run migrate again", id));
            continue;
        }
        let key = key_of_project(&project);
        renumber_tickets(&key, &[id]);
    }
}

fn epic_number(record: &Value) -> f64 {
    number(record.get("id").str_or("")).parse().unwrap_or(f64::NAN)
}

fn migrate_ranks() {
    let epics = list_kind("epic");
    if !epics.iter().any(|e| e.has("plan_rank") || e.get("rank").is_null()) {
        return;
    }
    let key_of = |e: &Value| -> Vec<Value> {
        let placed = if e.get("plan_rank").is_null() { 1 } else { 0 };
        let rank = e.get("plan_rank").alt(e.get("rank")).clone();
        let rank = if rank.truthy() { rank } else { Value::num(f64::INFINITY) };
        let target = e.get("target").alt(&Value::str("9999-12-31")).clone();
        vec![Value::int(placed), rank, target, Value::num(epic_number(e))]
    };
    let mut sorted = epics.clone();
    sorted.sort_by(|a, b| jq_cmp(&Value::Arr(key_of(a)), &Value::Arr(key_of(b))));
    for (index, epic) in sorted.iter().enumerate() {
        let wanted = Value::int(index as i64 + 1);
        if epic.get("rank") != &wanted || epic.has("plan_rank") {
            let id = epic.get("id").tostring();
            update_record(&id, |r| {
                r.del("plan_rank");
                r.set("rank", wanted.clone());
            });
            outln(&format!("{}\trank {}", id, index + 1));
        }
    }
}

fn migrate_tracks() {
    let board = ctx::board_dir();
    let old = format!("{}/no-project-tracks", board);
    if exists(&old) {
        let _ = fs::remove_file(&old);
        outln("no-project-tracks\tremoved");
    }
    if exists(&format!("{}/tracks", board)) {
        return;
    }
    let mut projects: Vec<String> = list_kind("epic")
        .into_iter()
        .filter(|e| e.get("status").as_str() != Some("Epic Done") && e.get("project").alt(&Value::str("")).tostring().starts_with("PRJ-"))
        .map(|e| e.get("project").tostring())
        .collect();
    projects.sort();
    projects.dedup();
    for project in projects {
        if !exists(&record_file(&project)) {
            continue;
        }
        let tracks = read_record(&project).get("tracks").clone();
        if tracks.truthy() && tracks != Value::str("") {
            continue;
        }
        update_record(&project, |r| r.set("tracks", Value::int(1)));
        outln(&format!("{}\ttracks 1", project));
    }
    let total = shares_total();
    if total <= 0 {
        return;
    }
    let _ = util::write_file(&format!("{}/tracks", board), &format!("{}\n", total));
    outln(&format!("tracks\t{}", total));
}

fn migrate_starts() {
    for epic in list_kind("epic") {
        if epic.get("status").as_str() == Some("Backlog") {
            continue;
        }
        let start = epic.get("start").alt(&Value::str("")).clone();
        if start != Value::str("") {
            continue;
        }
        let mut stamps: Vec<String> = Vec::new();
        if let Value::Obj(dates) = epic.get("dates") {
            for (column, value) in &dates.entries {
                if column == "Backlog" {
                    continue;
                }
                if let Value::Str(s) = value {
                    if !s.is_empty() {
                        stamps.push(s.clone());
                    }
                }
            }
        }
        stamps.sort();
        let chosen = match stamps.first() {
            Some(first) => Value::str(first),
            None => epic.get("created").clone(),
        };
        if !chosen.truthy() {
            continue;
        }
        let day: String = chosen.tostring().chars().take(10).collect();
        let id = epic.get("id").tostring();
        update_record(&id, |r| r.set("start", Value::str(&day)));
        outln(&format!("{}\tstart {}", id, day));
    }
}

fn migrate_me() {
    let file = format!("{}/me", ctx::board_dir());
    if !exists(&file) {
        return;
    }
    let _ = fs::remove_file(&file);
    outln("me\tremoved");
}

fn migrate_card_projects() {
    let files = md_files(&directory_of_kind("card"));
    let mut lines: Vec<String> = front_matter_values("project", &files).into_iter().map(|(f, v)| format!("{}\t{}", f, v)).collect();
    util::version_sort(&mut lines);
    for line in lines {
        let (file, value) = line.split_once('\t').unwrap_or((&line, ""));
        let card = id_of_file(file);
        update_record(&card, |r| r.del("project"));
        let shown = match Value::parse(value) {
            Ok(Value::Null) | Ok(Value::Bool(false)) => "null".to_string(),
            Ok(other) => other.tostring(),
            Err(_) => String::new(),
        };
        outln(&format!("{}\tproject {} removed", card, shown));
    }
}

fn migrate_sprints() {
    let mut spans: Vec<Value> = list_kind("sprint")
        .into_iter()
        .filter(|s| {
            let set = |key: &str| {
                let v = s.get(key).alt(&Value::str("")).clone();
                v != Value::str("")
            };
            set("start") && set("end")
        })
        .collect();
    spans.sort_by(|a, b| epic_number(a).partial_cmp(&epic_number(b)).unwrap_or(Ordering::Equal));
    let prefix = |v: &Value| v.tostring().chars().take(10).collect::<String>();
    for card in list_kind("card") {
        if card.get("status").as_str() != Some("Done") {
            continue;
        }
        let stamp = card.get("dates").get("Done").alt(card.get("moved")).alt(&Value::str("")).clone();
        let day = prefix(&stamp);
        if day.is_empty() {
            continue;
        }
        let Some(sprint) = spans.iter().find(|s| prefix(s.get("start")) <= day && prefix(s.get("end")) >= day) else { continue };
        let sprint_id = sprint.get("id").clone();
        if !sprint_id.truthy() || &sprint_id == card.get("sprint") {
            continue;
        }
        let was = card.get("sprint").alt(&Value::str("none")).tostring();
        let id = card.get("id").tostring();
        let sprint_text = sprint_id.tostring();
        update_record(&id, |r| r.set("sprint", Value::str(&sprint_text)));
        outln(&format!("{}\tsprint {} -> {}", id, was, sprint_text));
    }
}

fn blocked_history(paths: &[String]) -> Vec<(String, String)> {
    let mut args: Vec<&str> = vec!["log", "--reverse", "--format=@%ad", "--date=format-local:%Y-%m-%d", "--unified=0", "--patch", "--"];
    for path in paths {
        args.push(path);
    }
    let output = git::run_env(&args, &[("TZ", "UTC")]);
    let mut day = String::new();
    let mut out = Vec::new();
    for line in util::lines(&output.stdout) {
        if line.starts_with('@') && line.as_bytes().get(1).map(|b| b.is_ascii_digit()).unwrap_or(false) {
            day = line[1..].to_string();
        } else if let Some(value) = line.strip_prefix("+blocked: ") {
            out.push((day.clone(), value.to_string()));
        }
    }
    out
}

fn migrate_blocked_spans() {
    let mut paths: Vec<String> = Vec::new();
    if git::has_repo() {
        let output = git::run(&["log", "--format=", "--name-only", "-G", "^blocked: \"", "--", "cards", "epics"]);
        paths = util::lines(&output.stdout).into_iter().filter(|p| !p.is_empty()).collect();
        util::version_sort(&mut paths);
        paths.dedup();
    }
    for path in paths {
        if !exists(&format!("{}/{}", ctx::board_dir(), path)) {
            continue;
        }
        let id = id_of_file(&path);
        if read_record(&id).has("blocked_spans") {
            continue;
        }
        let variants = vec![path.clone()];
        let mut spans: Vec<Value> = Vec::new();
        for (day, value) in blocked_history(&variants) {
            let Ok(value) = Value::parse(&value) else { continue };
            let open = !spans.is_empty() && !spans.last().unwrap().has("to");
            if value.is_null() && open {
                spans.last_mut().unwrap().set("to", Value::str(&day));
            } else if !value.is_null() && !open {
                let mut span = Map::new();
                span.insert("from", Value::str(&day));
                spans.push(Value::Obj(span));
            }
        }
        if spans.is_empty() {
            continue;
        }
        let described: Vec<String> = spans
            .iter()
            .map(|s| format!("{} to {}", s.get("from").tostring(), s.get("to").alt(&Value::str("now")).tostring()))
            .collect();
        let list = Value::Arr(spans);
        update_record(&id, |r| r.set("blocked_spans", list.clone()));
        outln(&format!("{}\tblocked spans {}", id, described.join(", ")));
    }
    for kind in ["card", "epic"] {
        for record in list_kind(kind) {
            if !record.get("blocked").is_null() && !record.has("blocked_spans") {
                outln(&format!("{}\tblocked with no history to date it, so it has no blocked span", record.get("id").tostring()));
            }
        }
    }
}

fn migrate_breaks() {
    let file = format!("{}/breaks", ctx::board_dir());
    if !exists(&file) {
        return;
    }
    let items = breaks_value();
    if !items.iter().any(|b| b.has("project")) {
        return;
    }
    for item in &items {
        if !item.get("project").is_null() {
            outln(&format!(
                "{}\tbreak {} to {} for {} removed, as a break is the whole board's",
                item.get("id").tostring(),
                item.get("from").tostring(),
                item.get("to").tostring(),
                item.get("project").tostring()
            ));
        }
    }
    let kept: Vec<Value> = items
        .into_iter()
        .filter(|b| b.get("project").is_null())
        .map(|mut b| {
            b.del("project");
            b
        })
        .collect();
    if kept.is_empty() {
        let _ = fs::remove_file(&file);
    } else {
        let _ = util::write_file(&file, &format!("{}\n", Value::Arr(kept).pretty()));
    }
    outln("breaks\tno break names a project");
}

fn migrate_homes() {
    for card in list_kind("card") {
        if card.get("epic").alt(&Value::str("")) == &Value::str("") {
            outln(&format!("{}\tneeds an epic", card.get("id").tostring()));
        }
    }
    for epic in list_kind("epic") {
        if epic.get("project").alt(&Value::str("")) == &Value::str("") {
            outln(&format!("{}\tneeds a project", epic.get("id").tostring()));
        }
    }
}

pub fn migrate(args: &[String]) {
    let mut given: Vec<(String, String)> = Vec::new();
    let mut at = 0;
    while at < args.len() {
        match args[at].as_str() {
            "--key" => {
                let pair = args.get(at + 1).cloned().unwrap_or_default();
                let shaped = pair.split_once('=').map(|(p, k)| {
                    let (head, tail) = p.split_once('-').unwrap_or(("", ""));
                    !head.is_empty()
                        && head.bytes().all(|b| b.is_ascii_alphabetic())
                        && !tail.is_empty()
                        && tail.bytes().all(|b| b.is_ascii_digit())
                        && !k.is_empty()
                        && k.bytes().all(|b| b.is_ascii_alphabetic())
                });
                if shaped != Some(true) {
                    die(2, &format!("--key takes a project and its key, like PRJ-4=COC, not '{}'", pair));
                }
                let (project, key) = pair.split_once('=').unwrap();
                let project = normalise_id(project);
                let key = upper(key);
                if kind_of(&project) != "project" {
                    die(2, &format!("{} is not a project", project));
                }
                if !exists(&record_file(&project)) && !exists(&archive_file(&project)) {
                    die(3, &format!("no entity {}", project));
                }
                check_key(&key, &project);
                for (p, k) in &given {
                    if *k == key && *p != project {
                        die(2, &format!("{} and {} are both given the key {}", p, project, key));
                    }
                }
                let current = key_of_project(&project);
                if !current.is_empty() && current != key {
                    die(2, &format!("{} already has the key {} - change it with: board-card set {} key {}", project, current, project, key));
                }
                given.push((project, key));
                at += 2;
            }
            _ => die(2, "usage: board-card migrate [--key <PRJ-n>=<KEY>]..."),
        }
    }
    require_board();
    ctx::set_flush_now();
    with_lock(|| {
        ctx::capture_start();
        migrate_keys(&given);
        migrate_numbers();
        migrate_ranks();
        migrate_tracks();
        migrate_starts();
        migrate_me();
        migrate_card_projects();
        migrate_sprints();
        migrate_blocked_spans();
        migrate_breaks();
        cmd_misc::close_maintenance_locked();
        migrate_homes();
        let changes = ctx::capture_end();
        let changes = changes.trim_end_matches('\n');
        if changes.is_empty() {
            outln("nothing to migrate");
        } else {
            outln(changes);
        }
    });
}
