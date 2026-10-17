use std::cmp::Ordering;
use std::fmt::Write;

#[derive(Clone, Debug)]
pub struct Num {
    pub text: Option<String>,
    pub value: f64,
}

#[derive(Clone, Debug)]
pub enum Value {
    Null,
    Bool(bool),
    Num(Num),
    Str(String),
    Arr(Vec<Value>),
    Obj(Map),
}

#[derive(Clone, Debug, Default)]
pub struct Map {
    pub entries: Vec<(String, Value)>,
}

impl Map {
    pub fn new() -> Map {
        Map { entries: Vec::new() }
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        self.entries.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        self.entries.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    pub fn contains(&self, key: &str) -> bool {
        self.entries.iter().any(|(k, _)| k == key)
    }

    pub fn insert(&mut self, key: &str, value: Value) {
        if let Some(slot) = self.get_mut(key) {
            *slot = value;
        } else {
            self.entries.push((key.to_string(), value));
        }
    }

    pub fn remove(&mut self, key: &str) -> Option<Value> {
        let index = self.entries.iter().position(|(k, _)| k == key)?;
        Some(self.entries.remove(index).1)
    }

    pub fn keys_sorted(&self) -> Vec<String> {
        let mut keys: Vec<String> = self.entries.iter().map(|(k, _)| k.clone()).collect();
        keys.sort();
        keys.dedup();
        keys
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

pub static NULL: Value = Value::Null;

impl Value {
    pub fn num(value: f64) -> Value {
        Value::Num(Num { text: None, value })
    }

    pub fn int(value: i64) -> Value {
        Value::num(value as f64)
    }

    pub fn str(text: &str) -> Value {
        Value::Str(text.to_string())
    }

    pub fn obj() -> Value {
        Value::Obj(Map::new())
    }

    pub fn nullable(text: &str) -> Value {
        if text.is_empty() {
            Value::Null
        } else {
            Value::str(text)
        }
    }

    pub fn from_literal(text: &str) -> Option<Value> {
        let mut parser = Parser { bytes: text.as_bytes(), at: 0 };
        parser.skip_space();
        let value = parser.number().ok()?;
        parser.skip_space();
        if parser.at != parser.bytes.len() {
            return None;
        }
        Some(value)
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    pub fn truthy(&self) -> bool {
        !matches!(self, Value::Null | Value::Bool(false))
    }

    pub fn get(&self, key: &str) -> &Value {
        match self {
            Value::Obj(map) => map.get(key).unwrap_or(&NULL),
            _ => &NULL,
        }
    }

    pub fn has(&self, key: &str) -> bool {
        match self {
            Value::Obj(map) => map.contains(key),
            _ => false,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn str_or<'a>(&'a self, default: &'a str) -> &'a str {
        match self {
            Value::Str(s) => s,
            _ => default,
        }
    }

    pub fn alt<'a>(&'a self, other: &'a Value) -> &'a Value {
        if self.truthy() {
            self
        } else {
            other
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Num(n) => Some(n.value),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&Vec<Value>> {
        match self {
            Value::Arr(items) => Some(items),
            _ => None,
        }
    }

    pub fn as_obj(&self) -> Option<&Map> {
        match self {
            Value::Obj(map) => Some(map),
            _ => None,
        }
    }

    pub fn set(&mut self, key: &str, value: Value) {
        if !matches!(self, Value::Obj(_)) {
            *self = Value::obj();
        }
        if let Value::Obj(map) = self {
            map.insert(key, value);
        }
    }

    pub fn del(&mut self, key: &str) {
        if let Value::Obj(map) = self {
            map.remove(key);
        }
    }

    pub fn length(&self) -> usize {
        match self {
            Value::Arr(items) => items.len(),
            Value::Obj(map) => map.len(),
            Value::Str(s) => s.chars().count(),
            _ => 0,
        }
    }

    pub fn type_rank(&self) -> u8 {
        match self {
            Value::Null => 0,
            Value::Bool(false) => 1,
            Value::Bool(true) => 2,
            Value::Num(_) => 3,
            Value::Str(_) => 4,
            Value::Arr(_) => 5,
            Value::Obj(_) => 6,
        }
    }

    pub fn tostring(&self) -> String {
        match self {
            Value::Str(s) => s.clone(),
            other => other.compact(),
        }
    }

    pub fn compact(&self) -> String {
        let mut out = String::new();
        write_value(&mut out, self, None, 0);
        out
    }

    pub fn pretty(&self) -> String {
        let mut out = String::new();
        write_value(&mut out, self, Some(2), 0);
        out
    }

    pub fn parse(text: &str) -> Result<Value, ()> {
        let mut parser = Parser { bytes: text.as_bytes(), at: 0 };
        parser.skip_space();
        let value = parser.value()?;
        parser.skip_space();
        if parser.at != parser.bytes.len() {
            return Err(());
        }
        Ok(value)
    }

    pub fn parse_many(text: &str) -> Result<Vec<Value>, ()> {
        let mut parser = Parser { bytes: text.as_bytes(), at: 0 };
        let mut values = Vec::new();
        loop {
            parser.skip_space();
            if parser.at >= parser.bytes.len() {
                break;
            }
            values.push(parser.value()?);
        }
        Ok(values)
    }
}

impl PartialEq for Value {
    fn eq(&self, other: &Value) -> bool {
        jq_cmp(self, other) == Ordering::Equal
    }
}

pub fn jq_cmp(a: &Value, b: &Value) -> Ordering {
    let (ra, rb) = (a.type_rank(), b.type_rank());
    if ra != rb {
        return ra.cmp(&rb);
    }
    match (a, b) {
        (Value::Num(x), Value::Num(y)) => x.value.partial_cmp(&y.value).unwrap_or(Ordering::Equal),
        (Value::Str(x), Value::Str(y)) => x.as_bytes().cmp(y.as_bytes()),
        (Value::Arr(x), Value::Arr(y)) => {
            for (i, j) in x.iter().zip(y.iter()) {
                let ordering = jq_cmp(i, j);
                if ordering != Ordering::Equal {
                    return ordering;
                }
            }
            x.len().cmp(&y.len())
        }
        (Value::Obj(x), Value::Obj(y)) => {
            let kx = x.keys_sorted();
            let ky = y.keys_sorted();
            let keys_order = jq_cmp(
                &Value::Arr(kx.iter().map(|k| Value::str(k)).collect()),
                &Value::Arr(ky.iter().map(|k| Value::str(k)).collect()),
            );
            if keys_order != Ordering::Equal {
                return keys_order;
            }
            for key in kx {
                let ordering = jq_cmp(x.get(&key).unwrap(), y.get(&key).unwrap());
                if ordering != Ordering::Equal {
                    return ordering;
                }
            }
            Ordering::Equal
        }
        _ => Ordering::Equal,
    }
}

pub fn format_double(value: f64) -> String {
    if value.is_nan() {
        return "null".to_string();
    }
    if value.is_infinite() {
        return if value > 0.0 { "1.7976931348623157e+308".to_string() } else { "-1.7976931348623157e+308".to_string() };
    }
    if value == 0.0 {
        return if value.is_sign_negative() { "-0".to_string() } else { "0".to_string() };
    }
    let scientific = format!("{:e}", value.abs());
    let (mantissa, exponent) = scientific.split_once('e').unwrap();
    let exponent: i32 = exponent.parse().unwrap();
    let digits: String = mantissa.chars().filter(|c| c.is_ascii_digit()).collect();
    let digits = digits.trim_end_matches('0');
    let digits = if digits.is_empty() { "0" } else { digits };
    let count = digits.len() as i32;
    let decpt = exponent + 1;
    let mut out = String::new();
    if value < 0.0 {
        out.push('-');
    }
    if decpt <= -4 || decpt > count + 15 {
        out.push_str(&digits[..1]);
        if count > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        let shown = decpt - 1;
        if shown < 0 {
            out.push('-');
        } else {
            out.push('+');
        }
        let _ = write!(out, "{:02}", shown.abs());
    } else if decpt <= 0 {
        out.push_str("0.");
        for _ in 0..(-decpt) {
            out.push('0');
        }
        out.push_str(digits);
    } else if decpt >= count {
        out.push_str(digits);
        for _ in 0..(decpt - count) {
            out.push('0');
        }
    } else {
        out.push_str(&digits[..decpt as usize]);
        out.push('.');
        out.push_str(&digits[decpt as usize..]);
    }
    out
}

fn canonical_literal(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut at = 0;
    let negative = bytes.first() == Some(&b'-');
    if negative {
        at += 1;
    }
    let mut integer = String::new();
    while at < bytes.len() && bytes[at].is_ascii_digit() {
        integer.push(bytes[at] as char);
        at += 1;
    }
    let mut fraction = String::new();
    if at < bytes.len() && bytes[at] == b'.' {
        at += 1;
        while at < bytes.len() && bytes[at].is_ascii_digit() {
            fraction.push(bytes[at] as char);
            at += 1;
        }
    }
    let mut exponent: i64 = 0;
    let has_exponent = at < bytes.len() && (bytes[at] == b'e' || bytes[at] == b'E');
    if has_exponent {
        exponent = text[at + 1..].parse().unwrap_or(0);
    }
    let mut coefficient = format!("{}{}", integer, fraction);
    let mut exp = exponent - fraction.len() as i64;
    let trimmed = coefficient.trim_start_matches('0');
    coefficient = if trimmed.is_empty() { "0".to_string() } else { trimmed.to_string() };
    if !has_exponent && coefficient == "0" {
        exp = -(fraction.len() as i64);
    }
    let digits = coefficient.len() as i64;
    let adjusted = exp + digits - 1;
    let mut out = String::new();
    if negative {
        out.push('-');
    }
    if exp <= 0 && adjusted >= -6 {
        if exp == 0 {
            out.push_str(&coefficient);
        } else {
            let point = digits + exp;
            if point > 0 {
                out.push_str(&coefficient[..point as usize]);
                out.push('.');
                out.push_str(&coefficient[point as usize..]);
            } else {
                out.push_str("0.");
                for _ in 0..(-point) {
                    out.push('0');
                }
                out.push_str(&coefficient);
            }
        }
    } else {
        out.push_str(&coefficient[..1]);
        if digits > 1 {
            out.push('.');
            out.push_str(&coefficient[1..]);
        }
        out.push('E');
        if adjusted >= 0 {
            out.push('+');
        }
        let _ = write!(out, "{}", adjusted);
    }
    out
}

pub fn number_text(num: &Num) -> String {
    match &num.text {
        Some(text) => canonical_literal(text),
        None => format_double(num.value),
    }
}

pub fn escape_into(out: &mut String, text: &str) {
    out.push('"');
    if !text.bytes().any(|b| b < 0x20 || b == b'"' || b == b'\\' || b == 0x7f) {
        out.push_str(text);
        out.push('"');
        return;
    }
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

pub fn quote(text: &str) -> String {
    let mut out = String::new();
    escape_into(&mut out, text);
    out
}

fn indent(out: &mut String, step: Option<usize>, depth: usize) {
    if let Some(step) = step {
        out.push('\n');
        for _ in 0..(step * depth) {
            out.push(' ');
        }
    }
}

fn write_value(out: &mut String, value: &Value, step: Option<usize>, depth: usize) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Num(n) => out.push_str(&number_text(n)),
        Value::Str(s) => escape_into(out, s),
        Value::Arr(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                indent(out, step, depth + 1);
                write_value(out, item, step, depth + 1);
            }
            indent(out, step, depth);
            out.push(']');
        }
        Value::Obj(map) => {
            if map.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (key, item)) in map.entries.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                indent(out, step, depth + 1);
                escape_into(out, key);
                out.push(':');
                if step.is_some() {
                    out.push(' ');
                }
                write_value(out, item, step, depth + 1);
            }
            indent(out, step, depth);
            out.push('}');
        }
    }
}

struct Parser<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Parser<'a> {
    fn skip_space(&mut self) {
        while self.at < self.bytes.len() && matches!(self.bytes[self.at], b' ' | b'\t' | b'\n' | b'\r') {
            self.at += 1;
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.at).copied()
    }

    fn literal(&mut self, word: &str) -> Result<(), ()> {
        if self.bytes[self.at..].starts_with(word.as_bytes()) {
            self.at += word.len();
            Ok(())
        } else {
            Err(())
        }
    }

    fn value(&mut self) -> Result<Value, ()> {
        self.skip_space();
        match self.peek().ok_or(())? {
            b'{' => {
                self.at += 1;
                let mut map = Map::new();
                self.skip_space();
                if self.peek() == Some(b'}') {
                    self.at += 1;
                    return Ok(Value::Obj(map));
                }
                loop {
                    self.skip_space();
                    if self.peek() != Some(b'"') {
                        return Err(());
                    }
                    let key = self.string()?;
                    self.skip_space();
                    if self.peek() != Some(b':') {
                        return Err(());
                    }
                    self.at += 1;
                    let item = self.value()?;
                    map.insert(&key, item);
                    self.skip_space();
                    match self.peek() {
                        Some(b',') => self.at += 1,
                        Some(b'}') => {
                            self.at += 1;
                            return Ok(Value::Obj(map));
                        }
                        _ => return Err(()),
                    }
                }
            }
            b'[' => {
                self.at += 1;
                let mut items = Vec::new();
                self.skip_space();
                if self.peek() == Some(b']') {
                    self.at += 1;
                    return Ok(Value::Arr(items));
                }
                loop {
                    items.push(self.value()?);
                    self.skip_space();
                    match self.peek() {
                        Some(b',') => self.at += 1,
                        Some(b']') => {
                            self.at += 1;
                            return Ok(Value::Arr(items));
                        }
                        _ => return Err(()),
                    }
                }
            }
            b'"' => Ok(Value::Str(self.string()?)),
            b't' => self.literal("true").map(|_| Value::Bool(true)),
            b'f' => self.literal("false").map(|_| Value::Bool(false)),
            b'n' => self.literal("null").map(|_| Value::Null),
            b'-' | b'0'..=b'9' => self.number(),
            _ => Err(()),
        }
    }

    fn number(&mut self) -> Result<Value, ()> {
        let start = self.at;
        if self.peek() == Some(b'-') {
            self.at += 1;
        }
        let digits_start = self.at;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.at += 1;
        }
        if self.at == digits_start {
            return Err(());
        }
        if self.peek() == Some(b'.') {
            self.at += 1;
            let fraction_start = self.at;
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.at += 1;
            }
            if self.at == fraction_start {
                return Err(());
            }
        }
        if matches!(self.peek(), Some(b'e') | Some(b'E')) {
            self.at += 1;
            if matches!(self.peek(), Some(b'+') | Some(b'-')) {
                self.at += 1;
            }
            let exponent_start = self.at;
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.at += 1;
            }
            if self.at == exponent_start {
                return Err(());
            }
        }
        let text = std::str::from_utf8(&self.bytes[start..self.at]).map_err(|_| ())?;
        let value: f64 = text.parse().map_err(|_| ())?;
        Ok(Value::Num(Num { text: Some(text.to_string()), value }))
    }

