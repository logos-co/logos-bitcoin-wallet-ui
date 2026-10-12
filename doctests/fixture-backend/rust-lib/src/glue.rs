//! A stand-in for `bitcoin_wallet_backend` in the wallet app's doctest. The trait is the real
//! backend's (logos-bitcoin-wallet-backend d7887b3), so the contract matches; behind it, sim.rs.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use logos_rust_sdk::{AboutToUnload, LogosCaller, Shutdown};
use serde_json::{json, Value};

use crate::sim::{self, Event, Sim};

pub trait BitcoinWalletBackendModule: Send + Sync + 'static {
    /// CUSTODIAN. Replaces the custodian set, `{ custodians }`: total (`{}` is nobody), unknown
    /// keys refused, saved to roles.json. `{ ok, custodians }`.
    fn configure(&self, roles_json: String) -> String;
    /// `{ ok, kind, identity, custodians, rolesFile }`: who this call came from, who holds the
    /// role, and the file a headless operator writes to enrol a module.
    fn caller_identity(&self) -> String;

    /// `{ ok, networks, active, pending }`; `pending` is a switch waiting for a close to settle.
    fn list_networks(&self) -> String;
    /// CUSTODIAN. While a close settles the switch is queued: `{ ok, active, pending }`, and opens are
    /// refused with code busy until it applies. Refusals carry `code`: busy, wallet_open, send_open.
    fn set_active_network(&self, network: String) -> String;
    /// `{ ok, active, wallets: [{ group, family, network, label, birthday, gapLimit, firstOpened, lastOpened }] }`:
    /// wallets opened before, newest first. No secrets.
    fn list_wallets(&self) -> String;
    /// CUSTODIAN. `{ network?, group?, family?, birthday?, label?, gapLimit? }` on the active network; gapLimit
    /// 20 to 1000, else the core's 20 or the wallet's stored one. `{ ok, jobId }`; wallet_status carries
    /// `openHandle` while the person decides in the keys app.
    fn open_wallet(&self, params_json: String) -> String;
    /// CUSTODIAN. Withdraws open sends first; refused while one is going out. `{ ok, jobId }`.
    fn close_wallet(&self) -> String;
    /// `{ ok, jobId, kind, state: queued|running|done|failed|cancelled, result?, error? }`.
    fn job_status(&self, job_id: String) -> String;
    /// CUSTODIAN. The open wallet's public descriptors, as a call result only, never an event.
    fn descriptors(&self) -> String;
    /// CUSTODIAN. `{ date: "YYYY-MM-DD" }` or `{ height }` for the open wallet; the core scans again from
    /// it. `{ ok, jobId }`; the job's result is `{ birthday: { height, source }, rescanFrom }`.
    fn set_birthday(&self, params_json: String) -> String;
    /// CUSTODIAN. `{ gapLimit }`, 20 to 1000, for the open wallet; a raise scans again from the birthday.
    /// `{ ok, jobId }`; the job's result is `{ gapLimit, rescanFrom }`. Refusal codes: invalid, busy, no_wallet.
    fn set_gap_limit(&self, params_json: String) -> String;

    /// The core's status, `gapLimit` included, plus `syncPercent`, `activeNetwork`, `label` and `openSend`.
    fn wallet_status(&self) -> String;
    /// `{ ok, busy, confirmed, waiting, pending, sent, immature, tooSmall, beyondGap: { count, sat } }` in
    /// satoshis, each with a `…Btc` twin. beyondGap is coins past the gap limit: outside confirmed, waiting
    /// and pending, still spendable. Empty while busy, never zero.
    fn balances(&self) -> String;
    /// The core's history page, newest first; rows gain `amountBtc` and `feeBtc`, and keep `beyondGap`.
    fn history(&self, page: i64) -> String;
    /// `{ ok, address, index }`: a fresh receive address.
    fn receive_address(&self) -> String;
    /// `{ ok, fast, normal, slow, minimum, sources }` in sat/vB.
    fn fee_rates(&self) -> String;
    /// An address or BIP21 URI on the wallet's network: `{ ok, valid, address, type, amountSat?, reason? }`.
    fn address_valid(&self, text: String) -> String;
    /// Satoshis, a decimal string, as BTC: `{ ok, sat, btc }`.
    fn format_btc(&self, sat: String) -> String;
    /// BTC as satoshis, exactly; more than 8 decimals is refused. `{ ok, btc, sat }`.
    fn parse_btc(&self, btc: String) -> String;

    /// The node module's sources for the wallet's network.
    fn sources(&self) -> String;
    /// The node module's source health, plus `wallet`, the open wallet's own view of them.
    fn source_health(&self) -> String;
    /// `{ network?, source }`: the node module probes that source now, or every enabled server for "",
    /// within 15 s; a TLS server's row carries `certificate`.
    fn probe(&self, params_json: String) -> String;
    /// The servers that have seen the open wallet's addresses, and since when.
    fn exposure(&self) -> String;
    /// CUSTODIAN. Replaces the network's sources, a JSON array. Refused while a wallet is open.
    fn set_sources(&self, list_json: String) -> String;
    /// CUSTODIAN. `{ use?, history?, tor? }` for one source. Refused while a wallet is open.
    fn set_source(&self, source_id: String, changes_json: String) -> String;
    /// CUSTODIAN. The Tor proxy for every source, socks5h://host:port. Refused while a wallet is open.
    fn set_proxy(&self, proxy: String) -> String;
    /// CUSTODIAN. Clears a suspect mark in the node module and, with a wallet open, in the core.
    fn clear_suspect(&self, source_id: String) -> String;
    /// CUSTODIAN. `{ network, peers: [host[:port]] }`, at most 64: Kyoto's own peers, which replace the
    /// curated list (`[]` restores it). Refused while a wallet is open. Answers as peer_list.
    fn set_own_peers(&self, params_json: String) -> String;
    /// CUSTODIAN. `{ network? }`: the node module's peer list, with `ownPeers` and `usable`.
    fn peer_list(&self, params_json: String) -> String;

    /// Any named module. `{ recipients: [{ address, amountSat | amountBtc }], feeRate? | target?,
    /// sendMax? }` → `{ ok, requestId }`. One open send per wallet.
    fn request_send(&self, request_json: String) -> String;
    /// Any named module. `{ txid, feeRate }` replaces an unconfirmed send with RBF, approved like
    /// any send. `{ ok, requestId }`.
    fn request_fee_bump(&self, request_json: String) -> String;
    /// `{ ok, requestId, kind, state, requester, summary, approvalHandle, txid, broadcast, via, error, errorCode,
    /// cancelling }`; states preparing, awaiting_approval, committing, sent, failed, cancelled, unknown.
    fn send_status(&self, request_id: String) -> String;
    /// `{ ok, sends: [{ requestId, kind, state, requester, approvalHandle, txid, errorCode, createdAt, updatedAt }] }`, newest first.
    fn list_sends(&self) -> String;
    /// The requester or a custodian. Withdraws the approval request and unlocks the inputs;
    /// refused once the transaction is going out. `{ ok, requestId, state, cancelling }`.
    fn cancel_send(&self, request_id: String) -> String;
    /// CUSTODIAN. Broadcasts a send's transaction again, named by request id or txid. `{ ok, jobId }`.
    fn rebroadcast(&self, request_or_txid: String) -> String;
    /// CUSTODIAN. `{ txid }` of a send in `unknown`: the core frees its coins. `{ ok, jobId, requestId,
    /// txid, note }`; if the original still confirms, a later send from them fails, or replaces it first.
    fn abandon_send(&self, params_json: String) -> String;

    fn on_context_ready(&self, _ctx: &RustModuleContext) {}
}

