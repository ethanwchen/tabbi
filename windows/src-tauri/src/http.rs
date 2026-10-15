//! HTTP on the UI's behalf, to an allow-list only. Requests from Rust need no
//! CORS, so AnkiConnect and Ollama on localhost work as they are.
//!
//! Two kinds of request exist:
//! - API requests (any of GET, POST, PUT, PATCH, DELETE, with headers and a
//!   body) to exact origins: AnkiConnect and Ollama on the loopback address,
//!   the Claude, OpenAI and Gemini APIs, the Party Worker, and a plain-http
//!   loopback Worker for development. They never follow redirects, and their
//!   response comes back whole or streams to the UI chunk by chunk (AI
//!   replies).
//! - Calendar fetches: a GET of a user-entered ICS address, https on any
//!   public host (`webcal://` counts as https), capped in size, followed
//!   through https redirects only, and only returned when the reply is a
//!   calendar.
//!
//! The official HTTP plugin's JavaScript `fetch` was not used: its scope is a
//! static list of URL patterns, which cannot say "GET only and size-capped for
//! any https host" for calendars or "no redirects off the list", and it would
//! put the allow-list in a capability file instead of tested code. Its
//! re-exported `reqwest` client (with rustls) is used directly instead, and
//! the plugin itself is never registered, so the UI gets no `fetch` of its own.

use crate::error::{HostError, HostResult};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::Mutex;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;
use tauri::async_runtime::JoinHandle;
use tauri::ipc::Channel;
use tauri::{AppHandle, Manager};
use tauri_plugin_http::reqwest::{self, Url, header, redirect};

/// The production Party Worker.
pub const PARTY_SERVER: &str = "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev";

/// Every API origin, exactly (scheme, host and port).
pub const API_ORIGINS: [&str; 8] = [
    "http://127.0.0.1:8765",
    "http://localhost:8765",
    "http://127.0.0.1:11434",
    "http://localhost:11434",
    "https://api.anthropic.com",
    "https://api.openai.com",
    "https://generativelanguage.googleapis.com",
    PARTY_SERVER,
];

/// `wrangler dev`'s default address, allowed in development builds.
const DEV_WORKER: [&str; 2] = ["http://localhost:8787", "http://127.0.0.1:8787"];

const API_METHODS: [&str; 5] = ["GET", "POST", "PUT", "PATCH", "DELETE"];

/// Headers the client sets itself, or that would let a request carry more
/// than the UI's own data.
const FORBIDDEN_HEADERS: [&str; 7] = [
    "host",
    "connection",
    "content-length",
    "transfer-encoding",
    "cookie",
    "proxy-authorization",
    "upgrade",
];

pub const MAX_RESPONSE: usize = 16 << 20;
pub const MAX_CALENDAR: usize = 8 << 20;
const MAX_REDIRECTS: usize = 5;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
/// A whole non-streamed reply; long enough for a slow AI answer.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(300);
/// A stream that goes quiet this long has stalled.
const IDLE_TIMEOUT: Duration = Duration::from_secs(120);

fn blocked(message: impl Into<String>) -> HostError {
    HostError::new("blocked", message)
}

/// The origins API requests may reach. `dev_worker` is the development
/// Worker: plain-http loopback only, so a development run can never register
/// users on a deployed server (the Mac's rule for `TABBI_PARTY_SERVER`).
#[derive(Debug, Clone)]
pub struct Policy {
    origins: Vec<Url>,
}

/// A plain-http loopback address with a port, the only kind of development
/// Worker accepted.
pub fn dev_worker_origin(text: &str) -> Option<Url> {
    let url = Url::parse(text.trim()).ok()?;
    let loopback = match host_ip(&url) {
        Some(ip) => ip.is_loopback(),
        None => url.host_str() == Some("localhost"),
    };
    (url.scheme() == "http" && loopback && url.username().is_empty() && url.password().is_none())
        .then_some(url)
}

