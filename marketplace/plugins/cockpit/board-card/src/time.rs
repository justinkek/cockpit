use std::time::{SystemTime, UNIX_EPOCH};

pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

pub fn unix_now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn format_stamp(seconds: i64) -> String {
    let days = seconds.div_euclid(86400);
    let rest = seconds.rem_euclid(86400);
    let (y, m, d) = civil_from_days(days);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, rest / 3600, (rest % 3600) / 60, rest % 60)
}

pub fn now_stamp() -> String {
    match std::env::var("COCKPIT_NOW") {
        Ok(value) if !value.is_empty() => value,
        _ => format_stamp(unix_now()),
    }
}

fn digits(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit())
}

fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 {
                29
            } else {
                28
            }
        }
        _ => 0,
    }
}

pub fn is_day(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    if !digits(&text[0..4]) || !digits(&text[5..7]) || !digits(&text[8..10]) {
        return false;
    }
    let year: i64 = text[0..4].parse().unwrap();
    let month: i64 = text[5..7].parse().unwrap();
    let day: i64 = text[8..10].parse().unwrap();
    (1..=12).contains(&month) && day >= 1 && day <= days_in_month(year, month)
}

pub fn epoch(text: &str) -> Option<i64> {
    let bytes = text.as_bytes();
    if bytes.len() < 10 || !digits(&text[0..4]) || bytes[4] != b'-' || !digits(&text[5..7]) || bytes[7] != b'-' || !digits(&text[8..10]) {
        return None;
    }
    let year: i64 = text[0..4].parse().ok()?;
    let month: i64 = text[5..7].parse().ok()?;
    let day: i64 = text[8..10].parse().ok()?;
    let mut rest = &text[10..];
    let mut hour = 0;
    let mut minute = 0;
    let mut second = 0;
    let mut offset = 0;
    if !rest.is_empty() {
        if !rest.starts_with('T') {
            return None;
        }
        rest = &rest[1..];
        if rest.len() < 5 || !digits(&rest[0..2]) || rest.as_bytes()[2] != b':' || !digits(&rest[3..5]) {
            return None;
        }
        hour = rest[0..2].parse().ok()?;
        minute = rest[3..5].parse().ok()?;
        rest = &rest[5..];
        if rest.starts_with(':') {
            if rest.len() < 3 || !digits(&rest[1..3]) {
                return None;
            }
            second = rest[1..3].parse().ok()?;
            rest = &rest[3..];
        }
        if let Some(after) = rest.strip_prefix('.') {
            let count = after.bytes().take_while(|b| b.is_ascii_digit()).count();
            if count == 0 {
                return None;
            }
            rest = &after[count..];
        }
        if rest == "Z" {
            rest = "";
        } else if rest.starts_with('+') || rest.starts_with('-') {
            let sign = if rest.starts_with('-') { -60 } else { 60 };
            let zone = &rest[1..];
            let (h, m) = if zone.len() == 4 && digits(zone) {
                (&zone[0..2], &zone[2..4])
            } else if zone.len() == 5 && zone.as_bytes()[2] == b':' && digits(&zone[0..2]) && digits(&zone[3..5]) {
                (&zone[0..2], &zone[3..5])
            } else {
                return None;
            };
            let h: i64 = h.parse().ok()?;
            let m: i64 = m.parse().ok()?;
            offset = sign * (h * 60 + m);
            rest = "";
        }
        if !rest.is_empty() {
            return None;
        }
    }
    if !(1..=12).contains(&month) || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60 {
        return None;
    }
    let days = days_from_civil(year, month, 1) + day - 1;
    Some(days * 86400 + hour * 3600 + minute * 60 + second - offset)
}

pub fn working_minutes(seconds: i64) -> i64 {
    let day = seconds.div_euclid(86400);
    let into_week = day % 7;
    let minute = (seconds - day * 86400) / 60;
    let weekday = (day + 4) % 7;
    let full = (5 * (day / 7) + into_week.min(2) + (into_week - 4).max(0)) * 510;
    let partial = if weekday == 0 || weekday == 6 { 0 } else { (minute - 570).min(510).max(0) };
    full + partial
}

pub fn working_of(text: &str) -> Option<i64> {
    epoch(text).map(working_minutes)
}
