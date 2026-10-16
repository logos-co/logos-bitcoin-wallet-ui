//! The accounts the stand-in offers, in the shape signer manager 3ef020c answers: a keystore
//! wallet on each chain, and a routed Keycard row (seed-centric `origin`) with nothing plugged in.

use serde_json::{json, Value};

pub const KEYSTORE_TEST: &str = "g_fixture_keystore";
pub const KEYSTORE_MAIN: &str = "g_fixture_mainnet";
/// A routed Keycard row keeps the id its Shell lists it under, as `shell-f0150787-84-0-0` in Basecamp.
pub const CARD: &str = "shell-cdcdcdcd-84-1-0";

pub fn accounts() -> Value {
    let card_seed = format!("seed:{}", "cd".repeat(32));
    json!({ "ok": true, "accounts": [
        { "id": KEYSTORE_TEST, "family": "bitcoin", "chain": "test", "label": "Fixture wallet",
          "signer": "keystore_module", "available": true },
        { "id": KEYSTORE_MAIN, "family": "bitcoin", "chain": "main", "label": "Fixture mainnet wallet",
          "signer": "keystore_module", "available": true },
        { "id": CARD, "family": "bitcoin", "chain": "test", "label": "Card account",
          "signer": "keycard_module", "available": false,
          "origin": { "devices": [{ "kind": "keycard", "id": "ab".repeat(32), "name": "Keycard" }],
                      "phrase": { "id": card_seed, "name": "Black Card" } } },
    ]})
}

/// The same accounts as `roster()` answers them: each once, with its wallet and its one holder.
pub fn roster() -> Value {
    let holder = |signer: &str, id: &str, transport: &str, presence: &str, available: bool| {
        json!({ "signer": signer, "accountId": id, "kind": "", "model": "", "transport": transport,
                "presence": presence, "available": available, "collects": "nothing",
                "showsRequest": false, "requestKinds": ["hash"] })
    };
    json!({ "ok": true, "accounts": [
        { "key": "btc_00000000000000000000000000000001", "family": "bitcoin", "chain": "test",
          "path": "m/84'/1'/0'", "label": "Fixture wallet", "wallet": null,
          "holders": [holder("keystore_module", KEYSTORE_TEST, "keystore", "local", true)] },
        { "key": "btc_00000000000000000000000000000002", "family": "bitcoin", "chain": "main",
          "path": "m/84'/0'/0'", "label": "Fixture mainnet wallet", "wallet": null,
          "holders": [holder("keystore_module", KEYSTORE_MAIN, "keystore", "local", true)] },
        { "key": "btc_00000000000000000000000000000003", "family": "bitcoin", "chain": "test",
          "path": "m/84'/1'/0'", "label": "Card account", "wallet": { "fingerprint": "cdcdcdcd", "name": "Black Card" },
          "holders": [holder("keycard_module", CARD, "reader", "absent", false)] },
    ]})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_roster_lists_the_same_accounts_each_with_its_holder() {
        let (accounts, roster) = (accounts(), roster());
        let ids: Vec<&Value> = accounts["accounts"].as_array().unwrap().iter().map(|a| &a["id"]).collect();
        let held: Vec<&Value> =
            roster["accounts"].as_array().unwrap().iter().map(|e| &e["holders"][0]["accountId"]).collect();
        assert_eq!(ids, held);
        assert_eq!(roster["accounts"][2]["holders"][0]["presence"], "absent");
    }

    #[test]
    fn the_keycard_row_is_unplugged_and_named_by_its_seed() {
        let all = accounts();
        let card = all["accounts"].as_array().unwrap().iter().find(|a| a["id"] == CARD).unwrap();
        assert_eq!(card["available"], false);
        assert_eq!(card["origin"]["phrase"]["name"], "Black Card");
    }
}
