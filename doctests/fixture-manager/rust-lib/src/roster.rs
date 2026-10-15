//! The accounts the stand-in offers, in the shape signer manager 3ef020c answers: a keystore
//! wallet on each chain, and a routed Keycard row (seed-centric `origin`) with nothing plugged in.

use serde_json::{json, Value};

pub const KEYSTORE_TEST: &str = "g_fixture_keystore";
pub const KEYSTORE_MAIN: &str = "g_fixture_mainnet";
pub const CARD: &str = "g_fixture_card";

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_keycard_row_is_unplugged_and_named_by_its_seed() {
        let all = accounts();
        let card = all["accounts"].as_array().unwrap().iter().find(|a| a["id"] == CARD).unwrap();
        assert_eq!(card["available"], false);
        assert_eq!(card["origin"]["phrase"]["name"], "Black Card");
    }
}
