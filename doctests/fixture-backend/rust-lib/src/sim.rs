//! The scripted wallet behind the fixture: states move on a clock, a send's fate is its amount, and
//! the first send that goes out turns the history server suspect. A wallet opens without a birthday,
//! a reorg re-anchors one payment 5 s after the first open is ready, and Kyoto in use is the
//! authority and names a refused chain 3 s after it is. On signet under Kyoto, Esplora reports a
//! payment below the chain's start (signet's checkpoint): unchecked until a birthday below it is
//! set, whose rescan ends with one wider pass. On testnet4 Kyoto is on with one peer, which then
//! decides the chain. A signet wallet holds a coin past a 20-address gap limit: listed apart and
//! spendable, small sends spend it, and a gap limit of 30 or more takes it into the balance after
//! its rescan. Each open shows last session's chain for 4 s before its sources answer. Opens show the
//! first unused address and reveal none; testnet4's wallet already has 20 unused, so a new one is
//! refused there. Fee estimates: none on testnet4, a quiet 1 sat/vB under Kyoto on signet. No
//! network, no key.

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
const RESCAN_TIME: Duration = Duration::from_secs(4);
const REORG_AFTER: Duration = Duration::from_secs(5);
const AUTHORITY_ALERT_AFTER: Duration = Duration::from_secs(3);
const KYOTO_PEERS: u64 = 4;
/// A close settles this long, and a switch queued behind it applies this long after: room to ask
/// for a switch while it closes, and to open before the switch applies.
const CLOSE_TIME: Duration = Duration::from_secs(3);
const SWITCH_AFTER_CLOSE: Duration = Duration::from_secs(4);
const MAX_OWN_PEERS: usize = 64;
/// Esplora's report below signet's checkpoint, and when its alert fires after the wallet is ready.
const UNCHECKED_SAT: u64 = 60_000;
const UNCHECKED_HEIGHT: u64 = 289_950;
const UNCHECKED_ALERT_AFTER: Duration = Duration::from_secs(1);
/// The coin a 20-address gap limit misses on signet, and the limit that reaches it.
const BEYOND_GAP_SAT: u64 = 70_000;
const BEYOND_GAP_NEEDS: u64 = 30;
const GAP_LIMIT_DEFAULT: u64 = 20;
/// Until the first round of asking the chain's sources ends: no peers, the sources unasked.
const FIRST_ANSWER: Duration = Duration::from_secs(4);
/// testnet4's wallet was opened this often by an app that revealed an address at each open.
const OLD_APP_OPENS: u32 = 20;
/// The wallet's first payment, a fixed day so a birthday after it is refused the same way every run.
const FIRST_TX_DAY: &str = "2026-05-31";
// The core's own refusals.
const BIRTHDAY_FUTURE: &str = "the birthday is in the future";

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
    to_fee: u64,
    /// What it spends of the coin past the gap limit.
    beyond: u64,
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
    pin: Option<String>,
    user_added: bool,
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
    /// Receive addresses revealed, none of them paid, by network and group.
    revealed: BTreeMap<String, u32>,
    /// The open's first round of asking the chain's sources has ended, or ends then.
    asked: bool,
    answer_at: Option<Instant>,
    history: Vec<Value>,
    confirmed: u64,
    change: u64,
    alert_at: Option<Instant>,
    alerted: bool,
    birthday_height: u64,
    birthday_source: String,
    rescan_from: Option<u64>,
    rescan_until: Option<Instant>,
    reorg_at: Option<Instant>,
    reorged: bool,
    last_reorg: Value,
    authority_alert_at: Option<Instant>,
    authority_alerted: bool,
    pending_network: Option<String>,
    switch_at: Option<Instant>,
    own_peers: BTreeMap<String, Vec<String>>,
    /// The checkpoint the wallet's chain starts from, and a payment reported below it, unchecked.
    chain_base: u64,
    unchecked: bool,
    unchecked_alert_at: Option<Instant>,
    /// Kyoto's wider passes, whether the running rescan is one, and its last filter-header conflict.
    rescans: u32,
    window_rescan: bool,
    conflict_at: Option<u64>,
    /// The open wallet's gap limit, and whether its signet coin lies past it.
    gap_limit: u64,
    beyond_gap: bool,
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

/// The highest checkpoint a wallet's chain may start from, as the core's are.
fn checkpoint(network: &str) -> u64 {
    match network {
        "mainnet" => 935_424,
        "testnet4" => 120_000,
        "signet" => 290_000,
        _ => 0,
    }
}

/// Kyoto's quorum: 3 on mainnet, 2 on signet, and testnet4's one curated peer.
fn quorum(network: &str) -> u64 {
    match network {
        "mainnet" => 3,
        "testnet4" => 1,
        _ => 2,
    }
}

fn beyond_gap_txid() -> String {
    format!("{:016x}", 0x0bea_0000_0000_0000u64 + BEYOND_GAP_SAT).repeat(4)
}

/// `{ gapLimit }` as the core takes it: a whole number from 20 to 1000.
fn gap_limit_of(v: &Value) -> Option<u64> {
    v.as_u64().filter(|g| (20..=1000).contains(g))
}

fn unchecked_txid() -> String {
    format!("{:016x}", 0x0dd0_0000_0000_0000u64 + UNCHECKED_HEIGHT).repeat(4)
}

/// A block hash for a height: fake, and plain about it.
fn block_hash(height: u64) -> String {
    format!("{:064x}", 0xb10c_0000_0000u64 + height)
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

/// Days since 1970-01-01 of a YYYY-MM-DD day (Hinnant's days_from_civil), or None.
fn day_number(day: &str) -> Option<i64> {
    let p: Vec<&str> = day.split('-').collect();
    let [y, m, d] = p.as_slice() else { return None };
    if y.len() != 4 || m.len() != 2 || d.len() != 2 {
        return None;
    }
    let (y, m, d): (i64, i64, i64) = (y.parse().ok()?, m.parse().ok()?, d.parse().ok()?);
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * ((m + 9) % 12) + 2) / 5 + d - 1;
    Some(era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468)
}

/// Where a wallet's kind of address began: the scan floor without a birthday.
fn activation(network: &str, family: &str) -> u64 {
    match (network, family) {
        ("mainnet", "bitcoin_taproot") => 709_632,
        ("mainnet", _) => 481_824,
        _ => 0,
    }
}

fn is_tls(url: &str) -> bool {
    url.starts_with("ssl://") || url.starts_with("https://")
}

/// A server's certificate as the node module's probe shows it: CA-signed for the example operator,
/// self-signed for a server of your own, trusted then only through its pin.
fn certificate(s: &Source) -> Option<Value> {
    if !is_tls(&s.url) {
        return None;
    }
    let host = host_of(&s.url);
    // FNV-1a over the host: the same fingerprint on every build, so a doctest can name it.
    let fnv = host.bytes().fold(0xcbf2_9ce4_8422_2325u64, |h, b| (h ^ b as u64).wrapping_mul(0x0100_0000_01b3));
    let sha = format!("{fnv:016x}").repeat(4);
    let ca = host.ends_with(".example");
    let trusted = s.pin.as_deref().map_or(ca, |p| p == sha);
    Some(json!({"certSha256": sha, "subject": format!("CN={host}"), "issuer": if ca { "CN=Example CA".to_string() } else { format!("CN={host}") },
                "notBefore": "2026-10-11T01:43:03Z", "notAfter": "2126-09-17T01:43:03Z", "trusted": trusted}))
}

