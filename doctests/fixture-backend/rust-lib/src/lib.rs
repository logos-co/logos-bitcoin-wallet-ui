//! A scripted bitcoin_wallet_backend for the wallet app's doctest: the real contract, no wallet
//! core, no node module, no network. sim.rs holds the script.

pub mod sim;

#[cfg(feature = "logos_module")]
mod glue;