impl Policy {
    pub fn new(dev_workers: &[&str]) -> Self {
        let origins = API_ORIGINS
            .iter()
            .filter_map(|origin| Url::parse(origin).ok())
            .chain(
                dev_workers
                    .iter()
                    .filter_map(|text| dev_worker_origin(text)),
            )
            .collect();
        Self { origins }
    }

    /// The real policy: development builds also allow `wrangler dev`, and any
    /// build allows a loopback `TABBI_PARTY_SERVER`.
    pub fn from_environment() -> Self {
        let mut dev: Vec<String> = Vec::new();
        if cfg!(debug_assertions) {
            dev.extend(DEV_WORKER.iter().map(|s| (*s).to_owned()));
        }
        if let Ok(server) = std::env::var("TABBI_PARTY_SERVER") {
            dev.push(server);
        }
        let dev: Vec<&str> = dev.iter().map(String::as_str).collect();
        Self::new(&dev)
    }

    /// Checks an API request and returns its parsed address.
    pub fn check_api(&self, method: &str, url: &str) -> HostResult<Url> {
        let url = Url::parse(url).map_err(|_| HostError::new("invalid", "not a valid address"))?;
        if !url.username().is_empty() || url.password().is_some() {
            return Err(blocked(
                "addresses with a user name or password are not allowed",
            ));
        }
        if !self
            .origins
            .iter()
            .any(|allowed| allowed.origin() == url.origin())
        {
            return Err(blocked(format!(
                "{} is not on Tabbi's list of services",
                url.origin().ascii_serialization()
            )));
        }
        if !API_METHODS.contains(&method) {
            return Err(blocked(format!("the method {method} is not allowed")));
        }
        Ok(url)
    }
}

/// The address of a host given as an IP literal (`[::1]` included).
fn host_ip(url: &Url) -> Option<IpAddr> {
    let host = url.host_str()?;
    host.trim_start_matches('[')
        .trim_end_matches(']')
        .parse()
        .ok()
}

fn private_v4(ip: Ipv4Addr) -> bool {
    ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_unspecified()
        || ip.is_broadcast()
        || ip.is_documentation()
        /* Carrier-grade NAT, 100.64.0.0/10. */
        || (ip.octets()[0] == 100 && (ip.octets()[1] & 0xc0) == 64)
}

fn private_v6(ip: Ipv6Addr) -> bool {
    let first = ip.segments()[0];
    ip.is_loopback()
        || ip.is_unspecified()
        || (first & 0xfe00) == 0xfc00
        || (first & 0xffc0) == 0xfe80
        || ip.to_ipv4_mapped().is_some_and(private_v4)
}

/// Whether a calendar address points into this PC or the local network, which
/// a typed-in calendar address must never reach.
fn local_host(url: &Url) -> bool {
    match (host_ip(url), url.host_str()) {
        (Some(IpAddr::V4(ip)), _) => private_v4(ip),
        (Some(IpAddr::V6(ip)), _) => private_v6(ip),
        (None, Some(domain)) => {
            let domain = domain.trim_end_matches('.');
            domain == "localhost" || domain.ends_with(".localhost") || !domain.contains('.')
        }
        (None, None) => true,
    }
}

