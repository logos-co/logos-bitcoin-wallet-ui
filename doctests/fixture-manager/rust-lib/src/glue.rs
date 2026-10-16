//! The stand-in's module glue: `accounts` and nothing else the wallet app calls.

use logos_rust_sdk::{AboutToUnload, Shutdown};

pub trait SignerManagerModule: Send + Sync + 'static {
    /// Every signer's accounts: `{ ok, accounts: [{ id, family, chain?, label?, signer, available, origin? }] }`.
    fn accounts(&self) -> String;
    /// The same accounts, each once with every signer holding it: `{ ok, accounts: [{ key, family,
    /// chain, path, label, wallet, holders }] }`.
    fn roster(&self) -> String;

    fn on_context_ready(&self, _ctx: &RustModuleContext) {}
}

#[allow(dead_code)] // Read by logos-lidl-gen, which generates the emitters.
pub trait SignerManagerModuleEvents {
    /// A signer's accounts changed; re-read `accounts`. The roster here never changes.
    fn accounts_changed(&self, count: i64);
}

include!(concat!(env!("CARGO_MANIFEST_DIR"), "/generated/provider_gen.rs"));

#[derive(Default)]
pub struct SignerManagerModuleImpl;

impl SignerManagerModule for SignerManagerModuleImpl {
    fn accounts(&self) -> String {
        crate::roster::accounts().to_string()
    }

    fn roster(&self) -> String {
        crate::roster::roster().to_string()
    }
}

impl AboutToUnload for SignerManagerModuleImpl {
    fn about_to_unload(&self) -> Shutdown {
        Shutdown::Synchronous
    }
}

#[no_mangle]
pub extern "Rust" fn logos_module_install() {
    logos_install!(SignerManagerModuleImpl);
}