#[allow(dead_code)] // Read by logos-lidl-gen, which generates the emitters.
pub trait BitcoinWalletBackendModuleEvents {
    /// wallet_status()'s shape, whenever the core's state changes.
    fn wallet_state_changed(&self, payload: String);
    /// `{ state, network, walletTip, authorityHeight, tipAgeSecs, percent, synced }`, on change.
    fn sync_progress(&self, payload: String);
    /// balances()'s shape, when an amount the core read changes.
    fn balance_changed(&self, payload: String);
    fn send_status_changed(&self, request_id: String, state: String);
    /// Opens, closes and rebroadcasts, under the backend's job ids.
    fn job_finished(&self, job_id: String, state: String);
    /// The core's alert about a source: `{ source, kind, detail, at, network, group }`.
    fn source_alert(&self, payload: String);
}

include!(concat!(env!("CARGO_MANIFEST_DIR"), "/generated/provider_gen.rs"));

static UNLOADING: AtomicBool = AtomicBool::new(false);
const NOT_AUTHORIZED: &str = r#"{"ok":false,"error":"not authorized"}"#;

#[derive(Default)]
pub struct BitcoinWalletBackendModuleImpl {
    sim: Arc<Mutex<Option<Sim>>>,
    ticker: Mutex<Option<JoinHandle<()>>>,
}

