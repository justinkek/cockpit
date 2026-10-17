use std::cmp::Ordering;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn lines(text: &str) -> Vec<String> {
    if text.is_empty() {
        return Vec::new();
    }
    let mut parts: Vec<String> = text.split('\n').map(|s| s.to_string()).collect();
    if text.ends_with('\n') {
        parts.pop();
    }
    parts
}

pub fn glob(directory: &str, keep: impl Fn(&str) -> bool) -> Vec<String> {
    let Ok(entries) = fs::read_dir(directory) else { return Vec::new() };
    let mut names: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') || !keep(&name) {
                return None;
            }
            let path = format!("{}/{}", directory, name);
            if Path::new(&path).is_file() {
                Some(name)
            } else {
                None
            }
        })
        .collect();
    names.sort();
    names.into_iter().map(|name| format!("{}/{}", directory, name)).collect()
}

pub fn read_text(path: &str) -> Option<String> {
    fs::read(path).ok().map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
}

fn random_suffix(attempt: u32) -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.subsec_nanos() as u64).unwrap_or(0);
    let mut seed = nanos ^ ((std::process::id() as u64) << 20) ^ (attempt as u64).wrapping_mul(0x9E3779B97F4A7C15);
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut out = String::new();
    for _ in 0..6 {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        out.push(alphabet[(seed % alphabet.len() as u64) as usize] as char);
    }
    out
}

pub fn temp_file(directory: &str, prefix: &str) -> Option<String> {
    for attempt in 0..100 {
        let path = format!("{}/{}{}", directory, prefix, random_suffix(attempt));
        match fs::OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(_) => return Some(path),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return None,
        }
    }
    None
}

pub fn temp_dir() -> String {
    let base = std::env::var("TMPDIR").ok().filter(|t| !t.is_empty()).unwrap_or_else(|| "/tmp".to_string());
    let base = base.trim_end_matches('/').to_string();
    for attempt in 0..100 {
        let path = format!("{}/board-card.{}", base, random_suffix(attempt));
        if fs::create_dir(&path).is_ok() {
            return path;
        }
    }
    base
}

pub fn write_file(path: &str, text: &str) -> bool {
    match fs::File::create(path) {
        Ok(mut file) => file.write_all(text.as_bytes()).is_ok(),
        Err(_) => false,
    }
}

pub fn older_than_minute(path: &str) -> bool {
    let Ok(meta) = fs::metadata(path) else { return false };
    let Ok(modified) = meta.modified() else { return false };
    match SystemTime::now().duration_since(modified) {
        Ok(age) => age.as_secs() > 60,
        Err(_) => false,
    }
}

fn order(c: u8) -> i32 {
    if c.is_ascii_digit() {
        0
    } else if c.is_ascii_alphabetic() {
        c as i32
    } else if c == b'~' {
        -1
    } else {
        c as i32 + 256
    }
}

fn verrevcmp(a: &[u8], b: &[u8]) -> i32 {
    let (mut i, mut j) = (0, 0);
    let at = |s: &[u8], k: usize| -> u8 { if k < s.len() { s[k] } else { 0 } };
    while i < a.len() || j < b.len() {
        let mut first_diff = 0;
        while (i < a.len() && !a[i].is_ascii_digit()) || (j < b.len() && !b[j].is_ascii_digit()) {
            let ac = if i >= a.len() { 0 } else { order(a[i]) };
            let bc = if j >= b.len() { 0 } else { order(b[j]) };
            if ac != bc {
                return ac - bc;
            }
            i += 1;
            j += 1;
        }
        while at(a, i) == b'0' {
            i += 1;
        }
        while at(b, j) == b'0' {
            j += 1;
        }
        while at(a, i).is_ascii_digit() && at(b, j).is_ascii_digit() {
            if first_diff == 0 {
                first_diff = at(a, i) as i32 - at(b, j) as i32;
            }
            i += 1;
            j += 1;
        }
        if at(a, i).is_ascii_digit() {
            return 1;
        }
        if at(b, j).is_ascii_digit() {
            return -1;
        }
        if first_diff != 0 {
            return first_diff;
        }
    }
    0
}

fn prefix_len(s: &[u8]) -> usize {
    let n = s.len();
    let mut prefix = 0;
    let mut i = 0;
    loop {
        if i == n {
            return prefix;
        }
        i += 1;
        prefix = i;
        while i + 1 < n && s[i] == b'.' && (s[i + 1].is_ascii_alphabetic() || s[i + 1] == b'~') {
            i += 2;
            while i < n && (s[i].is_ascii_alphanumeric() || s[i] == b'~') {
                i += 1;
            }
        }
    }
}

pub fn filevercmp(a: &str, b: &str) -> Ordering {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.is_empty() {
        return if b.is_empty() { Ordering::Equal } else { Ordering::Less };
    }
    if b.is_empty() {
        return Ordering::Greater;
    }
    if a[0] == b'.' {
        if b[0] != b'.' {
            return Ordering::Less;
        }
        let adot = a.len() == 1;
        let bdot = b.len() == 1;
        if adot {
            return if bdot { Ordering::Equal } else { Ordering::Less };
        }
        if bdot {
            return Ordering::Greater;
        }
        let adotdot = a[1] == b'.' && a.len() == 2;
        let bdotdot = b[1] == b'.' && b.len() == 2;
        if adotdot {
            return if bdotdot { Ordering::Equal } else { Ordering::Less };
        }
        if bdotdot {
            return Ordering::Greater;
        }
    } else if b[0] == b'.' {
        return Ordering::Greater;
    }
    let ap = prefix_len(a);
    let bp = prefix_len(b);
    let one_pass = ap == a.len() && bp == b.len();
    let mut result = verrevcmp(&a[..ap], &b[..bp]);
    if result == 0 && !one_pass {
        result = verrevcmp(a, b);
    }
    result.cmp(&0)
}

pub fn version_sort(items: &mut [String]) {
    items.sort_by(|a, b| filevercmp(a, b).then_with(|| a.as_bytes().cmp(b.as_bytes())));
}

pub fn plural(count: usize, one: &str, many: &str) -> String {
    if count == 1 {
        one.to_string()
    } else {
        many.to_string()
    }
}

