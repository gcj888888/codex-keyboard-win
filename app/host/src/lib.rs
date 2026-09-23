//! Host 的公共入口。
//!
//! 这里集中提供「带墙上时间戳的日志」与「给模型注入当前时间」两个小工具：
//! 原先 Host 的每一条输出都没有时间，排查时只能靠行号猜先后顺序。

use std::time::{SystemTime, UNIX_EPOCH};

/// 取本机时区下的日历时间。
fn local_tm() -> Option<libc::tm> {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as libc::time_t;
    let mut parts: libc::tm = unsafe { std::mem::zeroed() };
    let converted = unsafe { libc::localtime_r(&seconds, &mut parts) };
    if converted.is_null() { None } else { Some(parts) }
}

/// 日志用的时间戳：`YYYY-MM-DD HH:MM:SS.mmm`。
pub fn time_stamp() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let millis = now.subsec_millis();
    match local_tm() {
        Some(t) => format!(
            "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
            t.tm_year + 1900,
            t.tm_mon + 1,
            t.tm_mday,
            t.tm_hour,
            t.tm_min,
            t.tm_sec,
            millis
        ),
        None => format!("{}.{:03}", now.as_secs(), millis),
    }
}

/// 给人看的时间：`YYYY-MM-DD HH:MM:SS`（不带毫秒），用于注入模型上下文。
pub fn local_datetime_human() -> String {
    match local_tm() {
        Some(t) => format!(
            "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
            t.tm_year + 1900,
            t.tm_mon + 1,
            t.tm_mday,
            t.tm_hour,
            t.tm_min,
            t.tm_sec
        ),
        None => "未知".to_owned(),
    }
}

/// 中文星期几。
pub fn local_weekday_cn() -> &'static str {
    match local_tm().map(|t| t.tm_wday) {
        Some(0) => "星期日",
        Some(1) => "星期一",
        Some(2) => "星期二",
        Some(3) => "星期三",
        Some(4) => "星期四",
        Some(5) => "星期五",
        Some(6) => "星期六",
        _ => "未知",
    }
}

/// 带时间戳写 stderr。用法与 `eprintln!` 完全一致。
#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {{
        let rendered = format!($($arg)*);
        eprintln!("[{}] {}", $crate::time_stamp(), rendered);
    }};
}

pub mod audio;
pub mod bindings;
pub mod cache;
pub mod codex_catalog;
pub mod codex_runner;
pub mod dashscope;
pub mod health;
pub mod lan_playback;
pub mod lan_voice;
pub mod launch_agent;
pub mod paths;
pub mod prompt_queue;
pub mod provisioning;
pub mod rollout_observer;
pub mod secrets;
pub mod spark_runner;
pub mod store;
pub mod summary;
pub mod summary_orchestrator;
#[cfg(any(target_os = "macos", target_os = "linux"))]
pub mod summary_worker;
pub mod tts_cache;
