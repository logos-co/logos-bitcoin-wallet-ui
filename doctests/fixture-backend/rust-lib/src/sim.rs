//! The scripted wallet behind the fixture. States move on a clock; a send's fate is picked by its
//! amount; the first send that goes out makes the history server report a confirmation on another
//! chain, so the app has a suspect source to clear. Nothing here touches a network or a key.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

pub const APP: &str = "bitcoin_wallet_ui";
/// Amounts, in satoshis, that pick a send's fate; any other amount is approved and sent.
pub const REJECTED_SAT: u64 = 20_000;
pub const EXPIRED_SAT: u64 = 30_000;
pub const UNKNOWN_SAT: u64 = 40_000;
pub const SMALL_CHANGE_SAT: u64 = 50_000;

// The backend's own words, so the app is tested against what it will read.
pub const NO_ACK: &str = "expired: nobody acknowledged the approval within 60 s; request the send again";
pub const REJECTED: &str = "rejected: the person declined in the signer app";
pub const MAY_HAVE_LEFT: &str = "the transaction may have left: rebroadcast it or replace it with a higher fee; never pay again from other coins while it could still confirm";
pub const ABANDONED: &str = "Abandoned: its coins are free to spend again. If the original transaction still confirms, a later send from those coins will fail; if a later send confirms first, it replaces the original.";
pub const LOCKED: &str = "source settings are locked while a wallet is open; close it first";

const VSIZE: u64 = 141;
const COIN_SAT: u64 = 10_000_000;
const TIP_AGE_SECS: u64 = 240;
const OPEN_APPROVE: Duration = Duration::from_secs(4);
const STEP: Duration = Duration::from_millis(1000);
const SYNC_TIME: Duration = Duration::from_secs(3);

pub enum Event {
    WalletState(Value),
    SyncProgress(Value),
    Balance(Value),
    SendStatus(String, String),
    JobFinished(String, String),
    SourceAlert(Value),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum WState {
    NoWallet,
    AwaitingOpen,
    Opening,
    Syncing,
    Ready,
    Closing,
}

impl WState {
    fn name(self) -> &'static str {
        match self {
            WState::NoWallet => "no_wallet",
            WState::AwaitingOpen => "awaiting_open",
            WState::Opening => "opening",
            WState::Syncing => "syncing",
            WState::Ready => "ready",
            WState::Closing => "closing",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Fate {
    Approve,
    Reject,
    Expire,
    Unknown,
}

struct Job {
    kind: String,
    state: String,
    error: Option<String>,
    result: Value,
    at: Instant,
    send: Option<String>,
}

struct Send {
    id: String,
    kind: String,
    requester: String,
    state: String,
    error: Option<String>,
    code: Option<String>,
    fate: Fate,
    stage_at: Instant,
    amount: u64,
    fee: u64,
    fee_rate: f64,
    input: u64,
    recipient: String,
    txid: String,
    replaces: Option<String>,
    approval: Option<String>,
    handle: Option<String>,
    broadcast: Option<String>,
    via: Option<String>,
    cancelling: bool,
    abandoned: bool,
    small_change: bool,
    created: u64,
    updated: u64,
}

#[derive(Clone)]
struct Source {
    id: String,
    kind: String,
    url: String,
    operator: String,
    label: String,
    enabled: bool,
    history: bool,
    tor: bool,
    suspect: bool,
}

pub struct Sim {
    pub regtest: bool,
    active: String,
    state: WState,
    since: Instant,
    network: String,
    family: String,
    group: String,
    label: Option<String>,
    handle: Option<String>,
    approve_at: Option<Instant>,
    open_job: Option<String>,
    close_job: Option<String>,
    opens: u32,
    jobs: BTreeMap<String, Job>,
    next_job: u64,
    sends: BTreeMap<u64, Send>,
    next_send: u64,
    next_tx: u64,
    sources: BTreeMap<String, Vec<Source>>,
    proxy: String,
    wallets: Vec<Value>,
    receive_index: u32,
    history: Vec<Value>,
    confirmed: u64,
    change: u64,
    alert_at: Option<Instant>,
    alerted: bool,
    last_status: String,
    last_balance: String,
}

pub fn now_secs() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

pub fn format_btc(sat: u64) -> String {
    format!("{}.{:08}", sat / 100_000_000, sat % 100_000_000)
}

pub fn parse_sat(s: &str) -> Result<u64, String> {
    let t = s.trim();
    if t.is_empty() || !t.bytes().all(|b| b.is_ascii_digit()) {
        return Err("not a whole number of satoshis".into());
    }
    t.parse::<u64>().ok().filter(|v| *v <= 2_100_000_000_000_000).ok_or_else(|| "more than the bitcoin supply".into())
}

pub fn parse_btc(s: &str) -> Result<u64, String> {
    let t = s.trim();
    let (whole, frac) = t.split_once('.').unwrap_or((t, ""));
    let digits = |p: &str| p.bytes().all(|b| b.is_ascii_digit());
    if (whole.is_empty() && frac.is_empty()) || !digits(whole) || !digits(frac) {
        return Err("not a BTC amount".into());
    }
    if frac.len() > 8 {
        return Err("at most 8 decimal places".into());
    }
    let w: u64 = if whole.is_empty() { 0 } else { whole.parse().map_err(|_| "more than the bitcoin supply".to_string())? };
    let f: u64 = format!("{frac:0<8}").parse().map_err(|_| "not a BTC amount".to_string())?;
    w.checked_mul(100_000_000).and_then(|v| v.checked_add(f)).filter(|v| *v <= 2_100_000_000_000_000).ok_or_else(|| "more than the bitcoin supply".into())
}

fn btc_of(sat: u64) -> String {
    format_btc(sat)
}

fn hrp(network: &str) -> &'static str {
    match network {
        "mainnet" => "bc",
        "regtest" => "bcrt",
        _ => "tb",
    }
}

fn tip(network: &str) -> u64 {
    match network {
        "mainnet" => 935_500,
        "testnet4" => 120_500,
        "regtest" => 150,
        _ => 290_123,
    }
}

fn birthday(network: &str) -> u64 {
    tip(network).saturating_sub(123)
}

/// A bech32-looking address for an index: fake, and plain about it.
fn address(network: &str, kind: char, n: u64) -> String {
    const CHARSET: &[u8] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    let mut body = String::new();
    let mut x = n.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ 0x5DEE_CE66;
    for _ in 0..38 {
        body.push(CHARSET[(x % 32) as usize] as char);
        x = x.rotate_left(7).wrapping_add(0x2545_F491);
    }
    format!("{}1{}{}", hrp(network), kind, body)
}

fn is_lan(host: &str) -> bool {
    let h = host.to_ascii_lowercase();
    if let Ok(ip) = h.parse::<std::net::Ipv4Addr>() {
        let [a, b, ..] = ip.octets();
        return ip.is_loopback() || ip.is_private() || ip.is_link_local() || (a == 100 && (64..128).contains(&b));
    }
    h == "localhost" || [".local", ".lan", ".home.arpa", ".internal"].iter().any(|s| h.ends_with(s))
}

fn host_of(url: &str) -> String {
    let rest = url.split_once("://").map_or(url, |(_, r)| r);
    let hostport = rest.split('/').next().unwrap_or("");
    hostport.rsplit_once(':').map_or(hostport, |(h, _)| h).to_ascii_lowercase()
}

/// The node module's normalization, enough for the fixture: scheme and default port by kind.
fn normalize(kind: &str, url: &str) -> Result<String, String> {
    let u = url.trim();
    if u.is_empty() {
        return Err("a server needs an address".into());
    }
    let host = host_of(if u.contains("://") { u.to_string() } else { format!("x://{u}") }.as_str());
    if host.is_empty() || !host.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-') {
        return Err(format!("{u}: not a server address"));
    }
    if u.contains("://") {
        return Ok(u.to_string());
    }
    let plain = is_lan(&host) || host.ends_with(".onion");
    let has_port = u.contains(':');
    Ok(match (kind, plain) {
        ("electrum", true) => format!("tcp://{u}{}", if has_port { "" } else { ":50001" }),
        ("electrum", false) => format!("ssl://{u}{}", if has_port { "" } else { ":50002" }),
        (_, true) => format!("http://{u}"),
        (_, false) => format!("https://{u}"),
    })
}

fn site(host: &str) -> String {
    if is_lan(host) {
        return "you".into();
    }
    let labels: Vec<&str> = host.split('.').collect();
    if labels.len() <= 2 { host.to_string() } else { labels[labels.len() - 2..].join(".") }
}

fn defaults() -> Vec<Source> {
    let s = |id: &str, kind: &str, url: &str, op: &str, label: &str, on: bool| Source {
        id: id.into(), kind: kind.into(), url: url.into(), operator: op.into(), label: label.into(),
        enabled: on, history: false, tor: true, suspect: false,
    };
    vec![
        s("kyoto", "kyoto", "p2p://peer-list", "peers", "Kyoto peers", false),
        s("electrum.example", "electrum", "ssl://electrum.example:50002", "example", "Example Electrum", true),
        s("esplora.example", "esplora", "https://esplora.example/api", "example", "Example Esplora", true),
    ]
}

impl Sim {
    pub fn new(regtest: bool, now: Instant) -> Self {
        let mut sim = Sim {
            regtest,
            active: "mainnet".into(),
            state: WState::NoWallet,
            since: now,
            network: String::new(),
            family: String::new(),
            group: String::new(),
            label: None,
            handle: None,
            approve_at: None,
            open_job: None,
            close_job: None,
            opens: 0,
            jobs: BTreeMap::new(),
            next_job: 0,
            sends: BTreeMap::new(),
            next_send: 0,
            next_tx: 0,
            sources: BTreeMap::new(),
            proxy: "socks5h://127.0.0.1:9050".into(),
            wallets: vec![],
            receive_index: 0,
            history: vec![],
            confirmed: 0,
            change: 0,
            alert_at: None,
            alerted: false,
            last_status: String::new(),
            last_balance: String::new(),
        };
        for n in ["mainnet", "testnet4", "signet", "regtest"] {
            sim.sources.insert(n.into(), defaults());
        }
        sim
    }