    fn hex4(&mut self) -> Result<u32, ()> {
        if self.at + 4 > self.bytes.len() {
            return Err(());
        }
        let text = std::str::from_utf8(&self.bytes[self.at..self.at + 4]).map_err(|_| ())?;
        let code = u32::from_str_radix(text, 16).map_err(|_| ())?;
        self.at += 4;
        Ok(code)
    }

    fn string(&mut self) -> Result<String, ()> {
        self.at += 1;
        let mut out: Vec<u8> = Vec::new();
        loop {
            let byte = self.peek().ok_or(())?;
            match byte {
                b'"' => {
                    self.at += 1;
                    return Ok(String::from_utf8_lossy(&out).into_owned());
                }
                b'\\' => {
                    self.at += 1;
                    let escape = self.peek().ok_or(())?;
                    self.at += 1;
                    match escape {
                        b'"' => out.push(b'"'),
                        b'\\' => out.push(b'\\'),
                        b'/' => out.push(b'/'),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'n' => out.push(b'\n'),
                        b'r' => out.push(b'\r'),
                        b't' => out.push(b'\t'),
                        b'u' => {
                            let mut code = self.hex4()?;
                            if (0xD800..0xDC00).contains(&code) {
                                if self.bytes[self.at..].starts_with(b"\\u") {
                                    self.at += 2;
                                    let low = self.hex4()?;
                                    if (0xDC00..0xE000).contains(&low) {
                                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                                    } else {
                                        code = 0xFFFD;
                                        self.at -= 6;
                                    }
                                } else {
                                    code = 0xFFFD;
                                }
                            } else if (0xDC00..0xE000).contains(&code) {
                                code = 0xFFFD;
                            }
                            let c = char::from_u32(code).unwrap_or('\u{FFFD}');
                            let mut buffer = [0u8; 4];
                            out.extend_from_slice(c.encode_utf8(&mut buffer).as_bytes());
                        }
                        _ => return Err(()),
                    }
                }
                byte if byte < 0x20 => return Err(()),
                byte => {
                    out.push(byte);
                    self.at += 1;
                }
            }
        }
    }
}

pub fn arr_of_strings(items: &[String]) -> Value {
    Value::Arr(items.iter().map(|s| Value::str(s)).collect())
}

pub fn unique_sorted(mut items: Vec<Value>) -> Vec<Value> {
    items.sort_by(jq_cmp);
    items.dedup_by(|a, b| jq_cmp(a, b) == Ordering::Equal);
    items
}