/// The custodian gate the real backend keeps: the wallet app is its default custodian.
fn custodian() -> bool {
    matches!(logos_rust_sdk::current_caller(), LogosCaller::Module { ref name, .. } if name == sim::APP)
}

fn requester() -> Option<String> {
    match logos_rust_sdk::current_caller() {
        LogosCaller::Module { name, .. } if !name.is_empty() => Some(name),
        _ => None,
    }
}

fn emit(events: Vec<Event>) {
    for e in events {
        match e {
            Event::WalletState(v) => emit_wallet_state_changed(&v.to_string()),
            Event::SyncProgress(v) => emit_sync_progress(&v.to_string()),
            Event::Balance(v) => emit_balance_changed(&v.to_string()),
            Event::SendStatus(id, state) => emit_send_status_changed(&id, &state),
            Event::JobFinished(id, state) => emit_job_finished(&id, &state),
            Event::SourceAlert(v) => emit_source_alert(&v.to_string()),
        }
    }
}

impl BitcoinWalletBackendModuleImpl {
    /// Runs `f` on the simulation and sends what it raised once the lock is let go.
    fn with(&self, f: impl FnOnce(&mut Sim, Instant, &mut Vec<Event>) -> Value) -> String {
        let mut events = vec![];
        let reply = {
            let mut g = self.sim.lock().unwrap_or_else(|e| e.into_inner());
            let sim = g.get_or_insert_with(|| Sim::new(false, Instant::now()));
            f(sim, Instant::now(), &mut events)
        };
        emit(events);
        reply.to_string()
    }

    fn gated(&self, f: impl FnOnce(&mut Sim, Instant, &mut Vec<Event>) -> Value) -> String {
        if !custodian() {
            return NOT_AUTHORIZED.into();
        }
        self.with(f)
    }
}

impl BitcoinWalletBackendModule for BitcoinWalletBackendModuleImpl {
    fn configure(&self, _roles_json: String) -> String {
        self.gated(|_, _, _| json!({"ok": true, "custodians": [sim::APP]}))
    }

    fn caller_identity(&self) -> String {
        let identity = logos_rust_sdk::current_caller().identity();
        json!({"ok": true, "kind": if custodian() { "module" } else { "other" }, "identity": identity,
               "custodians": [sim::APP], "rolesFile": null})
        .to_string()
    }

    fn list_networks(&self) -> String {
        self.with(|s, _, _| json!({"ok": true, "networks": s.networks(), "active": s.active(), "pending": s.pending_network()}))
    }

    fn set_active_network(&self, network: String) -> String {
        self.gated(|s, _, _| s.set_active_network(network.trim()))
    }

    fn list_wallets(&self) -> String {
        self.with(|s, _, _| s.list_wallets())
    }

    fn open_wallet(&self, params_json: String) -> String {
        self.gated(|s, now, ev| s.open_wallet(&params_json, now, ev))
    }

    fn close_wallet(&self) -> String {
        self.gated(|s, now, ev| s.close_wallet(now, ev))
    }

    fn job_status(&self, job_id: String) -> String {
        self.with(|s, _, _| s.job_status(&job_id))
    }

    fn descriptors(&self) -> String {
        self.gated(|s, _, _| s.descriptors())
    }

    fn set_birthday(&self, params_json: String) -> String {
        self.gated(|s, now, _| s.set_birthday(&params_json, now))
    }

    fn set_gap_limit(&self, params_json: String) -> String {
        self.gated(|s, now, _| s.set_gap_limit(&params_json, now))
    }

    fn wallet_status(&self) -> String {
        self.with(|s, now, _| s.status(now))
    }

    fn balances(&self) -> String {
        self.with(|s, _, _| s.balances())
    }

    fn history(&self, page: i64) -> String {
        self.with(|s, _, _| s.history(page))
    }

    fn receive_address(&self) -> String {
        self.with(|s, _, _| s.receive_address())
    }

    fn fee_rates(&self) -> String {
        self.with(|s, _, _| s.fee_rates())
    }

    fn address_valid(&self, text: String) -> String {
        self.with(|s, _, _| s.address_valid(&text))
    }

    fn format_btc(&self, sat: String) -> String {
        match sim::parse_sat(&sat) {
            Ok(v) => json!({"ok": true, "sat": v.to_string(), "btc": sim::format_btc(v)}).to_string(),
            Err(e) => json!({"ok": false, "error": e}).to_string(),
        }
    }

