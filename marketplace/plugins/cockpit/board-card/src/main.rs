mod board;
mod cmd_read;
mod ctx;
mod git;
mod json;
mod record;
mod time;
mod util;

const USAGE: &str = "board-card - the cockpit board, kept as one markdown file per record.

  board-card init
  board-card create [--kind card|epic|project|sprint|reference|milestone] --name <name> [--type Feature|Bug|Timebox]
                    [--status <column>] [--epic <EPIC-n>] [--project <PRJ-n>] [--icon <emoji>] [--timebox-mins <n>] [--body -]
                    [--start <date>] [--end <date>] [--target <date>] [--date <date>] [--dev-days <n>] [--speed <n>] [--priority <n>] [--repo <url>] [--key <KEY>]
  board-card show <id> [--json | --section <heading> | <property>...]
  board-card list [--kind card|epic|project|sprint|reference|milestone] [--status <column>] [--epic <EPIC-n>] [--archived] [--json]
  board-card search <text> [--kind card|epic|project|sprint|reference|milestone]
  board-card statuses [--kind card|epic]
  board-card set <id> <field> <value> [--close] | set <id> body <value> --base <file | ->
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
  board-card undo <id> [--since <commit> [--until <commit>]]
  board-card flush [--now]
  board-card revision
  board-card inbox [--json] [--author <name>] [--limit <n>] | inbox --read [<time>]
  board-card path [<id>]
  board-card tracks [<n> | '']
  board-card views [--json] | views save [--kind card|epic] [--] <name> < <json> | views delete [--kind card|epic] [--] <name>
  board-card breaks [--json] | breaks add <from> <to> [--name <text>] [--id <bn>] | breaks remove <id | index>
  board-card maintenance <PRJ-n> [--date <date>] | maintenance --close
  board-card aliases [--json]
  board-card migrate [--key <PRJ-n>=<KEY>]...";

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
        "show" => cmd_read::show(&rest),
        "list" => cmd_read::list(&rest),
        "search" => cmd_read::search(&rest),
        "statuses" => cmd_read::statuses(&rest),
        "comments" => cmd_read::comments(&rest),
        "attachments" => cmd_read::attachments(&rest),
        "revision" => cmd_read::revision(),
        "path" => cmd_read::path(&rest),
        "aliases" => cmd_read::aliases(&rest),
        _ => {
            ctx::err(USAGE);
            ctx::exit(2);
        }
    }
    ctx::exit(0);
}