    pub fn active(&self) -> String {
        self.active.clone()
    }

    pub fn networks(&self) -> Vec<&'static str> {
        let mut out = vec!["mainnet", "testnet4", "signet"];
        if self.regtest {
            out.push("regtest");
        }
        out
    }

    fn open(&self) -> bool {
        matches!(self.state, WState::Syncing | WState::Ready)
    }

    fn locked(&self) -> bool {
        self.state != WState::NoWallet
    }

    fn net(&self) -> String {
        if self.locked() && !self.network.is_empty() { self.network.clone() } else { self.active.clone() }
    }

    fn txid(&mut self) -> String {
        self.next_tx += 1;
        format!("{:016x}", 0xb17c_0000_0000_0000u64 + self.next_tx).repeat(4)
    }

    fn job(&mut self, kind: &str, now: Instant, send: Option<String>) -> String {
        self.next_job += 1;
        let id = format!("j{}", self.next_job);
        self.jobs.insert(id.clone(), Job { kind: kind.into(), state: "running".into(), error: None, result: Value::Null, at: now, send });
        id
    }

    fn finish(&mut self, id: &str, state: &str, error: Option<String>, result: Value, out: &mut Vec<Event>) {
        if let Some(j) = self.jobs.get_mut(id) {
            j.state = state.into();
            j.error = error;
            j.result = result;
            out.push(Event::JobFinished(id.into(), state.into()));
        }
    }

    // ---- reads ---------------------------------------------------------------------------------

    fn peers(&self) -> u64 {
        self.sources.get(&self.net()).map_or(0, |l| l.iter().filter(|s| s.enabled && s.kind == "electrum" && !s.suspect).count() as u64)
    }

    fn wallet_tip(&self, now: Instant) -> Option<u64> {
        match self.state {
            WState::Ready => Some(tip(&self.network)),
            WState::Syncing => {
                let (b, t) = (birthday(&self.network), tip(&self.network));
                let f = (now.saturating_duration_since(self.since).as_secs_f64() / SYNC_TIME.as_secs_f64()).min(1.0);
                Some(b + ((t - b) as f64 * f) as u64)
            }
            _ => None,
        }
    }

    pub fn status(&self, now: Instant) -> Value {
        let open = self.open();
        let authority = if open {
            json!({"kind": "electrum_headers", "height": tip(&self.network), "hash": "00000000000000000002f1c4fixture",
                   "tipAgeSecs": TIP_AGE_SECS, "peers": self.peers()})
        } else {
            json!({"kind": null, "height": null, "hash": null, "tipAgeSecs": null, "peers": 0})
        };
        let mut v = json!({
            "ok": true, "state": self.state.name(), "network": if self.locked() { json!(self.network) } else { Value::Null },
            "group": if self.group.is_empty() { Value::Null } else { json!(self.group) },
            "family": if self.family.is_empty() { Value::Null } else { json!(self.family) },
            "openHandle": self.handle, "approvalHandle": null, "needsBirthday": false,
            "birthday": if open { json!(birthday(&self.network)) } else { Value::Null },
            "birthdaySource": if open { json!("keystore") } else { Value::Null },
            "lastError": null, "synced": self.state == WState::Ready, "busy": false, "authority": authority,
            "activeNetwork": self.active, "label": self.label, "openSend": self.open_send(),
        });
        if let Some(t) = self.wallet_tip(now) {
            v["walletTip"] = json!(t);
            let (b, h) = (birthday(&self.network), tip(&self.network));
            v["syncPercent"] = json!(if t >= h { 100 } else { (t - b) * 100 / (h - b) });
            v["historyServer"] = json!("electrum.example");
        }
        v
    }

