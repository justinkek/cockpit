mod ctx;
mod json;
mod time;
mod util;

fn main() {
    ctx::init("");
    ctx::die(2, "the board is still run by the bash board-card beside this crate");
}
