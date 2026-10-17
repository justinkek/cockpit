mod board;
mod cmd_history;
mod cmd_migrate;
mod cmd_misc;
mod cmd_read;
mod cmd_write;
mod ctx;
mod git;
mod json;
mod record;
mod time;
mod util;

use ctx::{die, outln};
use std::fs;
use std::path::Path;

const USAGE: &str = "board-card - the cockpit board, kept as one markdown file per entity.

  board-card init
  board-card create [--kind ticket|epic|project|sprint|reference|milestone] --name <name> [--type Feature|Bug|Timebox]
                    [--status <column>] [--epic <EPIC-n>] [--project <PRJ-n>] [--icon <emoji>] [--timebox-mins <n>] [--body -]
                    [--start <date>] [--end <date>] [--target <date>] [--date <date>] [--dev-days <n>] [--speed <n>] [--priority <n>] [--repo <url>] [--key <KEY>]
  board-card show <id> [--json | --section <heading> | <property>...]
  board-card list [--kind ticket|epic|project|sprint|reference|milestone] [--status <column>] [--epic <EPIC-n>] [--archived] [--json]
  board-card search <text> [--kind ticket|epic|project|sprint|reference|milestone]
  board-card statuses [--kind ticket|epic]
  board-card set <id>... <field> <value> [--close] | set <id> body <value> --base <file | ->
  board-card rank <id> <n> [<id> <n>]...
  board-card section <id> <heading> [--before <heading> | --after <heading>] [--under <heading>] < <content>
  board-card bounce <id> <gate>
  board-card move <id>... <column>
  board-card walk <id> <column> [--skip <column>]...
  board-card link <parent-id> <child-id>
  board-card unlink <parent-id> <child-id>
  board-card claim <id>
  board-card release <id>
  board-card release-session <session-id>
  board-card comment <id> [--anchor <text> | --reply <comment-id> | --edit <comment-id>] [--author <name>] < <text>
  board-card uncomment <id> <comment-id> [--author <name>]
  board-card comments <id> [--all] [--json]
  board-card resolve <id> <comment-id>
  board-card reopen <id> <comment-id>
  board-card attach <id> <file>
  board-card attachments <id>
  board-card usage <id>
  board-card archive <id>
  board-card unarchive <id>
  board-card duplicate <id> [--name <name>] [--status <column>]
  board-card history <id> [--json]
  board-card undo <id>... [--since <commit> [--until <commit>]]
  board-card flush [--now]
  board-card revision
  board-card inbox [--json] [--author <name>] [--limit <n>] | inbox --read [<time>]
  board-card path [<id>]
  board-card tracks [<n> | '']
  board-card views [--json] | views save [--kind ticket|epic] [--] <name> < <json> | views delete [--kind ticket|epic] [--] <name>
  board-card breaks [--json] | breaks add <from> <to> [--name <text>] [--id <bn>] | breaks remove <id | index>
  board-card maintenance <PRJ-n> [--date <date>] | maintenance --close
  board-card aliases [--json]
  board-card migrate [--key <PRJ-n>=<KEY>]...";

fn init() {
    let board = ctx::board_dir();
    let mut changed = false;
    for folder in [ctx::ticket_dir().as_str(), "epics", "projects", "sprints", "references", "milestones"] {
        let _ = fs::create_dir_all(format!("{}/{}", board, folder));
    }
    if !Path::new(&format!("{}/.git", board)).is_dir() {
        let _ = git::bare(&["-C", &board, "init", "--quiet"]).status();
        changed = true;
    }
    let ignore = format!("{}/.gitignore", board);
    let has_rule = util::read_text(&ignore).map(|t| util::lines(&t).iter().any(|l| l == "*/.*")).unwrap_or(false);
    if !has_rule {
        let _ = util::write_file(&ignore, ".lock\n*/.*\n");
        changed = true;
    }
    if changed && !git::commit_board("init") {
        die(6, &format!("made {} but could not commit it", board));
    }
    outln(&board);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let action = args.first().cloned().unwrap_or_default();
    let rest: Vec<String> = args.iter().skip(1).cloned().collect();
    ctx::init(&action);
    std::panic::set_hook(Box::new(|info| {
        ctx::release_lock();
        eprintln!("[board-card] internal error: {}", info);
    }));
    if let Ok(delay) = std::env::var("BOARD_CARD_FLUSH_AFTER") {
        std::env::remove_var("BOARD_CARD_FLUSH_AFTER");
        if let Ok(seconds) = delay.parse::<f64>() {
            if seconds > 0.0 && seconds.is_finite() {
                std::thread::sleep(std::time::Duration::from_secs_f64(seconds));
            }
        }
    }
    match action.as_str() {
        "init" => init(),
        "create" => cmd_write::create(&rest),
        "show" => cmd_read::show(&rest),
        "list" => cmd_read::list(&rest),
        "search" => cmd_read::search(&rest),
        "statuses" => cmd_read::statuses(&rest),
        "set" => cmd_write::set(&rest),
        "rank" => cmd_write::rank(&rest),
        "section" => cmd_write::section(&rest),
        "bounce" => cmd_write::bounce(&rest),
        "move" => cmd_write::move_records(&rest),
        "walk" => cmd_write::walk(&rest),
        "link" => cmd_write::link("link", &rest),
        "unlink" => cmd_write::link("unlink", &rest),
        "claim" => cmd_write::claim(&rest),
        "release" => cmd_write::release(&rest),
        "release-session" => cmd_write::release_session(&rest),
        "comment" => cmd_write::comment(&rest),
        "comments" => cmd_read::comments(&rest),
        "resolve" => cmd_write::resolve(&rest, true),
        "reopen" => cmd_write::resolve(&rest, false),
        "uncomment" => cmd_write::uncomment(&rest),
        "attach" => cmd_write::attach(&rest),
        "attachments" => cmd_read::attachments(&rest),
        "usage" => cmd_write::usage(&rest),
        "archive" => cmd_write::archive(&rest),
        "unarchive" => cmd_write::unarchive(&rest),
        "duplicate" => cmd_write::duplicate(&rest),
        "history" => cmd_history::history(&rest),
        "undo" => cmd_history::undo(&rest),
        "flush" => cmd_misc::flush(&rest),
        "revision" => cmd_read::revision(),
        "inbox" => cmd_misc::inbox(&rest),
        "path" => cmd_read::path(&rest),
        "tracks" => cmd_misc::tracks(&rest),
        "migrate" => cmd_migrate::migrate(&rest),
        "aliases" => cmd_read::aliases(&rest),
        "views" => cmd_misc::views(&rest),
        "breaks" => cmd_misc::breaks(&rest),
        "maintenance" => cmd_misc::maintenance(&rest),
        _ => {
            ctx::err(USAGE);
            ctx::exit(2);
        }
    }
    ctx::exit(0);
}