    fn parse_btc(&self, btc: String) -> String {
        match sim::parse_btc(&btc) {
            Ok(v) => json!({"ok": true, "btc": sim::format_btc(v), "sat": v.to_string()}).to_string(),
            Err(e) => json!({"ok": false, "error": e}).to_string(),
        }
    }

    fn sources(&self) -> String {
        self.with(|s, _, _| s.sources())
    }

    fn source_health(&self) -> String {
        self.with(|s, _, _| s.source_health(sim::now_secs()))
    }

    fn probe(&self, params_json: String) -> String {
        self.with(|s, _, _| s.probe(&params_json))
    }

    fn exposure(&self) -> String {
        self.with(|s, _, _| s.exposure())
    }

    fn set_sources(&self, list_json: String) -> String {
        self.gated(|s, _, _| s.set_sources(&list_json))
    }

    fn set_source(&self, source_id: String, changes_json: String) -> String {
        self.gated(|s, _, _| s.set_source(source_id.trim(), &changes_json))
    }

    fn set_proxy(&self, proxy: String) -> String {
        self.gated(|s, _, _| s.set_proxy(&proxy))
    }

    fn set_own_peers(&self, params_json: String) -> String {
        self.gated(|s, _, _| s.set_own_peers(&params_json))
    }

    fn peer_list(&self, params_json: String) -> String {
        self.gated(|s, _, _| s.peer_list(&params_json))
    }

    fn clear_suspect(&self, source_id: String) -> String {
        self.gated(|s, now, ev| s.clear_suspect(source_id.trim(), now, ev))
    }

    fn request_send(&self, request_json: String) -> String {
        let Some(who) = requester() else { return NOT_AUTHORIZED.into() };
        self.with(|s, now, ev| s.request("send", &who, &request_json, now, ev))
    }

    fn request_fee_bump(&self, request_json: String) -> String {
        let Some(who) = requester() else { return NOT_AUTHORIZED.into() };
        self.with(|s, now, ev| s.request("fee_bump", &who, &request_json, now, ev))
    }

    fn send_status(&self, request_id: String) -> String {
        self.with(|s, _, _| s.send_status(&request_id))
    }

    fn list_sends(&self) -> String {
        self.with(|s, _, _| s.list_sends())
    }

    fn cancel_send(&self, request_id: String) -> String {
        if requester().is_none() {
            return NOT_AUTHORIZED.into();
        }
        self.with(|s, now, ev| s.cancel_send(&request_id, now, ev))
    }

    fn rebroadcast(&self, request_or_txid: String) -> String {
        self.gated(|s, now, _| s.rebroadcast(&request_or_txid, now))
    }

    fn abandon_send(&self, params_json: String) -> String {
        self.gated(|s, now, _| s.abandon_send(&params_json, now))
    }

    fn on_context_ready(&self, ctx: &RustModuleContext) {
        let dir = std::path::PathBuf::from(&ctx.instance_persistence_path);
        // Regtest is offered as the real backend offers it: with regtest.json beside the module's data.
        let regtest = dir.join("regtest.json").is_file();
        *self.sim.lock().unwrap_or_else(|e| e.into_inner()) = Some(Sim::new(regtest, Instant::now()));
        let shared = self.sim.clone();
        let ticker = std::thread::spawn(move || {
            while !UNLOADING.load(Ordering::SeqCst) {
                std::thread::sleep(Duration::from_millis(200));
                let events = {
                    let mut g = shared.lock().unwrap_or_else(|e| e.into_inner());
                    match g.as_mut() {
                        Some(sim) => sim.tick(Instant::now()),
                        None => vec![],
                    }
                };
                if !UNLOADING.load(Ordering::SeqCst) {
                    emit(events);
                }
            }
        });
        *self.ticker.lock().unwrap_or_else(|e| e.into_inner()) = Some(ticker);
    }
}

impl AboutToUnload for BitcoinWalletBackendModuleImpl {
    fn about_to_unload(&self) -> Shutdown {
        UNLOADING.store(true, Ordering::SeqCst);
        if let Some(t) = self.ticker.lock().unwrap_or_else(|e| e.into_inner()).take() {
            let until = Instant::now() + Duration::from_millis(1000);
            while !t.is_finished() && Instant::now() < until {
                std::thread::sleep(Duration::from_millis(10));
            }
            if t.is_finished() {
                let _ = t.join();
            }
        }
        Shutdown::Synchronous
    }
}

#[no_mangle]
pub extern "Rust" fn logos_module_install() {
    logos_install!(BitcoinWalletBackendModuleImpl);
}