    fn open_send(&self) -> Option<String> {
        self.sends.values().find(|s| matches!(s.state.as_str(), "preparing" | "awaiting_approval" | "committing")).map(|s| s.id.clone())
    }

    pub fn balances(&self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let b = |s: u64| json!(s.to_string());
        json!({
            "ok": true, "busy": false, "confirmed": b(self.confirmed), "waiting": b(50_000), "pending": b(30_000),
            "sent": b(self.change), "immature": b(0), "tooSmall": {"count": 2, "sat": "540", "btc": btc_of(540)},
            "confirmedBtc": btc_of(self.confirmed), "waitingBtc": btc_of(50_000), "pendingBtc": btc_of(30_000),
            "sentBtc": btc_of(self.change), "immatureBtc": btc_of(0),
        })
    }

    pub fn history(&self, page: i64) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let start = (page.max(0) as usize) * 50;
        let rows: Vec<Value> = self.history.iter().skip(start).take(50).cloned().collect();
        json!({"ok": true, "page": page.max(0), "pageSize": 50, "total": self.history.len(), "rows": rows})
    }

    pub fn fee_rates(&self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        json!({"ok": true, "fast": 12.0, "normal": 6.0, "slow": 2.0, "minimum": 1.0, "sources": ["esplora.example"]})
    }

    pub fn receive_address(&mut self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let i = self.receive_index;
        self.receive_index += 1;
        json!({"ok": true, "address": address(&self.network, 'q', 1000 + i as u64), "index": i})
    }

    pub fn address_valid(&self, text: &str) -> Value {
        let t = text.trim();
        let (addr, amount) = match t.get(..8) {
            Some(p) if p.eq_ignore_ascii_case("bitcoin:") => {
                let rest = &t[8..];
                let (a, q) = rest.split_once('?').unwrap_or((rest, ""));
                let amt = q.split('&').find_map(|kv| kv.strip_prefix("amount=")).map(parse_btc);
                (a.to_string(), amt)
            }
            _ => (t.to_string(), None),
        };
        let net = self.net();
        let lower = addr.to_ascii_lowercase();
        let want = format!("{}1", hrp(&net));
        let charset_ok = lower.len() > want.len() + 1 && lower[want.len()..].chars().all(|c| "qpzry9x8gf2tvdw0s3jn54khce6mua7l".contains(c));
        if !lower.starts_with(&want) || (net != "regtest" && lower.starts_with("bcrt1")) {
            let other = ["bc1", "tb1", "bcrt1"].iter().any(|p| lower.starts_with(p));
            let reason = if other { "this address is for another network" } else { "not a Bitcoin address" };
            return json!({"ok": true, "valid": false, "address": addr, "reason": reason});
        }
        if !charset_ok || lower.len() < 14 || lower.len() > 90 {
            return json!({"ok": true, "valid": false, "address": addr, "reason": "not a Bitcoin address"});
        }
        let kind = match lower.as_bytes()[want.len()] {
            b'p' => "p2tr",
            _ if lower.len() > want.len() + 45 => "p2wsh",
            _ => "p2wpkh",
        };
        let mut v = json!({"ok": true, "valid": true, "address": lower, "type": kind});
        match amount {
            Some(Ok(sat)) => v["amountSat"] = json!(sat.to_string()),
            Some(Err(e)) => return json!({"ok": true, "valid": false, "address": addr, "reason": e}),
            None => {}
        }
        v
    }

    fn source_json(&self, s: &Source) -> Value {
        let lan = is_lan(&host_of(&s.url)) && s.kind != "kyoto";
        let onion = host_of(&s.url).ends_with(".onion");
        let route = if lan { "direct" } else if onion { "onion" } else if s.tor { "tor" } else { "direct" };
        json!({"id": s.id, "kind": s.kind, "url": s.url, "operator": s.operator, "label": s.label, "use": s.enabled,
               "history": s.history, "tor": s.tor, "lan": lan, "hasCredentials": false, "route": route, "suspect": s.suspect})
    }

    pub fn sources(&self) -> Value {
        let net = self.net();
        let list: Vec<Value> = self.sources.get(&net).map(|l| l.iter().map(|s| self.source_json(s)).collect()).unwrap_or_default();
        let named = |v: &Value| json!({"id": v["id"], "url": v["url"], "operator": v["operator"], "lan": v["lan"]});
        let exposes: Vec<Value> = list.iter().filter(|v| v["use"] == true && v["history"] == true && (v["kind"] == "electrum" || v["kind"] == "esplora")).map(named).collect();
        let without: Vec<Value> = list.iter().filter(|v| v["use"] == true && v["route"] == "direct" && v["lan"] != true).map(named).collect();
        let ops: std::collections::BTreeSet<String> = list.iter().filter(|v| v["use"] == true && v["kind"] != "kyoto").filter_map(|v| v["operator"].as_str().map(str::to_lowercase)).collect();
        json!({"ok": true, "network": net, "configured": true, "walletOpen": self.locked(), "proxy": self.proxy,
               "sources": list, "exposes": exposes, "withoutTor": without, "crossCheck": ops.len() >= 2})
    }

    pub fn source_health(&self, now_s: u64) -> Value {
        let net = self.net();
        let list = self.sources.get(&net).cloned().unwrap_or_default();
        let rows: Vec<Value> = list
            .iter()
            .map(|s| {
                let mut v = self.source_json(s);
                if s.kind == "kyoto" {
                    v["state"] = json!(if s.enabled { "no_peers" } else { "not_probed" });
                    v["error"] = json!(if s.enabled { "no peer to dial: the peer list is empty" } else { "" });
                    v["peers"] = json!("0");
                } else {
                    v["state"] = json!("ok");
                    v["tipHeight"] = json!(tip(&net).to_string());
                    v["rttMs"] = json!(if is_lan(&host_of(&s.url)) { "12" } else { "480" });
                    v["checkedAt"] = json!(now_s.to_string());
                }
                v
            })
            .collect();
        let suspect = list.iter().any(|s| s.enabled && s.suspect);
        let mut out = json!({"ok": true, "network": net, "configured": true, "overall": if suspect { "degraded" } else { "ok" },
                             "pending": false, "sources": rows});
        if self.open() {
            let wallet: Vec<Value> = list
                .iter()
                .filter(|s| s.enabled && s.kind != "kyoto")
                .map(|s| json!({"id": s.id, "url": s.url, "operator": s.operator, "kind": s.kind,
                                "state": if s.suspect { "suspect" } else { "ok" }, "suspect": s.suspect,
                                "history": s.id == "electrum.example"}))
                .collect();
            out["wallet"] = json!({"ok": true, "proxy": self.proxy, "crossCheck": false, "sources": wallet});
        }
        out
    }

    pub fn exposure(&self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let since = now_secs().saturating_sub(3600);
        json!({"ok": true, "servers": [{"source": "electrum.example", "url": "ssl://electrum.example:50002", "operator": "example",
                                         "role": "history", "since": since, "last": now_secs()}]})
    }

    pub fn descriptors(&self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        json!({"ok": true, "group": self.group,
               "external": "wpkh([73c5da0a/84'/1'/0']tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M/0/*)#fixture0",
               "internal": "wpkh([73c5da0a/84'/1'/0']tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M/1/*)#fixture1"})
    }

    pub fn list_wallets(&self) -> Value {
        let w: Vec<Value> = self.wallets.iter().filter(|w| w["network"] == self.active).cloned().collect();
        json!({"ok": true, "active": self.active, "wallets": w})
    }

    pub fn job_status(&self, id: &str) -> Value {
        match self.jobs.get(id.trim()) {
            Some(j) => json!({"ok": true, "jobId": id.trim(), "kind": j.kind, "state": j.state, "result": j.result, "error": j.error}),
            None => json!({"ok": false, "error": "unknown job"}),
        }
    }

    pub fn send_status(&self, id: &str) -> Value {
        let Some(s) = id.trim().strip_prefix('s').and_then(|n| n.parse::<u64>().ok()).and_then(|n| self.sends.get(&n)) else {
            return json!({"ok": false, "error": "unknown send"});
        };
        let summary = if s.state == "preparing" { Value::Null } else { self.summary(s) };
        let mut v = json!({
            "ok": true, "requestId": s.id, "kind": s.kind, "state": s.state, "requester": s.requester, "network": self.network,
            "group": self.group, "summary": summary, "approvalHandle": s.handle, "approval": s.approval,
            "txid": if s.state == "preparing" { Value::Null } else { json!(s.txid) }, "broadcast": s.broadcast, "via": s.via,
            "error": s.error, "errorCode": s.code, "cancelling": s.cancelling, "createdAt": s.created, "updatedAt": s.updated,
        });
        if s.state == "unknown" {
            v["abandoned"] = json!(s.abandoned);
            v["offer"] = if s.abandoned { json!([]) } else { json!(["rebroadcast", "request_fee_bump", "abandon_send"]) };
        }
        v
    }

    fn summary(&self, s: &Send) -> Value {
        let change = s.input.saturating_sub(s.amount + s.fee);
        let mut warnings = vec![];
        if s.small_change {
            warnings.push(json!({"kind": "change_too_small", "amountSat": change.to_string(), "costToSpendSat": "408",
                                 "message": "The change is worth less than it costs to spend at this fee rate; it can be added to the fee instead."}));
        }
        let change_rows: Vec<Value> = if change > 0 {
            vec![json!({"address": address(&self.network, 'q', 7), "amountSat": change.to_string(), "amountBtc": btc_of(change)})]
        } else {
            vec![]
        };
        json!({
            "kind": s.kind, "recipients": [{"address": s.recipient, "amountSat": s.amount.to_string(), "amountBtc": btc_of(s.amount)}],
            "change": change_rows, "inputs": 1, "inputSat": s.input.to_string(), "inputBtc": btc_of(s.input),
            "feeSat": s.fee.to_string(), "feeBtc": btc_of(s.fee), "feeRate": s.fee_rate, "vsize": VSIZE,
            "totalSat": (s.amount + s.fee).to_string(), "totalBtc": btc_of(s.amount + s.fee), "txid": s.txid,
            "replaces": s.replaces, "warnings": warnings,
        })
    }

    pub fn list_sends(&self) -> Value {
        let rows: Vec<Value> = self
            .sends
            .values()
            .rev()
            .map(|s| json!({"requestId": s.id, "kind": s.kind, "state": s.state, "requester": s.requester, "approvalHandle": s.handle,
                            "txid": s.txid, "errorCode": s.code, "createdAt": s.created, "updatedAt": s.updated}))
            .collect();
        json!({"ok": true, "sends": rows})
    }

    // ---- writes ---------------------------------------------------------------------------------

    pub fn set_active_network(&mut self, network: &str) -> Value {
        if !self.networks().contains(&network) {
            return json!({"ok": false, "error": format!("unknown network {network}")});
        }
        if self.locked() {
            return json!({"ok": false, "error": "close the open wallet before switching networks"});
        }
        self.active = network.into();
        json!({"ok": true, "active": network})
    }

    /// The first open of a run is never approved, so the app's Cancel has something to withdraw.
    pub fn open_wallet(&mut self, params: &str, now: Instant, out: &mut Vec<Event>) -> Value {
        let p: Value = match serde_json::from_str(params) {
            Ok(v) => v,
            Err(e) => return json!({"ok": false, "error": format!("open_wallet: {e}")}),
        };
        if self.locked() {
            return json!({"ok": false, "error": "a wallet is already open; close it first"});
        }
        let group = p["group"].as_str().map(String::from);
        let family = p["family"].as_str().map(String::from).or_else(|| {
            group.as_ref().and_then(|g| self.wallets.iter().find(|w| w["group"] == g.as_str())).and_then(|w| w["family"].as_str().map(String::from))
        });
        let Some(family) = family.filter(|f| f == "bitcoin" || f == "bitcoin_taproot") else {
            return json!({"ok": false, "error": "name a group to reopen, or a family to pick, create or restore one"});
        };
        self.opens += 1;
        self.state = WState::AwaitingOpen;
        self.since = now;
        self.network = self.active.clone();
        self.family = family;
        self.group = group.unwrap_or_default();
        self.label = p["label"].as_str().map(String::from);
        self.handle = Some(format!("sma_fixture{}", self.opens));
        self.approve_at = (self.opens > 1).then(|| now + OPEN_APPROVE);
        let j = self.job("open_wallet", now, None);
        self.open_job = Some(j.clone());
        out.push(Event::WalletState(self.status(now)));
        json!({"ok": true, "jobId": j})
    }

    pub fn close_wallet(&mut self, now: Instant, out: &mut Vec<Event>) -> Value {
        if let Some(s) = self.sends.values().find(|s| s.state == "committing") {
            return json!({"ok": false, "error": format!("send {} is going out; close the wallet once it settles", s.id)});
        }
        let j = self.job("close_wallet", now, None);
        if self.state == WState::AwaitingOpen || self.state == WState::Opening {
            // Withdraws the open still waiting in the keys app.
            if let Some(o) = self.open_job.take() {
                self.finish(&o, "failed", Some("cancelled".into()), Value::Null, out);
            }
            self.reset();
            self.finish(&j, "done", None, json!({"closed": false}), out);
            out.push(Event::WalletState(self.status(now)));
        } else if self.locked() {
            for s in self.sends.values_mut() {
                if matches!(s.state.as_str(), "preparing" | "awaiting_approval") {
                    s.state = "failed".into();
                    s.code = Some("no_wallet".into());
                    s.error = Some("the wallet closed before the send was approved".into());
                    out.push(Event::SendStatus(s.id.clone(), s.state.clone()));
                }
            }
            self.state = WState::Closing;
            self.since = now;
            self.close_job = Some(j.clone());
            out.push(Event::WalletState(self.status(now)));
        } else {
            self.finish(&j, "done", None, json!({"closed": false}), out);
        }
        json!({"ok": true, "jobId": j})
    }

    fn reset(&mut self) {
        self.state = WState::NoWallet;
        self.handle = None;
        self.approve_at = None;
        self.group.clear();
        self.family.clear();
        self.label = None;
        self.network.clear();
    }

    fn seed_wallet(&mut self) {
        let net = self.network.clone();
        self.confirmed = 125_000_000;
        self.change = 0;
        self.receive_index = 0;
        let t = tip(&net);
        let now = now_secs();
        let own = address(&net, 'q', 1001);
        let them = address(&net, 'q', 77);
        let mut txids = vec![];
        for _ in 0..6 {
            txids.push(self.txid());
        }
        let row = |txid: &str, intent: &str, amount: u64, fee: Option<u64>, state: &str, height: Option<u64>, extra: Value| {
            let mut r = json!({"txid": txid, "intent": intent, "amountSat": amount.to_string(), "feeSat": fee.map(|f| f.to_string()),
                               "coins": null, "counterparties": [], "height": height,
                               "confirmations": height.map_or(0, |h| t.saturating_sub(h) + 1), "time": now - 600 * (1 + height.map_or(0, |h| t - h.min(t))),
                               "state": state, "replaces": null, "replacedBy": null, "reportedBy": null,
                               "amountBtc": btc_of(amount), "feeBtc": fee.map_or(String::new(), btc_of)});
            if let Value::Object(m) = extra {
                for (k, v) in m {
                    r[k] = v;
                }
            }
            r
        };
        self.history = vec![
            row(&txids[0], "receive", 30_000, None, "pending", None, json!({"reportedBy": "electrum.example"})),
            row(&txids[1], "receive", 50_000, None, "waiting", Some(t + 1), json!({})),
            row(&txids[2], "self", 1_000_000, Some(141), "confirmed", Some(t - 3), json!({"counterparties": [own]})),
            row(&txids[3], "combine", 2_400_000, Some(312), "confirmed", Some(t - 20), json!({"coins": 3})),
            row(&txids[4], "send", 200_000, Some(220), "confirmed", Some(t - 40), json!({"counterparties": [them]})),
            row(&txids[5], "receive", 125_000_000, None, "confirmed", Some(t - 100), json!({})),
        ];
    }

    pub fn request(&mut self, kind: &str, requester: &str, params: &str, now: Instant, out: &mut Vec<Event>) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        if let Some(open) = self.open_send() {
            return json!({"ok": false, "error": format!("send {open} is still open: one send at a time per wallet")});
        }
        let p: Value = match serde_json::from_str(params) {
            Ok(v) => v,
            Err(e) => return json!({"ok": false, "error": format!("{kind}: {e}")}),
        };
        let rate = p["feeRate"].as_f64().filter(|r| *r > 0.0).unwrap_or(6.0);
        let fee = (rate * VSIZE as f64).ceil() as u64;
        let (recipient, amount, replaces) = if kind == "fee_bump" {
            let txid = p["txid"].as_str().unwrap_or_default().to_ascii_lowercase();
            let Some(row) = self.history.iter().find(|r| r["txid"] == txid.as_str() && r["state"] == "sent") else {
                return json!({"ok": false, "error": "no unconfirmed send of this wallet has that txid"});
            };
            let amount = row["amountSat"].as_str().and_then(|a| a.parse().ok()).unwrap_or(0);
            let to = row["counterparties"][0].as_str().unwrap_or_default().to_string();
            (to, amount, Some(txid))
        } else {
            let r = &p["recipients"][0];
            let to = r["address"].as_str().unwrap_or_default().to_string();
            let check = self.address_valid(&to);
            if check["valid"] != true {
                return json!({"ok": false, "error": format!("recipient 1: {}", check["reason"].as_str().unwrap_or("not a valid address"))});
            }
            let amount = if p["sendMax"] == true {
                COIN_SAT - fee
            } else {
                match (r["amountSat"].as_str(), r["amountBtc"].as_str(), check["amountSat"].as_str()) {
                    (Some(s), _, _) => match parse_sat(s) {
                        Ok(v) if v > 0 => v,
                        _ => return json!({"ok": false, "error": "an amount must be above zero"}),
                    },
                    (None, Some(b), _) => match parse_btc(b) {
                        Ok(v) if v > 0 => v,
                        Ok(_) => return json!({"ok": false, "error": "an amount must be above zero"}),
                        Err(e) => return json!({"ok": false, "error": e}),
                    },
                    (None, None, Some(u)) => parse_sat(u).unwrap_or(0),
                    _ => return json!({"ok": false, "error": "every recipient needs an amount"}),
                }
            };
            (check["address"].as_str().unwrap_or_default().to_string(), amount, None)
        };
        if amount + fee > self.confirmed {
            return json!({"ok": false, "error": "insufficient funds: not enough confirmed coins for this and its fee"});
        }
        let fate = match amount {
            REJECTED_SAT => Fate::Reject,
            EXPIRED_SAT => Fate::Expire,
            UNKNOWN_SAT => Fate::Unknown,
            _ => Fate::Approve,
        };
        let small_change = amount == SMALL_CHANGE_SAT;
        let input = if small_change { amount + fee + 400 } else if p["sendMax"] == true { COIN_SAT } else { COIN_SAT.max(amount + fee) };
        self.next_send += 1;
        let id = format!("s{}", self.next_send);
        // Named by what it pays, so a doctest can address its row whatever came before it.
        let txid = if kind == "fee_bump" {
            format!("{:016x}", 0xfeeb_0000_0000_0000u64 + fee).repeat(4)
        } else {
            format!("{:016x}", 0x5e4d_0000_0000_0000u64 + amount).repeat(4)
        };
        let t = now_secs();
        self.sends.insert(self.next_send, Send {
            id: id.clone(), kind: kind.into(), requester: requester.into(), state: "preparing".into(), error: None, code: None,
            fate, stage_at: now, amount, fee, fee_rate: rate, input, recipient, txid, replaces, approval: None, handle: None,
            broadcast: None, via: None, cancelling: false, abandoned: false, small_change, created: t, updated: t,
        });
        out.push(Event::SendStatus(id.clone(), "preparing".into()));
        json!({"ok": true, "requestId": id})
    }

    pub fn cancel_send(&mut self, id: &str, now: Instant, out: &mut Vec<Event>) -> Value {
        let Some(s) = id.trim().strip_prefix('s').and_then(|n| n.parse::<u64>().ok()).and_then(|n| self.sends.get_mut(&n)) else {
            return json!({"ok": false, "error": "unknown send"});
        };
        match s.state.as_str() {
            "preparing" | "awaiting_approval" => {
                s.cancelling = true;
                s.stage_at = now;
                out.push(Event::SendStatus(s.id.clone(), s.state.clone()));
                json!({"ok": true, "requestId": s.id, "state": s.state, "cancelling": true})
            }
            "committing" => json!({"ok": false, "error": "too late: the transaction is going out"}),
            st => json!({"ok": false, "error": format!("send is already {st}")}),
        }
    }

    pub fn rebroadcast(&mut self, arg: &str, now: Instant) -> Value {
        let id = arg.trim().to_string();
        let Some(s) = self.sends.values().rev().find(|s| s.id == id || s.txid == id) else {
            return json!({"ok": false, "error": "unknown send"});
        };
        if s.state != "unknown" && s.state != "sent" {
            return json!({"ok": false, "error": format!("send is {}: nothing went out to rebroadcast", s.state)});
        }
        let (sid, txid) = (s.id.clone(), s.txid.clone());
        let j = self.job("rebroadcast", now, Some(sid));
        json!({"ok": true, "jobId": j, "txid": txid})
    }

    pub fn abandon_send(&mut self, params: &str, now: Instant) -> Value {
        let txid = serde_json::from_str::<Value>(params).ok().and_then(|v| v["txid"].as_str().map(str::to_ascii_lowercase)).unwrap_or_default();
        let Some(s) = self.sends.values().rev().find(|s| s.txid == txid) else {
            return json!({"ok": false, "error": "no send of this wallet has that txid"});
        };
        if s.state != "unknown" {
            return json!({"ok": false, "error": format!("send {} is {}: only a send whose outcome is unknown can be abandoned", s.id, s.state)});
        }
        if s.abandoned {
            return json!({"ok": false, "error": format!("send {} was abandoned already", s.id)});
        }
        let sid = s.id.clone();
        let j = self.job("abandon_send", now, Some(sid.clone()));
        json!({"ok": true, "jobId": j, "requestId": sid, "txid": txid, "note": ABANDONED})
    }

    pub fn set_sources(&mut self, list: &str) -> Value {
        if self.locked() {
            return json!({"ok": false, "error": LOCKED});
        }
        let items: Vec<Value> = match serde_json::from_str(list) {
            Ok(v) => v,
            Err(e) => return json!({"ok": false, "error": format!("source list: {e}")}),
        };
        let mut out: Vec<Source> = vec![];
        let current = self.sources.get(&self.active).cloned().unwrap_or_default();
        for it in items {
            let id = it["id"].as_str().unwrap_or_default().to_string();
            let kind = it["kind"].as_str().unwrap_or_default().to_string();
            if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || "-._".contains(c)) {
                return json!({"ok": false, "error": format!("bad source id {id:?}")});
            }
            if out.iter().any(|s| s.id == id) {
                return json!({"ok": false, "error": format!("duplicate source id {id}")});
            }
            let url = if kind == "kyoto" { "p2p://peer-list".to_string() } else {
                match normalize(&kind, it["url"].as_str().unwrap_or_default()) {
                    Ok(u) => u,
                    Err(e) => return json!({"ok": false, "error": format!("{id}: {e}")}),
                }
            };
            let host = host_of(&url);
            let given = |k: &str| it[k].as_str().map(str::trim).filter(|t| !t.is_empty()).map(String::from);
            let suspect = current.iter().any(|c| c.id == id && c.suspect);
            out.push(Source {
                operator: given("operator").unwrap_or_else(|| if kind == "kyoto" { "peers".into() } else { site(&host) }),
                label: given("label").unwrap_or_else(|| host.clone()),
                enabled: it["use"].as_bool().unwrap_or(true),
                history: it["history"].as_bool().unwrap_or(false),
                tor: it["tor"].as_bool().unwrap_or(true),
                id, kind, url, suspect,
            });
        }
        self.sources.insert(self.active.clone(), out);
        self.sources()
    }

    pub fn set_source(&mut self, id: &str, changes: &str) -> Value {
        if self.locked() {
            return json!({"ok": false, "error": LOCKED});
        }
        let c: Value = match serde_json::from_str::<Value>(changes) {
            Ok(v) if v.is_object() => v,
            _ => return json!({"ok": false, "error": "changes must be a JSON object, such as {\"use\":true}"}),
        };
        let net = self.active.clone();
        let Some(s) = self.sources.get_mut(&net).and_then(|l| l.iter_mut().find(|s| s.id == id)) else {
            return json!({"ok": false, "error": format!("unknown source {id}")});
        };
        if c["tor"] == false && host_of(&s.url).ends_with(".onion") {
            return json!({"ok": false, "error": format!("{id}: an onion service is reached through Tor only")});
        }
        if let Some(v) = c["use"].as_bool() {
            s.enabled = v;
        }
        if let Some(v) = c["history"].as_bool() {
            s.history = v;
        }
        if let Some(v) = c["tor"].as_bool() {
            s.tor = v;
        }
        self.sources()
    }

    pub fn set_proxy(&mut self, proxy: &str) -> Value {
        if self.locked() {
            return json!({"ok": false, "error": LOCKED});
        }
        let p = proxy.trim();
        if !p.is_empty() && !p.starts_with("socks5h://") {
            return json!({"ok": false, "error": "the proxy is socks5h://host:port"});
        }
        self.proxy = p.into();
        json!({"ok": true, "proxy": self.proxy})
    }

    pub fn clear_suspect(&mut self, id: &str, now: Instant, out: &mut Vec<Event>) -> Value {
        let net = self.net();
        let cleared = self.sources.get_mut(&net).and_then(|l| l.iter_mut().find(|s| s.id == id)).map(|s| std::mem::replace(&mut s.suspect, false));
        match cleared {
            None => json!({"ok": false, "node": {"ok": false, "error": format!("unknown source {id}")}}),
            Some(had) => {
                if self.open() {
                    out.push(Event::WalletState(self.status(now)));
                }
                json!({"ok": true, "node": {"ok": true, "network": net, "sourceId": id, "cleared": had},
                       "wallet": {"ok": true, "cleared": had}})
            }
        }
    }

    // ---- the clock --------------------------------------------------------------------------------

    pub fn tick(&mut self, now: Instant) -> Vec<Event> {
        let mut out = vec![];
        let elapsed = now.saturating_duration_since(self.since);
        let state = self.state;
        match state {
            WState::AwaitingOpen if self.approve_at.is_some_and(|t| now >= t) => {
                self.state = WState::Opening;
                self.since = now;
                self.handle = None;
                self.approve_at = None;
            }
            WState::Opening if elapsed >= STEP => {
                if self.group.is_empty() {
                    self.group = format!("g_fixture{}", self.opens);
                }
                self.state = WState::Syncing;
                self.since = now;
                self.seed_wallet();
                let entry = json!({"group": self.group, "family": self.family, "network": self.network, "label": self.label,
                                   "birthday": birthday(&self.network), "firstOpened": now_secs(), "lastOpened": now_secs()});
                self.wallets.retain(|w| w["group"] != entry["group"]);
                self.wallets.insert(0, entry);
                if let Some(j) = self.open_job.take() {
                    let result = json!({"group": self.group, "family": self.family, "network": self.network, "created": self.opens == 2,
                                        "reset": false, "birthday": {"height": birthday(&self.network), "source": "keystore"}});
                    self.finish(&j, "done", None, result, &mut out);
                }
            }
            WState::Syncing if elapsed >= SYNC_TIME => {
                self.state = WState::Ready;
                self.since = now;
            }
            WState::Closing if elapsed >= STEP => {
                self.reset();
                self.alert_at = None;
                if let Some(j) = self.close_job.take() {
                    self.finish(&j, "done", None, json!({"closed": true}), &mut out);
                }
            }
            _ => {}
        }
        self.tick_sends(now, &mut out);
        self.tick_jobs(now, &mut out);
        if self.alert_at.is_some_and(|t| now >= t) && self.open() {
            self.alert_at = None;
            self.raise_alert(&mut out);
        }
        // Change events, as the backend sends them: on what the status says, and on amounts.
        let st = self.status(now);
        let digest = json!([st["state"], st["openHandle"], st["walletTip"], st["authority"]["peers"], st["openSend"]]).to_string();
        if digest != self.last_status {
            self.last_status = digest;
            out.push(Event::SyncProgress(json!({"state": st["state"], "network": st["network"], "walletTip": st["walletTip"],
                "authorityHeight": st["authority"]["height"], "tipAgeSecs": st["authority"]["tipAgeSecs"], "percent": st["syncPercent"],
                "synced": st["synced"]})));
            out.push(Event::WalletState(st));
        }
        let b = self.balances();
        let bd = b.to_string();
        if b["ok"] == true && bd != self.last_balance {
            self.last_balance = bd;
            out.push(Event::Balance(b));
        }
        out
    }

    fn raise_alert(&mut self, out: &mut Vec<Event>) {
        let net = self.net();
        if let Some(s) = self.sources.get_mut(&net).and_then(|l| l.iter_mut().find(|s| s.id == "electrum.example")) {
            s.suspect = true;
        }
        self.alerted = true;
        out.push(Event::SourceAlert(json!({"source": "electrum.example", "kind": "anchor_mismatch",
            "detail": format!("reported a payment confirmed in block {}, whose hash is not the wallet's chain's", tip(&net)),
            "at": now_secs(), "network": net, "group": self.group})));
    }

    fn tick_sends(&mut self, now: Instant, out: &mut Vec<Event>) {
        let mut sent_rows = vec![];
        for s in self.sends.values_mut() {
            let e = now.saturating_duration_since(s.stage_at);
            let before = s.state.clone();
            if s.cancelling && matches!(s.state.as_str(), "preparing" | "awaiting_approval") {
                if e >= Duration::from_millis(500) {
                    s.state = "cancelled".into();
                    s.code = Some("cancelled".into());
                    s.error = Some(format!("cancelled by {APP}"));
                    s.cancelling = false;
                }
            } else {
                let state = s.state.clone();
                match (state.as_str(), s.fate) {
                    ("preparing", _) if e >= STEP => {
                        s.state = "awaiting_approval".into();
                        s.approval = Some("offered".into());
                        s.handle = Some(format!("smh_fixture{}", &s.id[1..]));
                        s.stage_at = now;
                    }
                    ("awaiting_approval", Fate::Approve) if e >= Duration::from_secs(3) => {
                        s.state = "committing".into();
                        s.approval = Some("settled".into());
                        s.stage_at = now;
                    }
                    ("awaiting_approval", Fate::Approve) if e >= Duration::from_millis(1500) => {
                        s.approval = Some("rendered".into());
                    }
                    ("awaiting_approval", Fate::Reject) if e >= Duration::from_secs(2) => {
                        s.state = "failed".into();
                        s.code = Some("rejected".into());
                        s.error = Some(REJECTED.into());
                    }
                    ("awaiting_approval", Fate::Expire) if e >= Duration::from_secs(5) => {
                        s.state = "failed".into();
                        s.code = Some("expired".into());
                        s.error = Some(NO_ACK.into());
                    }
                    ("awaiting_approval", Fate::Unknown) if e >= Duration::from_secs(2) => {
                        s.state = "committing".into();
                        s.approval = Some("settled".into());
                        s.stage_at = now;
                    }
                    ("committing", Fate::Unknown) if e >= STEP => {
                        s.state = "unknown".into();
                        s.broadcast = Some("unknown".into());
                        s.via = Some("electrum.example".into());
                        s.error = Some(MAY_HAVE_LEFT.into());
                    }
                    ("committing", _) if e >= STEP => {
                        s.state = "sent".into();
                        s.broadcast = Some("seen".into());
                        s.via = Some("electrum.example".into());
                        sent_rows.push((s.txid.clone(), s.kind.clone(), s.amount, s.fee, s.input, s.recipient.clone(), s.replaces.clone()));
                    }
                    _ => {}
                }
            }
            if s.state != before {
                s.updated = now_secs();
                out.push(Event::SendStatus(s.id.clone(), s.state.clone()));
            }
        }
        for (txid, kind, amount, fee, input, recipient, replaces) in sent_rows {
            self.record_sent(&txid, &kind, amount, fee, input, &recipient, replaces.as_deref());
            if !self.alerted && self.alert_at.is_none() && kind == "send" {
                self.alert_at = Some(now + Duration::from_secs(2));
            }
        }
    }

    fn record_sent(&mut self, txid: &str, kind: &str, amount: u64, fee: u64, input: u64, recipient: &str, replaces: Option<&str>) {
        let mut row = json!({"txid": txid, "intent": if kind == "fee_bump" { "fee_bump" } else { "send" }, "amountSat": amount.to_string(),
                             "feeSat": fee.to_string(), "coins": null, "counterparties": [recipient], "height": null, "confirmations": 0,
                             "time": now_secs(), "state": "sent", "replaces": replaces, "replacedBy": null, "reportedBy": null,
                             "amountBtc": btc_of(amount), "feeBtc": btc_of(fee)});
        if let Some(old) = replaces {
            if let Some(r) = self.history.iter_mut().find(|r| r["txid"] == old) {
                r["state"] = json!("replaced");
                r["replacedBy"] = json!(txid);
            }
            row["replaces"] = json!(old);
        } else {
            self.confirmed = self.confirmed.saturating_sub(input);
            self.change += input.saturating_sub(amount + fee);
        }
        self.history.insert(0, row);
    }

    fn tick_jobs(&mut self, now: Instant, out: &mut Vec<Event>) {
        let due: Vec<String> = self
            .jobs
            .iter()
            .filter(|(_, j)| j.state == "running" && (j.kind == "rebroadcast" || j.kind == "abandon_send") && now.saturating_duration_since(j.at) >= STEP)
            .map(|(id, _)| id.clone())
            .collect();
        for id in due {
            let (kind, send) = {
                let j = &self.jobs[&id];
                (j.kind.clone(), j.send.clone().unwrap_or_default())
            };
            let n = send.strip_prefix('s').and_then(|n| n.parse::<u64>().ok()).unwrap_or(0);
            if kind == "abandon_send" {
                if let Some(s) = self.sends.get_mut(&n) {
                    s.abandoned = true;
                    s.updated = now_secs();
                }
                self.finish(&id, "done", None, json!({"abandoned": true}), out);
                out.push(Event::SendStatus(send, "unknown".into()));
            } else {
                let mut moved = false;
                if let Some(s) = self.sends.get_mut(&n).filter(|s| s.state == "unknown" && !s.abandoned) {
                    s.state = "sent".into();
                    s.broadcast = Some("seen".into());
                    s.updated = now_secs();
                    moved = true;
                }
                self.finish(&id, "done", None, json!({"broadcast": "seen", "via": "electrum.example"}), out);
                if moved {
                    out.push(Event::SendStatus(send, "sent".into()));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(sim: &mut Sim, from: Instant, secs: u64) -> Instant {
        let mut t = from;
        for _ in 0..(secs * 10) {
            t += Duration::from_millis(100);
            sim.tick(t);
        }
        t
    }

    fn opened(net: &str) -> (Sim, Instant) {
        let t0 = Instant::now();
        let mut sim = Sim::new(false, t0);
        sim.set_active_network(net);
        let mut ev = vec![];
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t0, &mut ev);
        assert_eq!(sim.status(t0)["openHandle"], "sma_fixture1");
        let t = run(&mut sim, t0, 10);
        assert_eq!(sim.status(t)["state"], "awaiting_open", "the first open waits for a cancel");
        sim.close_wallet(t, &mut ev);
        assert_eq!(sim.status(t)["state"], "no_wallet");
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t, &mut ev);
        let t = run(&mut sim, t, 10);
        assert_eq!(sim.status(t)["state"], "ready");
        (sim, t)
    }

    #[test]
    fn opens_on_the_second_try_and_reports_its_chain() {
        let (sim, t) = opened("signet");
        let st = sim.status(t);
        assert_eq!((st["walletTip"].clone(), st["authority"]["peers"].clone(), st["syncPercent"].clone()), (json!(290_123), json!(1), json!(100)));
        assert_eq!(sim.balances()["confirmed"], "125000000");
        assert_eq!(sim.list_wallets()["wallets"][0]["group"], "g_fixture2");
    }

    #[test]
    fn sends_settle_by_amount() {
        for (amount, end) in [(20_000u64, "failed"), (30_000, "failed"), (40_000, "unknown"), (60_000, "sent")] {
            let (mut sim, t) = opened("signet");
            let to = address("signet", 'q', 5);
            let mut ev = vec![];
            let r = sim.request("send", APP, &json!({"recipients": [{"address": to, "amountSat": amount.to_string()}], "feeRate": 6}).to_string(), t, &mut ev);
            let id = r["requestId"].as_str().unwrap().to_string();
            let t = run(&mut sim, t, 8);
            let st = sim.send_status(&id);
            assert_eq!(st["state"], end, "{amount}");
            if amount == 30_000 {
                assert_eq!(st["errorCode"], "expired");
            }
            if amount == 40_000 {
                assert_eq!(st["offer"], json!(["rebroadcast", "request_fee_bump", "abandon_send"]));
                let a = sim.abandon_send(&json!({"txid": st["txid"]}).to_string(), t);
                assert_eq!(a["note"], ABANDONED);
                run(&mut sim, t, 2);
                assert_eq!(sim.send_status(&id)["abandoned"], true);
            }
            if amount == 60_000 {
                assert_eq!(sim.history(0)["rows"][0]["state"], "sent");
                let t = run(&mut sim, t, 3);
                assert_eq!(sim.status(t)["authority"]["peers"], 0, "the history server turned suspect");
                sim.clear_suspect("electrum.example", t, &mut ev);
                assert_eq!(sim.status(t)["authority"]["peers"], 1);
            }
        }
    }

    #[test]
    fn a_fee_bump_replaces_the_send() {
        let (mut sim, t) = opened("signet");
        let mut ev = vec![];
        let to = address("signet", 'q', 5);
        sim.request("send", APP, &json!({"recipients": [{"address": to, "amountSat": "60000"}], "feeRate": 6}).to_string(), t, &mut ev);
        let t = run(&mut sim, t, 8);
        let txid = sim.history(0)["rows"][0]["txid"].as_str().unwrap().to_string();
        let r = sim.request("fee_bump", APP, &json!({"txid": txid, "feeRate": 12}).to_string(), t, &mut ev);
        let id = r["requestId"].as_str().unwrap().to_string();
        run(&mut sim, t, 8);
        assert_eq!(sim.send_status(&id)["state"], "sent");
        let rows = sim.history(0)["rows"].clone();
        assert_eq!((rows[0]["intent"].clone(), rows[0]["feeSat"].clone(), rows[1]["state"].clone()), (json!("fee_bump"), json!("1692"), json!("replaced")));
    }

    #[test]
    fn sources_lock_while_open_and_normalize_your_own() {
        let t0 = Instant::now();
        let mut sim = Sim::new(false, t0);
        let mut list = sim.sources()["sources"].as_array().unwrap().clone();
        list.push(json!({"id": "192.168.1.20", "kind": "electrum", "url": "192.168.1.20:50001", "label": "Home node", "use": true}));
        let r = sim.set_sources(&serde_json::to_string(&list).unwrap());
        let mine = r["sources"].as_array().unwrap().iter().find(|s| s["id"] == "192.168.1.20").unwrap().clone();
        assert_eq!((mine["url"].clone(), mine["operator"].clone(), mine["lan"].clone(), mine["route"].clone()),
                   (json!("tcp://192.168.1.20:50001"), json!("you"), json!(true), json!("direct")));
        assert_eq!(sim.set_source("electrum.example", r#"{"tor":false}"#)["withoutTor"][0]["id"], "electrum.example");
        let mut ev = vec![];
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t0, &mut ev);
        assert_eq!(sim.set_source("electrum.example", r#"{"use":false}"#)["error"], LOCKED);
    }

    #[test]
    fn addresses_check_their_network() {
        let sim = Sim::new(false, Instant::now());
        assert_eq!(sim.address_valid(&address("mainnet", 'q', 3))["type"], "p2wpkh");
        assert_eq!(sim.address_valid(&address("signet", 'q', 3))["reason"], "this address is for another network");
        let uri = format!("bitcoin:{}?amount=0.0015", address("mainnet", 'p', 3));
        let v = sim.address_valid(&uri);
        assert_eq!((v["type"].clone(), v["amountSat"].clone()), (json!("p2tr"), json!("150000")));
    }
}