/// A pin as the node module stores it: 64 hex digits, colons allowed, lowercase.
fn parse_pin(v: &Value) -> Result<Option<String>, String> {
    match v {
        Value::Null => Ok(None),
        Value::String(t) if t.trim().is_empty() => Ok(None),
        Value::String(t) => {
            let hex: String = t.trim().chars().filter(|c| *c != ':').collect::<String>().to_ascii_lowercase();
            if hex.len() == 64 && hex.chars().all(|c| c.is_ascii_hexdigit()) { Ok(Some(hex)) } else {
                Err("invalid parameters: certSha256 is 64 hex digits".into())
            }
        }
        _ => Err("invalid parameters: certSha256 is a string or null".into()),
    }
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
        enabled: on, history: false, tor: true, suspect: false, pin: None, user_added: false,
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
            revealed: BTreeMap::new(),
            asked: false,
            answer_at: None,
            history: vec![],
            confirmed: 0,
            change: 0,
            alert_at: None,
            alerted: false,
            birthday_height: 0,
            birthday_source: String::new(),
            rescan_from: None,
            rescan_until: None,
            reorg_at: None,
            reorged: false,
            last_reorg: Value::Null,
            authority_alert_at: None,
            authority_alerted: false,
            pending_network: None,
            switch_at: None,
            own_peers: BTreeMap::new(),
            chain_base: 0,
            unchecked: false,
            unchecked_alert_at: None,
            rescans: 0,
            window_rescan: false,
            conflict_at: None,
            gap_limit: GAP_LIMIT_DEFAULT,
            beyond_gap: false,
            last_status: String::new(),
            last_balance: String::new(),
        };
        for n in ["mainnet", "testnet4", "signet", "regtest"] {
            let mut list = defaults();
            // The node module's testnet4 list holds one peer, and Kyoto runs on it.
            if n == "testnet4" {
                list.iter_mut().filter(|s| s.kind == "kyoto").for_each(|s| s.enabled = true);
            }
            sim.sources.insert(n.into(), list);
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

    fn kyoto(&self) -> bool {
        self.sources.get(&self.net()).is_some_and(|l| l.iter().any(|s| s.enabled && s.kind == "kyoto"))
    }

    fn peers(&self) -> u64 {
        if self.kyoto() {
            return if quorum(&self.net()) == 1 { 1 } else { KYOTO_PEERS };
        }
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
        let kyoto = open && self.kyoto();
        let authority = if open {
            json!({"kind": if kyoto { "kyoto" } else { "electrum_headers" }, "height": tip(&self.network),
                   "hash": "00000000000000000002f1c4fixture", "tipAgeSecs": TIP_AGE_SECS, "peers": if self.asked { self.peers() } else { 0 },
                   "asked": self.asked, "base": self.chain_base})
        } else {
            json!({"kind": null, "height": null, "hash": null, "tipAgeSecs": null, "peers": 0})
        };
        let mut v = json!({
            "ok": true, "state": self.state.name(), "network": if self.locked() { json!(self.network) } else { Value::Null },
            "group": if self.group.is_empty() { Value::Null } else { json!(self.group) },
            "family": if self.family.is_empty() { Value::Null } else { json!(self.family) },
            "openHandle": self.handle, "approvalHandle": null, "needsBirthday": open && self.birthday_source == "activation",
            "birthday": if open { json!(self.birthday_height) } else { Value::Null },
            "birthdaySource": if open { json!(self.birthday_source) } else { Value::Null },
            "rescanFrom": if open { json!(self.rescan_from) } else { Value::Null },
            "lastReorg": if open { self.last_reorg.clone() } else { Value::Null },
            "kyoto": if kyoto { self.kyoto_status() } else { Value::Null },
            "node": null,
            "lastError": null, "synced": self.state == WState::Ready, "busy": false, "authority": authority,
            "activeNetwork": self.active, "label": self.label, "openSend": self.open_send(),
            "gapLimit": if open { json!(self.gap_limit) } else { Value::Null },
        });
        if let Some(t) = self.wallet_tip(now) {
            v["walletTip"] = json!(t);
            let (b, h) = (birthday(&self.network), tip(&self.network));
            v["syncPercent"] = json!(if t >= h { 100 } else { (t - b) * 100 / (h - b) });
            v["historyServer"] = json!("electrum.example");
        }
        // A rescan reports a share done only under Kyoto; a server's full scan has no height to count,
        // and the fixture's wider pass shows none either.
        if let (Some(_), Some(until)) = (self.rescan_from, self.rescan_until) {
            if kyoto && !self.window_rescan {
                let left = until.saturating_duration_since(now).as_secs_f64() / RESCAN_TIME.as_secs_f64();
                v["syncPercent"] = json!(((1.0 - left.min(1.0)) * 100.0).floor() as u64);
            } else if let Some(m) = v.as_object_mut() {
                m.remove("syncPercent");
            }
        }
        v
    }

    fn kyoto_status(&self) -> Value {
        let q = quorum(&self.network);
        let conflict = self.conflict_at.map(|at| json!({"at": at, "peers": [format!("peer3{}.onion:38333", "a".repeat(46))]}));
        json!({"running": true, "phase": "synced", "headers": tip(&self.network), "progress": 1.0, "connected": if self.asked { self.peers() } else { 0 },
               "quorum": q, "onePeerDecides": q == 1, "rescans": self.rescans, "window": [26, 25], "lastConflict": conflict})
    }

    fn open_send(&self) -> Option<String> {
        self.sends.values().find(|s| matches!(s.state.as_str(), "preparing" | "awaiting_approval" | "committing")).map(|s| s.id.clone())
    }

    pub fn balances(&self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let b = |s: u64| json!(s.to_string());
        let unchecked = if self.unchecked { UNCHECKED_SAT } else { 0 };
        let beyond = if self.beyond_gap { BEYOND_GAP_SAT } else { 0 };
        json!({
            "ok": true, "busy": false, "confirmed": b(self.confirmed), "waiting": b(50_000), "pending": b(30_000),
            "sent": b(self.change), "immature": b(0), "tooSmall": {"count": 2, "sat": "540", "btc": btc_of(540)},
            "unchecked": b(unchecked), "uncheckedBtc": btc_of(unchecked),
            "beyondGap": {"count": u64::from(beyond > 0), "sat": beyond.to_string(), "confirmedSat": beyond.to_string()},
            "beyondGapBtc": btc_of(beyond),
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

    /// Kyoto estimates nothing, so testnet4 has no estimate; under Kyoto on signet Esplora's is a
    /// quiet network's.
    pub fn fee_rates(&self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        if self.network == "testnet4" {
            return json!({"ok": false, "error": "no fee estimate yet"});
        }
        let (fast, normal, slow) = if self.kyoto() { (1.0, 1.0, 1.0) } else { (12.0, 6.0, 2.0) };
        json!({"ok": true, "fast": fast, "normal": normal, "slow": slow, "minimum": 1.0, "sources": ["esplora.example"], "estimated": true})
    }

    fn revealed_mut(&mut self) -> &mut u32 {
        let old = if self.network == "testnet4" { OLD_APP_OPENS } else { 0 };
        self.revealed.entry(format!("{}/{}", self.network, self.group)).or_insert(old)
    }

    /// A new address, unless as many unused ones as the gap limit stand: then the first, not fresh.
    pub fn receive_address(&mut self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let (net, gap) = (self.network.clone(), self.gap_limit as u32);
        let n = self.revealed_mut();
        if *n >= gap {
            return json!({"ok": true, "address": address(&net, 'q', 1000), "index": 0, "fresh": false, "unused": *n, "gapLimit": gap});
        }
        let i = *n;
        *n += 1;
        json!({"ok": true, "address": address(&net, 'q', 1000 + u64::from(i)), "index": i, "fresh": true, "unused": i + 1, "gapLimit": gap})
    }

    /// The first unused address, revealed only when none is; none of the fixture's is ever paid.
    pub fn current_address(&mut self) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let net = self.network.clone();
        let n = self.revealed_mut();
        *n = (*n).max(1);
        json!({"ok": true, "address": address(&net, 'q', 1000), "index": 0})
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
        let mut v = json!({"id": s.id, "kind": s.kind, "url": s.url, "operator": s.operator, "label": s.label, "use": s.enabled,
                           "history": s.history, "tor": s.tor, "lan": lan, "hasCredentials": false, "route": route, "suspect": s.suspect});
        if let Some(p) = &s.pin {
            v["certSha256"] = json!(p);
        }
        if s.user_added {
            v["userAdded"] = json!(true);
        }
        if s.kind != "kyoto" {
            v["encrypted"] = json!(is_tls(&s.url) || onion);
        }
        v
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
                    if let Some(c) = certificate(s) {
                        v["certificate"] = c;
                    }
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
                                "state": if s.suspect { "suspect" } else if self.asked { "ok" } else { "unknown" }, "suspect": s.suspect,
                                "history": s.id == "electrum.example", "encrypted": is_tls(&s.url)}))
                .collect();
            out["wallet"] = json!({"ok": true, "proxy": self.proxy, "crossCheck": false, "sources": wallet});
        }
        out
    }

    /// The node module's probe: the health of one source, or of every enabled server for "".
    pub fn probe(&self, params: &str) -> Value {
        let p: Value = match serde_json::from_str(params) {
            Ok(v) => v,
            Err(e) => return json!({"ok": false, "error": format!("probe: {e}")}),
        };
        let Some(source) = p["source"].as_str().map(str::trim) else {
            return json!({"ok": false, "error": "source is required: a source id, or \"\" for every enabled server"});
        };
        let mut h = self.source_health(now_secs());
        let rows: Vec<Value> = h["sources"].as_array().cloned().unwrap_or_default().into_iter()
            .filter(|r| if source.is_empty() { r["use"] == true && r["kind"] != "kyoto" } else { r["id"] == source })
            .collect();
        if rows.is_empty() && !source.is_empty() {
            return json!({"ok": false, "error": format!("unknown source {source}")});
        }
        h["answered"] = json!(rows.iter().map(|r| r["id"].clone()).collect::<Vec<_>>());
        h["sources"] = json!(rows);
        if let Some(m) = h.as_object_mut() {
            m.remove("wallet");
        }
        h
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
        if s.to_fee > 0 {
            warnings.push(json!({"kind": "change_to_fee", "amountSat": s.to_fee.to_string(), "costToSpendSat": "408",
                                 "message": "The change was worth less than it costs to spend at this fee rate, so it went to the fee."}));
        }
        if s.beyond > 0 {
            warnings.push(json!({"kind": "beyond_gap_inputs", "count": 1, "sat": s.beyond.to_string(),
                                 "message": "1 input was found beyond the wallet's gap limit"}));
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

    pub fn pending_network(&self) -> Option<String> {
        self.pending_network.clone()
    }

    /// The backend's plan: a send open refuses, a close settling queues, an open refuses as busy.
    pub fn set_active_network(&mut self, network: &str) -> Value {
        if !self.networks().contains(&network) {
            return json!({"ok": false, "error": format!("unknown network {network}")});
        }
        if network == self.active {
            self.pending_network = None;
            return json!({"ok": true, "active": network, "pending": null});
        }
        if let Some(s) = self.open_send() {
            return json!({"ok": false, "code": "send_open", "error": format!("send {s} is still open")});
        }
        match self.state {
            WState::Closing => {
                self.pending_network = Some(network.into());
                json!({"ok": true, "active": self.active, "pending": network})
            }
            WState::AwaitingOpen | WState::Opening => {
                json!({"ok": false, "code": "busy", "error": "a wallet is opening; close it, or wait, then switch"})
            }
            WState::Syncing | WState::Ready => {
                json!({"ok": false, "code": "wallet_open", "error": "close the open wallet before switching networks"})
            }
            WState::NoWallet if self.switch_at.is_some() => {
                self.pending_network = Some(network.into());
                json!({"ok": true, "active": self.active, "pending": network})
            }
            WState::NoWallet => {
                self.active = network.into();
                json!({"ok": true, "active": network, "pending": null})
            }
        }
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
        if let Some(n) = &self.pending_network {
            return json!({"ok": false, "code": "busy", "error": format!("switching to {n} once the wallet has closed; try again")});
        }
        let group = p["group"].as_str().map(String::from);
        let family = p["family"].as_str().map(String::from).or_else(|| {
            group.as_ref().and_then(|g| self.wallets.iter().find(|w| w["group"] == g.as_str())).and_then(|w| w["family"].as_str().map(String::from))
        // The app names an account from the signer's roster (a keystore group or a device's id) and
        // no family: the doctest's are native segwit.
        }).or_else(|| group.as_ref().map(|_| "bitcoin".to_string()));
        let Some(family) = family.filter(|f| f == "bitcoin" || f == "bitcoin_taproot") else {
            return json!({"ok": false, "error": "name a group to reopen, or a family to pick, create or restore one"});
        };
        // The core keeps a gap limit per wallet, and a group has a wallet per network.
        let kept = group.as_ref().and_then(|g| self.wallets.iter().find(|w| w["group"] == g.as_str() && w["network"] == self.active.as_str()))
            .and_then(|w| w["gapLimit"].as_u64());
        let gap = match p.get("gapLimit").filter(|v| !v.is_null()) {
            Some(v) => match gap_limit_of(v) {
                Some(g) => g,
                None => return json!({"ok": false, "code": "invalid", "error": "gapLimit is a whole number from 20 to 1000"}),
            },
            None => kept.unwrap_or(GAP_LIMIT_DEFAULT),
        };
        self.gap_limit = gap;
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
        (self.asked, self.answer_at) = (false, None);
    }

    fn seed_wallet(&mut self) {
        let net = self.network.clone();
        self.confirmed = 125_000_000;
        self.change = 0;
        let t = tip(&net);
        let now = now_secs();
        let own = address(&net, 'q', 1001);
        let them = address(&net, 'q', 77);
        let mut txids = vec![];
        for _ in 0..6 {
            txids.push(self.txid());
        }
        let first = day_number(FIRST_TX_DAY).map_or(now, |d| d as u64 * 86_400 + 43_200);
        let row = |txid: &str, intent: &str, amount: u64, fee: Option<u64>, state: &str, height: Option<u64>, extra: Value| {
            let mut r = json!({"txid": txid, "intent": intent, "amountSat": amount.to_string(), "feeSat": fee.map(|f| f.to_string()),
                               "coins": null, "counterparties": [], "height": height, "blockHash": height.map(block_hash),
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
            row(&txids[5], "receive", 125_000_000, None, "confirmed", Some(t - 100), json!({"time": first})),
        ];
        if net == "signet" {
            self.beyond_gap = self.gap_limit < BEYOND_GAP_NEEDS;
            if !self.beyond_gap {
                self.confirmed += BEYOND_GAP_SAT;
            }
            let r = row(&beyond_gap_txid(), "receive", BEYOND_GAP_SAT, None, "confirmed", Some(t - 60), json!({"beyondGap": self.beyond_gap}));
            let at = self.history.len() - 1;
            self.history.insert(at, r);
        } else {
            self.beyond_gap = false;
        }
        let esplora = self.sources.get(&net).is_some_and(|l| l.iter().any(|s| s.enabled && s.kind == "esplora"));
        self.unchecked = net == "signet" && self.kyoto() && esplora;
        self.chain_base = if self.unchecked { checkpoint(&net) } else { 0 };
        if self.unchecked {
            // No reportedBy, as the core leaves an unchecked row: the alert names the source.
            let r = row(&unchecked_txid(), "receive", UNCHECKED_SAT, None, "unchecked", Some(UNCHECKED_HEIGHT), json!({}));
            self.history.insert(2, r);
        }
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
                COIN_SAT + if self.beyond_gap { BEYOND_GAP_SAT } else { 0 } - fee
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
        let spare = if self.beyond_gap { BEYOND_GAP_SAT } else { 0 };
        if amount + fee > self.confirmed + spare {
            return json!({"ok": false, "error": "insufficient funds: not enough confirmed coins for this and its fee"});
        }
        let fate = match amount {
            REJECTED_SAT => Fate::Reject,
            EXPIRED_SAT => Fate::Expire,
            UNKNOWN_SAT => Fate::Unknown,
            _ => Fate::Approve,
        };
        let small_change = amount == SMALL_CHANGE_SAT;
        // Coin selection takes the coin past the gap limit as any other: a small send fits in it.
        let beyond = if !self.beyond_gap || small_change || kind == "fee_bump" { 0 }
                     else if p["sendMax"] == true || amount + fee <= BEYOND_GAP_SAT { BEYOND_GAP_SAT } else { 0 };
        let input = if small_change { amount + fee + 400 } else if p["sendMax"] == true { COIN_SAT + beyond }
                    else if beyond > 0 { beyond } else { COIN_SAT.max(amount + fee) };
        // With smallChangeToFee the too-small change goes to the fee, and the warning says so.
        let to_fee = if small_change && p["smallChangeToFee"] == true { 400 } else { 0 };
        let fee = fee + to_fee;
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
            broadcast: None, via: None, cancelling: false, abandoned: false, small_change: small_change && to_fee == 0, to_fee,
            beyond, created: t, updated: t,
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

    /// `{ date }` or `{ height }`, as the backend parses it; the core's refusals come back as a failed job.
    pub fn set_birthday(&mut self, params: &str, now: Instant) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let p: Value = match serde_json::from_str::<Value>(params) {
            Ok(v) if v.is_object() => v,
            _ => return json!({"ok": false, "error": "set_birthday takes { date: \"YYYY-MM-DD\" } or { height }"}),
        };
        let (date, height) = (p.get("date").filter(|v| !v.is_null()), p.get("height").filter(|v| !v.is_null()));
        let net = self.network.clone();
        let first_height = tip(&net) - 100;
        let first_day = day_number(FIRST_TX_DAY).unwrap_or(0);
        let today = (now_secs() / 86_400) as i64;
        let floor = activation(&net, &self.family);
        let outcome: Result<u64, String> = match (date, height) {
            (Some(Value::String(d)), None) => match day_number(d.trim()) {
                None => return json!({"ok": false, "error": "set_birthday takes { date: \"YYYY-MM-DD\" } or { height }"}),
                Some(n) if n > today => Err(BIRTHDAY_FUTURE.into()),
                Some(n) if n > first_day => Err(format!("the wallet has a transaction from before {}, at height {first_height}", d.trim())),
                Some(n) => Ok(tip(&net).saturating_sub(((today - n).max(0) as u64) * 144 + 288).max(floor)),
            },
            (None, Some(Value::Number(h))) if h.as_u64().is_some_and(|h| h <= u32::MAX as u64) => {
                let h = h.as_u64().unwrap_or(0);
                if h > first_height { Err(format!("the wallet has a transaction at height {first_height}, before a birthday at {h}")) }
                else { Ok(h.saturating_sub(288).max(floor)) }
            }
            (Some(_), Some(_)) => return json!({"ok": false, "error": "give date or height, not both"}),
            _ => return json!({"ok": false, "error": "set_birthday takes { date: \"YYYY-MM-DD\" } or { height }"}),
        };
        let j = self.job("set_birthday", now, None);
        if let Some(job) = self.jobs.get_mut(&j) {
            match outcome {
                Ok(from) => job.result = json!({"birthday": {"height": from, "source": "set"}, "rescanFrom": from}),
                Err(e) => job.error = Some(e),
            }
        }
        json!({"ok": true, "jobId": j})
    }

    /// `{ gapLimit }`, 20 to 1000: a job that rescans from the birthday. Refusals carry code invalid or busy.
    pub fn set_gap_limit(&mut self, params: &str, now: Instant) -> Value {
        if !self.open() {
            return json!({"ok": false, "error": "no wallet is open"});
        }
        let p: Value = serde_json::from_str(params).unwrap_or(Value::Null);
        let Some(g) = gap_limit_of(&p["gapLimit"]) else {
            return json!({"ok": false, "code": "invalid", "error": "gapLimit is a whole number from 20 to 1000"});
        };
        if self.rescan_from.is_some() || self.jobs.values().any(|j| j.state == "running" && matches!(j.kind.as_str(), "set_gap_limit" | "set_birthday")) {
            return json!({"ok": false, "code": "busy", "error": "a rescan is running; try again once it ends"});
        }
        let j = self.job("set_gap_limit", now, None);
        if let Some(job) = self.jobs.get_mut(&j) {
            job.result = json!({"gapLimit": g, "rescanFrom": self.birthday_height});
        }
        json!({"ok": true, "jobId": j})
    }

    /// After a rescan, the coin past the gap limit joins the balance once the limit reaches it.
    fn settle_gap(&mut self) {
        let beyond = self.network == "signet" && self.gap_limit < BEYOND_GAP_NEEDS;
        if beyond == self.beyond_gap || self.network != "signet" {
            return;
        }
        if beyond { self.confirmed -= BEYOND_GAP_SAT } else { self.confirmed += BEYOND_GAP_SAT }
        self.beyond_gap = beyond;
        let txid = beyond_gap_txid();
        if let Some(r) = self.history.iter_mut().find(|r| r["txid"] == txid.as_str()) {
            r["beyondGap"] = json!(beyond);
        }
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
            let was = current.iter().find(|c| c.id == id);
            let suspect = was.is_some_and(|c| c.suspect);
            // A pin is kept when the entry leaves it out, and set or cleared when it names one.
            let pin = match it.get("certSha256") {
                None => was.and_then(|c| c.pin.clone()),
                Some(v) => match parse_pin(v) {
                    Ok(p) => p,
                    Err(e) => return json!({"ok": false, "error": format!("{id}: {e}")}),
                },
            };
            if pin.is_some() && !is_tls(&url) {
                return json!({"ok": false, "error": format!("{id}: invalid parameters: certSha256 pins a TLS server (ssl:// or https://)")});
            }
            let user_added = was.map_or(!defaults().iter().any(|d| d.id == id), |c| c.user_added);
            out.push(Source {
                operator: given("operator").unwrap_or_else(|| if kind == "kyoto" { "peers".into() } else { site(&host) }),
                label: given("label").unwrap_or_else(|| host.clone()),
                enabled: it["use"].as_bool().unwrap_or(true),
                history: it["history"].as_bool().unwrap_or(false),
                tor: it["tor"].as_bool().unwrap_or(true),
                id, kind, url, suspect, pin, user_added,
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
        if let Some(v) = c.get("certSha256") {
            let pin = match parse_pin(v) {
                Ok(p) => p,
                Err(e) => return json!({"ok": false, "error": e}),
            };
            if pin.is_some() && !is_tls(&s.url) {
                return json!({"ok": false, "error": "invalid parameters: certSha256 pins a TLS server (ssl:// or https://)"});
            }
            s.pin = pin;
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

    fn curated(net: &str) -> Value {
        let n = if net == "testnet4" { 1 } else { 11 };
        let peers: Vec<String> = (0..n).map(|i| format!("peer{i}{}.onion:38333", "a".repeat(46))).collect();
        json!({"format": 1, "network": net, "version": "202610110405", "created": "2026-10-11T04:05:49Z", "date": "2026-10-11",
               "note": "PROVISIONAL: from 1 run (2026-10-11), not the plan's 6 of 7 days. Signed with a TEST key: not a release.",
               "refreshUrl": null, "peers": peers, "keyId": "test-d680f3cac9837bf9", "signature": "00"})
    }

    /// The node module's peer_list: the curated list, your own peers, and how Kyoto reaches them.
    pub fn peer_list(&self, params: &str) -> Value {
        let p: Value = serde_json::from_str(params).unwrap_or(Value::Null);
        let net = p["network"].as_str().filter(|n| !n.is_empty()).map(String::from).unwrap_or_else(|| self.net());
        let own = self.own_peers.get(&net).cloned().unwrap_or_default();
        let list = Self::curated(&net);
        let host = |h: &String| host_of(&format!("x://{h}"));
        let route = if !own.is_empty() && own.iter().all(|h| is_lan(&host(h))) { "direct" }
                    else if own.iter().all(|h| host(h).ends_with(".onion")) { "onion" } else { "tor" };
        let usable = if own.is_empty() { list["peers"].clone() } else { json!(own) };
        // The install's peer book: the signed list, peers learned from it, and Core's onion seeds.
        let listed = list["peers"].as_array().map_or(0, Vec::len);
        let learned = if net == "signet" { 3 } else { 0 };
        let usable_n = if own.is_empty() { listed + learned } else { own.len() };
        let counts = json!({"list": listed, "learned": learned, "seed": 8, "usable": usable_n, "okLast30d": if net == "signet" { 6 } else { 1 }});
        json!({"ok": true, "network": net, "list": list, "ownPeers": own, "usable": usable, "counts": counts,
               "route": route, "kyotoTor": true})
    }

    /// `{ network, peers }`, at most 64; [] goes back to the curated list. Refused while a wallet is open.
    pub fn set_own_peers(&mut self, params: &str) -> Value {
        if self.locked() {
            return json!({"ok": false, "error": LOCKED});
        }
        let p: Value = match serde_json::from_str::<Value>(params) {
            Ok(v) if v.is_object() => v,
            _ => return json!({"ok": false, "error": "set_own_peers takes { network, peers: [host[:port]] }"}),
        };
        let net = p["network"].as_str().filter(|n| !n.is_empty()).map(String::from).unwrap_or_else(|| self.net());
        let Some(peers) = p["peers"].as_array() else { return json!({"ok": false, "error": "peers must be a list"}) };
        if peers.len() > MAX_OWN_PEERS {
            return json!({"ok": false, "error": format!("invalid parameters: at most {MAX_OWN_PEERS} peers of your own")});
        }
        let mut own: Vec<String> = vec![];
        for v in peers {
            let h = v.as_str().map(str::trim).unwrap_or_default().to_string();
            let host = host_of(&format!("x://{h}"));
            if host.is_empty() || !host.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-') {
                return json!({"ok": false, "error": format!("invalid parameters: {h:?} is not host[:port]")});
            }
            if !own.contains(&h) {
                own.push(h);
            }
        }
        let lan = own.iter().filter(|h| is_lan(&host_of(&format!("x://{h}")))).count();
        if lan != 0 && lan != own.len() {
            return json!({"ok": false, "error": "invalid parameters: peers on your network and peers through Tor can't be mixed"});
        }
        self.own_peers.insert(net.clone(), own);
        self.peer_list(&json!({"network": net}).to_string())
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
        if self.answer_at.is_some_and(|t| now >= t) {
            (self.asked, self.answer_at) = (true, None);
        }
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
                (self.asked, self.answer_at) = (false, Some(now + FIRST_ANSWER));
                self.seed_wallet();
                // Restored without a birthday: the scan starts where its kind of address began.
                self.birthday_height = activation(&self.network, &self.family);
                self.birthday_source = "activation".into();
                let entry = json!({"group": self.group, "family": self.family, "network": self.network, "label": self.label,
                                   "birthday": birthday(&self.network), "gapLimit": self.gap_limit,
                                   "firstOpened": now_secs(), "lastOpened": now_secs()});
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
                if self.unchecked {
                    self.unchecked_alert_at = Some(now + UNCHECKED_ALERT_AFTER);
                }
                // Kyoto set aside peers that disagreed on a filter header on its way to the tip.
                if self.kyoto() {
                    self.conflict_at = Some(now_secs());
                }
                if !self.reorged && self.reorg_at.is_none() {
                    self.reorg_at = Some(now + REORG_AFTER);
                }
            }
            WState::Closing if elapsed >= CLOSE_TIME => {
                self.reset();
                if self.pending_network.is_some() {
                    self.switch_at = Some(now + SWITCH_AFTER_CLOSE);
                }
                self.alert_at = None;
                self.rescan_from = None;
                self.rescan_until = None;
                self.authority_alert_at = None;
                self.last_reorg = Value::Null;
                (self.unchecked, self.unchecked_alert_at, self.chain_base) = (false, None, 0);
                (self.rescans, self.window_rescan, self.conflict_at) = (0, false, None);
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
        // A switch queued behind the close applies once it has settled.
        if self.switch_at.is_some_and(|t| now >= t) {
            self.switch_at = None;
            if let Some(n) = self.pending_network.take() {
                self.active = n;
            }
        }
        if self.rescan_until.is_some_and(|t| now >= t) {
            let below = self.birthday_height < self.chain_base;
            if self.unchecked && below && !self.window_rescan {
                // The scan from the new birthday ends wider once, as Kyoto's does when the window does not hold.
                (self.window_rescan, self.rescans, self.rescan_until) = (true, self.rescans + 1, Some(now + RESCAN_TIME));
            } else {
                self.rescan_until = None;
                self.rescan_from = None;
                self.window_rescan = false;
                if self.unchecked && below {
                    self.check_unchecked();
                }
                self.settle_gap();
            }
        }
        if self.unchecked_alert_at.is_some_and(|t| now >= t) && self.open() {
            self.unchecked_alert_at = None;
            out.push(Event::SourceAlert(json!({"source": "esplora.example", "kind": "unchecked_anchor",
                "detail": format!("reported a payment in block {UNCHECKED_HEIGHT}, below the chain's start at {}: nothing could check it", self.chain_base),
                "at": now_secs(), "network": self.network, "group": self.group})));
        }
        if self.reorg_at.is_some_and(|t| now >= t) && self.state == WState::Ready {
            self.reorg_at = None;
            self.reorg(now);
        }
        // Kyoto as the authority names a chain the checks refuse, once.
        if self.state == WState::Ready && self.kyoto() && !self.authority_alerted && self.authority_alert_at.is_none() {
            self.authority_alert_at = Some(now + AUTHORITY_ALERT_AFTER);
        }
        if self.authority_alert_at.is_some_and(|t| now >= t) && self.open() {
            self.authority_alert_at = None;
            self.authority_alerted = true;
            out.push(Event::SourceAlert(json!({"source": "kyoto", "kind": "authority_suspect",
                "detail": "a filter header its peers agreed on does not match the block they sent", "at": now_secs(),
                "network": self.network, "group": self.group})));
        }
        // Change events, as the backend sends them: on what the status says, and on amounts.
        let st = self.status(now);
        let digest = json!([st["state"], st["openHandle"], st["walletTip"], st["authority"]["peers"], st["authority"]["asked"], st["openSend"]]).to_string();
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

    /// A birthday below the chain's start lowered it to genesis: the rescan checked the payment.
    fn check_unchecked(&mut self) {
        let t = tip(&self.network);
        if let Some(r) = self.history.iter_mut().find(|r| r["state"] == "unchecked") {
            r["state"] = json!("confirmed");
            r["confirmations"] = json!(t.saturating_sub(UNCHECKED_HEIGHT) + 1);
        }
        (self.unchecked, self.chain_base) = (false, 0);
        self.confirmed += UNCHECKED_SAT;
    }

    /// The seeded transfer to yourself, three blocks deep, confirms again in a new block at its height.
    fn reorg(&mut self, now: Instant) {
        let Some(row) = self.history.iter_mut().find(|r| r["intent"] == "self" && r["state"] == "confirmed") else { return };
        let height = row["height"].as_u64().unwrap_or(0);
        row["blockHash"] = json!(format!("{:064x}", 0x0e0e_0000_0000u64 + height));
        let txid = row["txid"].clone();
        self.reorged = true;
        self.last_reorg = json!({"height": height, "depth": 1, "moved": [txid], "at": now_secs()});
        let _ = now;
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
                    // A warning takes the person longer to read: time to add the change to the fee.
                    ("awaiting_approval", Fate::Approve) if e >= Duration::from_secs(if s.small_change { 8 } else { 3 }) => {
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
                             "feeSat": fee.to_string(), "coins": null, "counterparties": [recipient], "height": null, "blockHash": null,
                             "confirmations": 0, "time": now_secs(), "state": "sent", "replaces": replaces, "replacedBy": null,
                             "reportedBy": null, "sendState": "sent", "amountBtc": btc_of(amount), "feeBtc": btc_of(fee)});
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
            .filter(|(_, j)| j.state == "running" && matches!(j.kind.as_str(), "rebroadcast" | "abandon_send" | "set_birthday" | "set_gap_limit") && now.saturating_duration_since(j.at) >= STEP)
            .map(|(id, _)| id.clone())
            .collect();
        for id in due {
            let (kind, send) = {
                let j = &self.jobs[&id];
                (j.kind.clone(), j.send.clone().unwrap_or_default())
            };
            let n = send.strip_prefix('s').and_then(|n| n.parse::<u64>().ok()).unwrap_or(0);
            if kind == "set_gap_limit" {
                let result = self.jobs[&id].result.clone();
                self.gap_limit = result["gapLimit"].as_u64().unwrap_or(GAP_LIMIT_DEFAULT);
                let group = self.group.clone();
                if let Some(w) = self.wallets.iter_mut().find(|w| w["group"] == group.as_str()) {
                    w["gapLimit"] = json!(self.gap_limit);
                }
                self.rescan_from = Some(self.birthday_height);
                self.rescan_until = Some(now + RESCAN_TIME);
                self.finish(&id, "done", None, result, out);
                continue;
            }
            if kind == "set_birthday" {
                let (result, error) = {
                    let j = &self.jobs[&id];
                    (j.result.clone(), j.error.clone())
                };
                if let Some(e) = error {
                    self.finish(&id, "failed", Some(e), Value::Null, out);
                } else {
                    let from = result["rescanFrom"].as_u64().unwrap_or(0);
                    self.birthday_height = from;
                    self.birthday_source = "set".into();
                    self.rescan_from = Some(from);
                    self.rescan_until = Some(now + RESCAN_TIME);
                    self.finish(&id, "done", None, result, out);
                }
                continue;
            }
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
    fn an_open_shows_the_stored_chain_until_its_sources_answer() {
        let t0 = Instant::now();
        let mut sim = Sim::new(false, t0);
        sim.set_active_network("signet");
        let mut ev = vec![];
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t0, &mut ev);
        sim.close_wallet(t0, &mut ev);
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t0, &mut ev);
        // Approved at 4 s, syncing from 5 s: nothing asked for 4 s more.
        let t = run(&mut sim, t0, 6);
        let a = sim.status(t)["authority"].clone();
        assert_eq!((a["height"].clone(), a["peers"].clone(), a["asked"].clone()), (json!(290_123), json!(0), json!(false)), "{a}");
        assert!(sim.source_health(0)["wallet"]["sources"].as_array().unwrap().iter().all(|w| w["state"] == "unknown"));
        let t = run(&mut sim, t, 4);
        let a = sim.status(t)["authority"].clone();
        assert_eq!((a["peers"].clone(), a["asked"].clone()), (json!(1), json!(true)), "{a}");
        assert!(sim.source_health(0)["wallet"]["sources"].as_array().unwrap().iter().all(|w| w["state"] == "ok"));
    }

    #[test]
    fn opens_reveal_no_address_and_a_gap_stops_new_ones() {
        let (mut sim, t) = opened("signet");
        assert_eq!(sim.current_address()["index"], 0);
        assert_eq!(sim.current_address()["index"], 0, "asking again reveals nothing");
        let a = sim.receive_address();
        assert_eq!((a["index"].clone(), a["fresh"].clone()), (json!(1), json!(true)));
        let mut ev = vec![];
        sim.close_wallet(t, &mut ev);
        let t = run(&mut sim, t, 4);
        sim.open_wallet(r#"{"family":"bitcoin","group":"g_fixture2"}"#, t, &mut ev);
        let t = run(&mut sim, t, 10);
        assert_eq!(sim.current_address()["index"], 0, "a reopen shows the first unused address");
        assert_eq!(sim.receive_address()["index"], 2);
        let g = sim.set_gap_limit(r#"{"gapLimit":30}"#, t);
        assert_eq!(g["ok"], true, "{g}");
        let t = run(&mut sim, t, 6);
        sim.close_wallet(t, &mut ev);
        let t = run(&mut sim, t, 4);
        sim.set_active_network("testnet4");
        let t = run(&mut sim, t, 1);
        sim.open_wallet(r#"{"family":"bitcoin","group":"g_fixture2"}"#, t, &mut ev);
        run(&mut sim, t, 10);
        assert_eq!(sim.receive_address(), json!({"ok": true, "address": address("testnet4", 'q', 1000), "index": 0, "fresh": false, "unused": 20, "gapLimit": 20}));
    }

    #[test]
    fn fee_estimates_by_network() {
        let (sim, _) = opened("signet");
        assert_eq!((sim.fee_rates()["normal"].clone(), sim.fee_rates()["estimated"].clone()), (json!(6.0), json!(true)));
        let (sim, _) = opened("testnet4");
        assert_eq!(sim.fee_rates(), json!({"ok": false, "error": "no fee estimate yet"}));
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
    fn a_device_account_opens_by_its_id() {
        let t0 = Instant::now();
        let mut sim = Sim::new(false, t0);
        sim.set_active_network("signet");
        let mut ev = vec![];
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t0, &mut ev);
        let t = run(&mut sim, t0, 10);
        sim.close_wallet(t, &mut ev);
        let id = "shell-cdcdcdcd-84-1-0";
        assert_eq!(sim.open_wallet(&format!(r#"{{"group":"{id}","network":"signet"}}"#), t, &mut ev)["ok"], true);
        let t = run(&mut sim, t, 10);
        assert_eq!((sim.status(t)["state"].clone(), sim.status(t)["group"].clone()), (json!("ready"), json!(id)));
        assert_eq!(sim.list_wallets()["wallets"][0]["group"], id);
    }

    #[test]
    fn another_account_opens_only_once_the_open_wallet_has_closed() {
        let (mut sim, t) = opened("signet");
        let mut ev = vec![];
        let other = r#"{"group":"shell-cdcdcdcd-84-1-0"}"#;
        assert_eq!(sim.open_wallet(other, t, &mut ev)["error"], "a wallet is already open; close it first");
        sim.close_wallet(t, &mut ev);
        assert_eq!(sim.open_wallet(other, t, &mut ev)["error"], "a wallet is already open; close it first", "nor while it closes");
        let t = run(&mut sim, t, 4);
        assert_eq!(sim.open_wallet(other, t, &mut ev)["ok"], true);
        let t = run(&mut sim, t, 10);
        assert_eq!((sim.status(t)["state"].clone(), sim.status(t)["group"].clone()), (json!("ready"), json!("shell-cdcdcdcd-84-1-0")));
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
    fn a_birthday_is_refused_after_the_first_payment_and_rescans_otherwise() {
        let (mut sim, t) = opened("signet");
        assert_eq!(sim.status(t)["needsBirthday"], true);
        for (params, error) in [(r#"{"date":"2099-01-01"}"#, BIRTHDAY_FUTURE.to_string()),
                                (r#"{"date":"2026-07-01"}"#, "the wallet has a transaction from before 2026-07-01, at height 290023".to_string())] {
            let j = sim.set_birthday(params, t)["jobId"].as_str().unwrap().to_string();
            run(&mut sim, t, 2);
            let st = sim.job_status(&j);
            assert_eq!((st["state"].clone(), st["error"].clone()), (json!("failed"), json!(error)));
        }
        assert!(sim.set_birthday(r#"{"date":"2026-01-02","height":1}"#, t)["error"].is_string(), "not both");
        let j = sim.set_birthday(r#"{"height":0}"#, t)["jobId"].as_str().unwrap().to_string();
        let t = run(&mut sim, t, 2);
        assert_eq!(sim.job_status(&j)["result"]["rescanFrom"], 0);
        let st = sim.status(t);
        assert_eq!((st["needsBirthday"].clone(), st["birthdaySource"].clone(), st["rescanFrom"].clone()), (json!(false), json!("set"), json!(0)));
        assert!(st.get("syncPercent").is_none(), "a server's full scan reports no share");
        let t = run(&mut sim, t, 5);
        assert!(sim.status(t)["rescanFrom"].is_null());
    }

    #[test]
    fn small_change_goes_to_the_fee_when_asked() {
        let (mut sim, t) = opened("signet");
        let mut ev = vec![];
        let to = address("signet", 'q', 5);
        let ask = |small: bool| json!({"recipients": [{"address": to, "amountSat": "50000"}], "feeRate": 6, "smallChangeToFee": small}).to_string();
        let id = sim.request("send", APP, &ask(false), t, &mut ev)["requestId"].as_str().unwrap().to_string();
        let t = run(&mut sim, t, 2);
        assert_eq!(sim.send_status(&id)["summary"]["warnings"][0]["kind"], "change_too_small");
        sim.cancel_send(&id, t, &mut ev);
        let t = run(&mut sim, t, 1);
        let id = sim.request("send", APP, &ask(true), t, &mut ev)["requestId"].as_str().unwrap().to_string();
        run(&mut sim, t, 2);
        let summary = sim.send_status(&id)["summary"].clone();
        assert_eq!((summary["warnings"][0]["kind"].clone(), summary["change"].clone(), summary["feeSat"].clone()),
                   (json!("change_to_fee"), json!([]), json!("1246")));
    }

    #[test]
    fn a_reorg_re_anchors_a_payment_and_kyoto_names_a_refused_chain() {
        let (mut sim, t) = opened("signet");
        let t = run(&mut sim, t, 6);
        let reorg = sim.status(t)["lastReorg"].clone();
        let moved = reorg["moved"][0].as_str().unwrap().to_string();
        let row = sim.history(0)["rows"].as_array().unwrap().iter().find(|r| r["txid"] == moved.as_str()).unwrap().clone();
        assert_eq!((row["intent"].clone(), reorg["height"].clone()), (json!("self"), row["height"].clone()));
        assert!(row["blockHash"].as_str().unwrap().starts_with("00000000000000000000000000000000000000000000000000000e0e"));
        let mut ev = vec![];
        sim.close_wallet(t, &mut ev);
        let t = run(&mut sim, t, 4);
        assert!(sim.set_source("kyoto", r#"{"use":true}"#)["ok"] == true);
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t, &mut ev);
        let mut out = vec![];
        let mut tt = t;
        for _ in 0..120 {
            tt += Duration::from_millis(100);
            out.extend(sim.tick(tt));
        }
        let st = sim.status(tt);
        assert_eq!((st["authority"]["kind"].clone(), st["authority"]["peers"].clone()), (json!("kyoto"), json!(KYOTO_PEERS)));
        assert!(out.iter().any(|e| matches!(e, Event::SourceAlert(v) if v["kind"] == "authority_suspect")));
    }

    #[test]
    fn under_kyoto_on_signet_a_payment_below_the_chains_start_is_unchecked_until_an_earlier_birthday() {
        let (mut sim, t) = opened("signet");
        let mut ev = vec![];
        sim.close_wallet(t, &mut ev);
        let t = run(&mut sim, t, 4);
        assert_eq!(sim.set_source("kyoto", r#"{"use":true}"#)["ok"], true);
        sim.open_wallet(r#"{"family":"bitcoin"}"#, t, &mut ev);
        let (mut out, mut tt) = (vec![], t);
        for _ in 0..100 {
            tt += Duration::from_millis(100);
            out.extend(sim.tick(tt));
        }
        let st = sim.status(tt);
        assert_eq!((st["state"].clone(), st["authority"]["base"].clone(), st["kyoto"]["quorum"].clone(), st["kyoto"]["onePeerDecides"].clone()),
                   (json!("ready"), json!(290_000), json!(2), json!(false)));
        assert!(st["kyoto"]["lastConflict"]["at"].is_u64());
        assert_eq!((sim.balances()["unchecked"].clone(), sim.balances()["uncheckedBtc"].clone()), (json!("60000"), json!("0.00060000")));
        let row = |sim: &Sim| sim.history(0)["rows"].as_array().unwrap().iter().find(|r| r["txid"] == unchecked_txid().as_str()).cloned().unwrap();
        assert_eq!((row(&sim)["state"].clone(), row(&sim)["reportedBy"].clone(), row(&sim)["height"].clone()),
                   (json!("unchecked"), Value::Null, json!(UNCHECKED_HEIGHT)));
        assert!(out.iter().any(|e| matches!(e, Event::SourceAlert(v) if v["kind"] == "unchecked_anchor")));
        // A birthday below the chain's start: its rescan, then one wider pass, and the payment is checked.
        assert_eq!(sim.set_birthday(r#"{"height":0}"#, tt)["ok"], true);
        let tt = run(&mut sim, tt, 2);
        assert_eq!(sim.status(tt)["rescanFrom"], 0);
        let tt = run(&mut sim, tt, 4);
        let st = sim.status(tt);
        assert_eq!((st["kyoto"]["rescans"].clone(), st.get("syncPercent").cloned()), (json!(1), None), "a wider pass, with no share to show");
        let tt = run(&mut sim, tt, 5);
        let st = sim.status(tt);
        assert_eq!((st["rescanFrom"].clone(), st["authority"]["base"].clone(), sim.balances()["unchecked"].clone()), (Value::Null, json!(0), json!("0")));
        assert_eq!(row(&sim)["state"], "confirmed");
    }

    #[test]
    fn on_testnet4_kyoto_runs_on_its_one_peer_which_decides_the_chain() {
        let (sim, t) = opened("testnet4");
        let st = sim.status(t);
        assert_eq!((st["authority"]["kind"].clone(), st["authority"]["peers"].clone(), st["kyoto"]["quorum"].clone(), st["kyoto"]["onePeerDecides"].clone()),
                   (json!("kyoto"), json!(1), json!(1), json!(true)));
        let p = sim.peer_list(r#"{"network":"testnet4"}"#);
        assert_eq!((p["list"]["peers"].as_array().unwrap().len(), p["counts"]["list"].clone(), p.get("source")), (1, json!(1), None));
        assert_eq!(sim.balances()["unchecked"], "0");
    }

    #[test]
    fn a_coin_past_the_gap_limit_is_apart_and_spendable_until_the_limit_reaches_it() {
        let (mut sim, t) = opened("signet");
        let b = sim.balances();
        assert_eq!((b["beyondGap"]["count"].clone(), b["beyondGap"]["sat"].clone(), b["beyondGap"]["confirmedSat"].clone(), b["beyondGapBtc"].clone(), b["confirmed"].clone()),
                   (json!(1), json!("70000"), json!("70000"), json!("0.00070000"), json!("125000000")));
        assert_eq!(sim.status(t)["gapLimit"], 20);
        let row = |sim: &Sim| sim.history(0)["rows"].as_array().unwrap().iter().find(|r| r["txid"] == beyond_gap_txid().as_str()).cloned().unwrap();
        assert_eq!((row(&sim)["beyondGap"].clone(), row(&sim)["state"].clone()), (json!(true), json!("confirmed")));
        // A small send spends it, and its summary says so.
        let mut ev = vec![];
        let to = address("signet", 'q', 5);
        let r = sim.request("send", APP, &json!({"recipients": [{"address": to, "amountSat": "20000"}], "feeRate": 6}).to_string(), t, &mut ev);
        let id = r["requestId"].as_str().unwrap().to_string();
        let t = run(&mut sim, t, 2);
        let w = sim.send_status(&id)["summary"]["warnings"].as_array().unwrap().iter().find(|w| w["kind"] == "beyond_gap_inputs").cloned().unwrap();
        assert_eq!((w["count"].clone(), w["sat"].clone()), (json!(1), json!("70000")));
        let t = run(&mut sim, t, 4);
        // Refused out of range, then raised: busy until its rescan ends, then the coin joins the balance.
        assert_eq!(sim.set_gap_limit(r#"{"gapLimit":10}"#, t)["code"], "invalid");
        assert_eq!(sim.set_gap_limit(r#"{"gapLimit":1001}"#, t)["code"], "invalid");
        let j = sim.set_gap_limit(r#"{"gapLimit":30}"#, t);
        assert_eq!(j["ok"], true);
        assert_eq!(sim.set_gap_limit(r#"{"gapLimit":40}"#, t)["code"], "busy");
        let t = run(&mut sim, t, 2);
        assert_eq!((sim.status(t)["gapLimit"].clone(), sim.status(t)["rescanFrom"].clone()), (json!(30), json!(0)));
        assert_eq!(sim.job_status(j["jobId"].as_str().unwrap())["result"], json!({"gapLimit": 30, "rescanFrom": 0}));
        let t = run(&mut sim, t, 5);
        let b = sim.balances();
        assert_eq!((b["beyondGap"]["count"].clone(), b["confirmed"].clone()), (json!(0), json!("125070000")));
        assert_eq!(row(&sim)["beyondGap"], false);
        // The wallet keeps its limit: reopened, the coin is in its balance from the start.
        sim.close_wallet(t, &mut ev);
        let t = run(&mut sim, t, 4);
        sim.open_wallet(r#"{"group":"g_fixture2"}"#, t, &mut ev);
        let t = run(&mut sim, t, 10);
        assert_eq!((sim.status(t)["gapLimit"].clone(), sim.balances()["confirmed"].clone()), (json!(30), json!("125070000")));
        // A limit asked for at open: out of range is refused.
        sim.close_wallet(t, &mut ev);
        let t = run(&mut sim, t, 4);
        assert_eq!(sim.open_wallet(r#"{"family":"bitcoin","gapLimit":5}"#, t, &mut ev)["code"], "invalid");
    }

    #[test]
    fn your_own_tls_server_shows_its_certificate_until_pinned() {
        let t0 = Instant::now();
        let mut sim = Sim::new(false, t0);
        let mut list = sim.sources()["sources"].as_array().unwrap().clone();
        list.push(json!({"id": "electrs.lan", "kind": "electrum", "url": "ssl://electrs.lan:50002", "use": true}));
        list.push(json!({"id": "plain", "kind": "electrum", "url": "192.168.1.20:50001", "use": true}));
        let r = sim.set_sources(&serde_json::to_string(&list).unwrap());
        let row = |r: &Value, id: &str| r["sources"].as_array().unwrap().iter().find(|s| s["id"] == id).unwrap().clone();
        assert_eq!((row(&r, "plain")["encrypted"].clone(), row(&r, "plain")["userAdded"].clone()), (json!(false), json!(true)));
        let p = sim.probe(r#"{"source":"electrs.lan"}"#);
        let cert = p["sources"][0]["certificate"].clone();
        assert_eq!((cert["trusted"].clone(), cert["issuer"].clone()), (json!(false), json!("CN=electrs.lan")));
        assert_eq!(sim.probe(r#"{"source":""}"#)["answered"].as_array().unwrap().len(), 4, "every enabled server");
        assert!(sim.set_source("plain", &json!({"certSha256": cert["certSha256"]}).to_string())["error"].as_str().unwrap().contains("TLS"));
        let pinned = sim.set_source("electrs.lan", &json!({"certSha256": cert["certSha256"]}).to_string());
        assert_eq!(row(&pinned, "electrs.lan")["certSha256"], cert["certSha256"]);
        assert_eq!(sim.probe(r#"{"source":"electrs.lan"}"#)["sources"][0]["certificate"]["trusted"], true);
        let kept = sim.set_sources(&serde_json::to_string(&sim.sources()["sources"]).unwrap());
        assert_eq!(row(&kept, "electrs.lan")["certSha256"], cert["certSha256"], "kept when the entry names it");
        let cleared = sim.set_source("electrs.lan", r#"{"certSha256":null}"#);
        assert!(row(&cleared, "electrs.lan").get("certSha256").is_none());
    }

    #[test]
    fn a_switch_waits_for_the_close_and_an_open_waits_for_the_switch() {
        let (mut sim, t) = opened("signet");
        assert_eq!(sim.set_active_network("testnet4")["code"], "wallet_open");
        let mut ev = vec![];
        sim.close_wallet(t, &mut ev);
        let r = sim.set_active_network("testnet4");
        assert_eq!((r["active"].clone(), r["pending"].clone()), (json!("signet"), json!("testnet4")));
        let t = run(&mut sim, t, 4);
        assert_eq!(sim.status(t)["state"], "no_wallet");
        let busy = sim.open_wallet(r#"{"family":"bitcoin"}"#, t, &mut ev);
        assert_eq!(busy["code"], "busy", "never on the old network");
        let t = run(&mut sim, t, 5);
        assert_eq!((sim.active(), sim.pending_network()), ("testnet4".to_string(), None));
        assert_eq!(sim.open_wallet(r#"{"family":"bitcoin"}"#, t, &mut ev)["ok"], true);
        assert_eq!(sim.set_active_network("signet")["code"], "busy", "an open in progress");
    }

    #[test]
    fn your_own_peers_replace_the_curated_list() {
        let mut sim = Sim::new(false, Instant::now());
        let p = sim.peer_list("{}");
        assert_eq!((p["list"]["peers"].as_array().unwrap().len(), p["ownPeers"].clone()), (11, json!([])));
        let r = sim.set_own_peers(r#"{"network":"mainnet","peers":["192.168.1.20:8333"]}"#);
        assert_eq!((r["ownPeers"].clone(), r["route"].clone()), (json!(["192.168.1.20:8333"]), json!("direct")));
        assert!(sim.set_own_peers(r#"{"peers":["192.168.1.20:8333","example.org:8333"]}"#)["error"].as_str().unwrap().contains("mixed"));
        let many: Vec<String> = (0..65).map(|i| format!("10.0.0.{i}:8333")).collect();
        assert!(sim.set_own_peers(&json!({"peers": many}).to_string())["error"].as_str().unwrap().contains("64"));
        assert_eq!(sim.set_own_peers(r#"{"peers":[]}"#)["ownPeers"], json!([]));
        let mut ev = vec![];
        sim.open_wallet(r#"{"family":"bitcoin"}"#, Instant::now(), &mut ev);
        assert_eq!(sim.set_own_peers(r#"{"peers":["192.168.1.20:8333"]}"#)["error"], LOCKED);
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
