//! A stand-in signer_manager_module for the wallet app's doctest: `accounts` answers roster.rs.

pub mod roster;

#[cfg(feature = "logos_module")]
mod glue;