/// Checks one hop of a calendar fetch (the typed address or a redirect).
pub fn check_calendar_url(url: &Url) -> HostResult<()> {
    if url.scheme() != "https" {
        return Err(blocked("calendar addresses must use https"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(blocked(
            "addresses with a user name or password are not allowed",
        ));
    }
    if local_host(url) {
        return Err(blocked(
            "calendar addresses must be on the internet, not this network",
        ));
    }
    Ok(())
}

/// Parses a typed calendar address; `webcal://` (what calendar apps share)
/// means https.
pub fn calendar_url(text: &str) -> HostResult<Url> {
    let text = text.trim();
    let text = match text.get(..9) {
        Some(scheme) if scheme.eq_ignore_ascii_case("webcal://") => {
            format!("https://{}", &text[9..])
        }
        _ => text.to_owned(),
    };
    let url = Url::parse(&text).map_err(|_| HostError::new("invalid", "not a valid address"))?;
    check_calendar_url(&url)?;
    Ok(url)
}

/// Whether a reply is an iCalendar file.
pub fn looks_like_calendar(body: &str) -> bool {
    let body = body.trim_start_matches('\u{feff}').trim_start();
    body.get(..15)
        .is_some_and(|start| start.eq_ignore_ascii_case("BEGIN:VCALENDAR"))
}

/// Checks the UI's headers and builds them.
pub fn headers(list: &[(String, String)]) -> HostResult<header::HeaderMap> {
    let mut map = header::HeaderMap::new();
    for (name, value) in list {
        let name = header::HeaderName::from_bytes(name.trim().as_bytes())
            .map_err(|_| HostError::new("invalid", format!("\"{name}\" is not a header name")))?;
        if FORBIDDEN_HEADERS.contains(&name.as_str()) || name.as_str().starts_with("proxy-") {
            return Err(blocked(format!("the header {name} is not allowed")));
        }
        /* The value is not echoed: it can be an API key. */
        let value = header::HeaderValue::from_str(value)
            .map_err(|_| HostError::new("invalid", format!("the {name} header has a bad value")))?;
        map.append(name, value);
    }
    Ok(map)
}

/// Response headers, lowercase, repeated ones joined with ", ".
pub fn header_map(headers: &header::HeaderMap) -> BTreeMap<String, String> {
    let mut map: BTreeMap<String, String> = BTreeMap::new();
    for (name, value) in headers {
        let value = String::from_utf8_lossy(value.as_bytes()).into_owned();
        map.entry(name.as_str().to_owned())
            .and_modify(|existing| {
                existing.push_str(", ");
                existing.push_str(&value);
            })
            .or_insert(value);
    }
    map
}

/// Turns a byte stream into text without splitting a character across two
/// chunks; invalid bytes become U+FFFD.
#[derive(Debug, Default)]
pub struct Utf8Stream {
    pending: Vec<u8>,
}

impl Utf8Stream {
    pub fn push(&mut self, bytes: &[u8]) -> String {
        self.pending.extend_from_slice(bytes);
        let mut out = String::new();
        loop {
            match std::str::from_utf8(&self.pending) {
                Ok(text) => {
                    out.push_str(text);
                    self.pending.clear();
                    return out;
                }
                Err(error) => {
                    let valid = error.valid_up_to();
                    out.push_str(std::str::from_utf8(&self.pending[..valid]).unwrap_or_default());
                    match error.error_len() {
                        /* An unfinished character at the end: wait for the rest. */
                        None => {
                            self.pending.drain(..valid);
                            return out;
                        }
                        Some(bad) => {
                            out.push('\u{fffd}');
                            self.pending.drain(..valid + bad);
                        }
                    }
                }
            }
        }
    }

    /// Whatever is left when the stream ends.
    pub fn finish(&mut self) -> String {
        let rest = String::from_utf8_lossy(&self.pending).into_owned();
        self.pending.clear();
        rest
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HttpRequest {
    pub method: String,
    pub url: String,
    #[serde(default)]
    pub headers: Vec<(String, String)>,
    pub body: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HttpResponse {
    pub status: u16,
    pub headers: BTreeMap<String, String>,
    pub body: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum StreamEvent {
    Head {
        status: u16,
        headers: BTreeMap<String, String>,
    },
    Chunk {
        text: String,
    },
    End,
    Error {
        error: HostError,
    },
}

fn network(error: reqwest::Error) -> HostError {
    if error.is_timeout() {
        HostError::new("timeout", "the service took too long to answer")
    } else {
        /* Without the URL: a calendar address can hold a private token. */
        HostError::new("network", error.without_url().to_string())
    }
}

fn too_large(limit: usize) -> HostError {
    HostError::new(
        "tooLarge",
        format!("the reply is larger than {} MB", limit >> 20),
    )
}

/// Reads a reply up to `limit` bytes.
async fn read_capped(mut response: reqwest::Response, limit: usize) -> HostResult<Vec<u8>> {
    if response
        .content_length()
        .is_some_and(|length| length > limit as u64)
    {
        return Err(too_large(limit));
    }
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(network)? {
        if body.len() + chunk.len() > limit {
            return Err(too_large(limit));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

/// A stream in flight: its task, and its channel for the cancel notice.
type Running = (JoinHandle<()>, Channel<StreamEvent>);

pub struct Http {
    policy: Policy,
    api: reqwest::Client,
    calendar: reqwest::Client,
    next_stream: AtomicU32,
    streams: Mutex<HashMap<u32, Running>>,
}

impl Http {
    pub fn new() -> Self {
        let user_agent = concat!("Tabbi/", env!("CARGO_PKG_VERSION"), " (Windows)");
        let api = reqwest::Client::builder()
            .user_agent(user_agent)
            .connect_timeout(CONNECT_TIMEOUT)
            .read_timeout(IDLE_TIMEOUT)
            .redirect(redirect::Policy::none())
            .build()
            .expect("the HTTP client builds");
        let calendar = reqwest::Client::builder()
            .user_agent(user_agent)
            .connect_timeout(CONNECT_TIMEOUT)
            .timeout(REQUEST_TIMEOUT)
            .redirect(redirect::Policy::custom(|attempt| {
                if attempt.previous().len() >= MAX_REDIRECTS {
                    attempt.error("too many redirects")
                } else if check_calendar_url(attempt.url()).is_err() {
                    attempt.error("the calendar redirected to an address that is not allowed")
                } else {
                    attempt.follow()
                }
            }))
            .build()
            .expect("the HTTP client builds");
        Self {
            policy: Policy::from_environment(),
            api,
            calendar,
            next_stream: AtomicU32::new(1),
            streams: Mutex::new(HashMap::new()),
        }
    }

    fn build(&self, request: &HttpRequest) -> HostResult<reqwest::RequestBuilder> {
        let method = request.method.to_ascii_uppercase();
        let url = self.policy.check_api(&method, &request.url)?;
        let method = reqwest::Method::from_bytes(method.as_bytes())
            .map_err(|_| HostError::new("invalid", "not an HTTP method"))?;
        let mut builder = self
            .api
            .request(method, url)
            .headers(headers(&request.headers)?);
        if let Some(body) = &request.body {
            builder = builder.body(body.clone());
        }
        Ok(builder)
    }
}

/// An API request, answered whole.
#[tauri::command]
pub async fn http_request(app: AppHandle, request: HttpRequest) -> HostResult<HttpResponse> {
    let builder = app.state::<Http>().build(&request)?;
    let response = builder
        .timeout(REQUEST_TIMEOUT)
        .send()
        .await
        .map_err(network)?;
    let status = response.status().as_u16();
    let headers = header_map(response.headers());
    let body = read_capped(response, MAX_RESPONSE).await?;
    Ok(HttpResponse {
        status,
        headers,
        body: String::from_utf8_lossy(&body).into_owned(),
    })
}

async fn stream(
    builder: reqwest::RequestBuilder,
    channel: &Channel<StreamEvent>,
) -> HostResult<()> {
    let mut response = builder.send().await.map_err(network)?;
    let _ = channel.send(StreamEvent::Head {
        status: response.status().as_u16(),
        headers: header_map(response.headers()),
    });
    let mut text = Utf8Stream::default();
    let mut total = 0usize;
    while let Some(chunk) = response.chunk().await.map_err(network)? {
        total += chunk.len();
        if total > MAX_RESPONSE {
            return Err(too_large(MAX_RESPONSE));
        }
        let piece = text.push(&chunk);
        if !piece.is_empty() {
            let _ = channel.send(StreamEvent::Chunk { text: piece });
        }
    }
    let rest = text.finish();
    if !rest.is_empty() {
        let _ = channel.send(StreamEvent::Chunk { text: rest });
    }
    Ok(())
}

/// An API request whose reply streams to `on_event`: a head, text chunks as
/// they arrive, then an end or an error. Returns an id for `http_cancel`.
#[tauri::command]
pub fn http_stream(
    app: AppHandle,
    request: HttpRequest,
    on_event: Channel<StreamEvent>,
) -> HostResult<u32> {
    let http = app.state::<Http>();
    let builder = http.build(&request)?;
    let id = http.next_stream.fetch_add(1, Ordering::Relaxed);
    let mut streams = http.streams.lock().expect("http streams lock");
    let task_app = app.clone();
    let channel = on_event.clone();
    let task = tauri::async_runtime::spawn(async move {
        let last = match stream(builder, &channel).await {
            Ok(()) => StreamEvent::End,
            Err(error) => StreamEvent::Error { error },
        };
        let _ = channel.send(last);
        let http = task_app.state::<Http>();
        http.streams.lock().expect("http streams lock").remove(&id);
    });
    streams.insert(id, (task, on_event));
    Ok(id)
}

/// Stops a stream; it ends with a `cancelled` error. False when it had
/// already finished.
#[tauri::command]
pub fn http_cancel(app: AppHandle, id: u32) -> bool {
    let removed = app
        .state::<Http>()
        .streams
        .lock()
        .expect("http streams lock")
        .remove(&id);
    match removed {
        Some((task, channel)) => {
            task.abort();
            let _ = channel.send(StreamEvent::Error {
                error: HostError::new("cancelled", "the request was stopped"),
            });
            true
        }
        None => false,
    }
}

/// Fetches a user-entered ICS calendar and returns its text.
#[tauri::command]
pub async fn http_fetch_calendar(app: AppHandle, url: String) -> HostResult<String> {
    let url = calendar_url(&url)?;
    let response = app
        .state::<Http>()
        .calendar
        .get(url)
        .header(header::ACCEPT, "text/calendar, text/plain;q=0.5, */*;q=0.1")
        .send()
        .await
        .map_err(network)?;
    let status = response.status();
    if !status.is_success() {
        return Err(HostError::new(
            "status",
            format!("the calendar server answered {}", status.as_u16()),
        ));
    }
    let body = read_capped(response, MAX_CALENDAR).await?;
    let text = String::from_utf8_lossy(&body).into_owned();
    if !looks_like_calendar(&text) {
        return Err(HostError::new(
            "notCalendar",
            "the address did not return a calendar",
        ));
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy() -> Policy {
        Policy::new(&[])
    }

    #[test]
    fn every_listed_service_is_allowed() {
        let p = policy();
        for url in [
            "http://127.0.0.1:8765",
            "http://127.0.0.1:8765/",
            "http://localhost:8765/",
            "http://localhost:11434/api/chat",
            "http://127.0.0.1:11434/api/tags",
            "https://api.anthropic.com/v1/messages",
            "https://api.openai.com/v1/chat/completions",
            "https://generativelanguage.googleapis.com/v1beta/models/gemini:streamGenerateContent?alt=sse",
            "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev/v1/me",
            "https://api.anthropic.com:443/v1/messages",
            "HTTPS://API.ANTHROPIC.COM/v1/messages",
            "http://LOCALHOST:8765",
        ] {
            assert!(p.check_api("POST", url).is_ok(), "{url} should be allowed");
        }
    }

    #[test]
    fn near_misses_are_blocked() {
        let p = policy();
        for url in [
            "http://api.anthropic.com/v1/messages",
            "https://api.anthropic.com:8443/v1/messages",
            "https://api.anthropic.com.evil.com/v1/messages",
            "https://evil.com/api.anthropic.com",
            "https://sub.api.openai.com/v1",
            "https://openai.com/",
            "https://localhost:8765/",
            "http://localhost:8766/",
            "http://localhost/",
            "http://127.0.0.2:8765/",
            "http://[::1]:8765/",
            "http://0.0.0.0:11434/",
            "http://192.168.1.10:11434/",
            "http://localhost:8765@evil.com/",
            "https://user:pass@api.openai.com/v1",
            "https://key@api.openai.com/v1",
            "http://localhost:8787/v1/me",
            "https://tabbi-friends.workers.dev/v1/me",
            "file:///C:/Windows/win.ini",
            "ftp://api.openai.com/",
            "ws://localhost:8765/",
        ] {
            let error = p.check_api("GET", url).unwrap_err();
            assert_eq!(error.code, "blocked", "{url} should be blocked");
        }
        assert_eq!(p.check_api("GET", "not a url").unwrap_err().code, "invalid");
        assert_eq!(p.check_api("GET", "").unwrap_err().code, "invalid");
    }

    #[test]
    fn only_the_rest_methods_are_allowed() {
        let p = policy();
        for method in API_METHODS {
            assert!(
                p.check_api(method, "https://api.openai.com/v1/models")
                    .is_ok()
            );
        }
        for method in ["CONNECT", "TRACE", "OPTIONS", "HEAD", "get", ""] {
            assert!(
                p.check_api(method, "https://api.openai.com/v1/models")
                    .is_err(),
                "{method}"
            );
        }
    }

    #[test]
    fn a_development_worker_must_be_plain_http_on_loopback() {
        let p = Policy::new(&[
            "http://localhost:8787",
            "http://127.0.0.1:9999/",
            " http://[::1]:8788 ",
            "https://localhost:8789",
            "http://tabbi-friends.drosophil-anki-friends-backend.workers.dev",
            "http://192.168.1.2:8787",
            "http://user@localhost:8790",
            "nonsense",
        ]);
        assert!(
            p.check_api("POST", "http://localhost:8787/v1/register")
                .is_ok()
        );
        assert!(p.check_api("GET", "http://127.0.0.1:9999/v1/me").is_ok());
        assert!(p.check_api("GET", "http://[::1]:8788/v1/me").is_ok());
        assert!(p.check_api("GET", "https://localhost:8789/").is_err());
        assert!(p.check_api("GET", "http://192.168.1.2:8787/").is_err());
        assert!(p.check_api("GET", "http://localhost:8790/").is_err());
        assert!(
            p.check_api("GET", "http://127.0.0.1:8787/").is_err(),
            "only the exact origin given"
        );
    }

    #[test]
    fn calendar_addresses_are_https_on_public_hosts() {
        for ok in [
            "https://calendar.google.com/calendar/ical/abc%40group/private-123/basic.ics",
            "webcal://p42-caldav.icloud.com/published/2/abc",
            "WEBCAL://outlook.office365.com/owa/calendar/x/reachcalendar.ics",
            "  https://example.org:8443/cal.ics  ",
            "https://8.8.8.8/cal.ics",
        ] {
            assert!(calendar_url(ok).is_ok(), "{ok}");
        }
        assert_eq!(
            calendar_url("webcal://example.org/a.ics").unwrap().as_str(),
            "https://example.org/a.ics"
        );
        for bad in [
            "http://example.org/cal.ics",
            "ftp://example.org/cal.ics",
            "file:///C:/cal.ics",
            "https://localhost/cal.ics",
            "https://calendar.localhost/cal.ics",
            "https://intranet/cal.ics",
            "https://127.0.0.1/cal.ics",
            "https://10.0.0.5/cal.ics",
            "https://172.16.0.1/cal.ics",
            "https://192.168.0.1/cal.ics",
            "https://169.254.169.254/latest/meta-data",
            "https://100.64.0.1/cal.ics",
            "https://0.0.0.0/cal.ics",
            "https://[::1]/cal.ics",
            "https://[fd00::1]/cal.ics",
            "https://[fe80::1]/cal.ics",
            "https://[::ffff:192.168.0.1]/cal.ics",
            "https://user:pw@example.org/cal.ics",
        ] {
            assert!(calendar_url(bad).is_err(), "{bad}");
        }
        assert_eq!(calendar_url("webcal").unwrap_err().code, "invalid");
    }

    #[test]
    fn only_calendar_replies_count() {
        assert!(looks_like_calendar("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"));
        assert!(looks_like_calendar(
            "\u{feff}\r\n  begin:vcalendar\nEND:VCALENDAR"
        ));
        assert!(!looks_like_calendar("<!DOCTYPE html><html>"));
        assert!(!looks_like_calendar("BEGIN:VCARD"));
        assert!(!looks_like_calendar(""));
    }

    #[test]
    fn request_headers_are_checked_and_values_never_echoed() {
        let ok = headers(&[
            ("x-api-key".into(), "sk-ant-secret".into()),
            ("Content-Type".into(), "application/json".into()),
            ("anthropic-version".into(), "2023-06-01".into()),
        ])
        .unwrap();
        assert_eq!(ok.len(), 3);
        for name in [
            "Host",
            "cookie",
            "Content-Length",
            "transfer-encoding",
            "Proxy-Authorization",
            "proxy-connection",
            "connection",
        ] {
            assert_eq!(
                headers(&[(name.into(), "x".into())]).unwrap_err().code,
                "blocked",
                "{name}"
            );
        }
        assert_eq!(
            headers(&[("bad name".into(), "x".into())])
                .unwrap_err()
                .code,
            "invalid"
        );
        let error = headers(&[("authorization".into(), "Bearer sec\nret".into())]).unwrap_err();
        assert_eq!(error.code, "invalid");
        assert!(!error.message.contains("sec"));
    }

    #[test]
    fn response_headers_are_lowercase_and_joined() {
        let mut map = header::HeaderMap::new();
        map.append("ETag", header::HeaderValue::from_static("\"v7\""));
        map.append("Retry-After", header::HeaderValue::from_static("30"));
        map.append("vary", header::HeaderValue::from_static("a"));
        map.append("vary", header::HeaderValue::from_static("b"));
        let out = header_map(&map);
        assert_eq!(out.get("etag").map(String::as_str), Some("\"v7\""));
        assert_eq!(out.get("retry-after").map(String::as_str), Some("30"));
        assert_eq!(out.get("vary").map(String::as_str), Some("a, b"));
    }

    #[test]
    fn streamed_text_never_splits_a_character() {
        let mut stream = Utf8Stream::default();
        let text = "caf\u{e9} \u{1f600}!";
        let bytes = text.as_bytes();
        let mut out = String::new();
        for byte in bytes {
            out.push_str(&stream.push(std::slice::from_ref(byte)));
        }
        out.push_str(&stream.finish());
        assert_eq!(out, text);

        let mut stream = Utf8Stream::default();
        assert_eq!(stream.push(&[b'a', 0xe2, 0x82]), "a");
        assert_eq!(stream.push(&[0xac, b'b']), "\u{20ac}b");
    }

    #[test]
    fn invalid_bytes_become_replacement_characters() {
        let mut stream = Utf8Stream::default();
        assert_eq!(stream.push(&[b'a', 0xff, b'b', 0xc3]), "a\u{fffd}b");
        assert_eq!(
            stream.finish(),
            "\u{fffd}",
            "a cut-off character at the end"
        );
        assert_eq!(stream.finish(), "");
    }

    #[test]
    fn stream_events_use_the_ui_shapes() {
        let json = |event: StreamEvent| serde_json::to_value(event).unwrap();
        assert_eq!(
            json(StreamEvent::Chunk { text: "hi".into() }),
            serde_json::json!({ "type": "chunk", "text": "hi" })
        );
        assert_eq!(json(StreamEvent::End), serde_json::json!({ "type": "end" }));
        assert_eq!(
            json(StreamEvent::Error {
                error: HostError::new("cancelled", "stopped")
            }),
            serde_json::json!({ "type": "error", "error": { "code": "cancelled", "message": "stopped" } })
        );
        let request: HttpRequest = serde_json::from_value(serde_json::json!({
            "method": "POST",
            "url": "https://api.openai.com/v1/chat/completions",
            "headers": [["authorization", "Bearer x"]],
            "body": "{}"
        }))
        .unwrap();
        assert_eq!(request.headers.len(), 1);
        let bare: HttpRequest =
            serde_json::from_value(serde_json::json!({ "method": "GET", "url": "x" })).unwrap();
        assert!(bare.headers.is_empty() && bare.body.is_none());
    }
}
