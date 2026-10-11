# logos-bitcoin-wallet-ui

`bitcoin_wallet_ui`: the Bitcoin wallet app for Logos Basecamp, built on the Logos Design System.
It talks only to `bitcoin_wallet_backend`, whose default custodian it is. It takes no password and
holds no key material: wallets are opened, created and restored in the keys app, and every send
is approved in the signer app.

- **Open a wallet:** pick native segwit or taproot, or a wallet opened before. The backend's
  `open_wallet` answers a job, and while `wallet_status` carries an `openHandle` the app raises
  `keystore.accounts.open` with `{ handle }` and shows "Waiting for the keys app", with Ask again and
  Cancel. Cancel closes the wallet, which withdraws the open.
- **Home:** the confirmed balance, then rows for payments waiting for the wallet's chain, pending
  payments with the source that reported them, sent transactions not yet confirmed (with Speed
  up), mined coins not yet mature, and coins too small to spend at today's fee rate. A busy read
  is "not read": the last read stays, and an empty amount shows as a dash, never as zero.
  - The sync line gives the chain authority's height and tip age. It never says "Synchronized"
    when no source agrees with the wallet's chain, nor when the tip is older than an hour; it
    says "No source agrees" or "Stalled" instead. Regtest reads "Local chain".
  - Source alerts show as a banner above the tabs.
- **Send:** an address or a BIP21 URI, checked as you type with `address_valid`; the amount in BTC
  or sats (a URI's amount fills it); fast, normal or slow from `fee_rates`, or a custom sat/vB
  rate; and Send max.
  - Review shows what the form says. Approve in Signer calls `request_send`; once `send_status`
    carries an `approvalHandle` the app raises `evm.signing.approve` with `{ handle }`. The review
    then shows the wallet's own summary: recipients, change, fee, what leaves the wallet, and
    warnings, among them change too small to spend.
  - It follows the send to a final state. Expired (`errorCode` `expired`) offers Ask again, the
    same request once more; rejected, cancelled and the other codes say what happened. An unknown
    outcome offers Rebroadcast, Speed up and Forget this payment (`abandon_send`, behind a
    confirmation), and a banner stays above the tabs until it is settled or forgotten; a review is
    refused meanwhile. A forgotten payment shows as Forgotten, with the backend's note.
  - Done on a settled send is local: the backend refuses to cancel a final send, and such a
    refusal must not leave the form wedged.
- **Receive:** a fresh address per request, with a BIP21 QR (an optional amount goes in the URI)
  drawn as rectangles. Copy the address or the payment request.
- **Activity:** one row per transaction saying what it was for: "−X · fee F", "X to yourself ·
  fee F", "N coins combined · fee F", "Fee raised to F" and "+X". Each shows its state, and an
  unconfirmed send has Speed up (`request_fee_bump`). Details list the addresses paid, what it
  replaces or was replaced by, the source that reported a pending payment, and the txid.
- **Settings:** the wallet, its public descriptors behind a privacy warning, Close wallet, and
  the sources pane, which also opens from the Open a wallet screen.
  - Each source has Use, History and Tor switches (`set_source`). Turning History on asks first:
    the server will learn every address. Turning Tor off asks first, in that row, and says what
    the source would see.
  - The info button says what a second operator adds, claiming only what the design does.
    Notices name the sources reached without Tor, and say when Kyoto is off and the Electrum
    servers of one operator alone decide the chain.
  - Your own servers, added by address; the Tor proxy; the exposure record.
  - While a wallet is open, opening or closing, these settings show but do not change. A suspect
    mark can still be cleared.

## Secrets

None cross the view's interface (`src/bitcoin_wallet_ui.rep`), in either direction. CI checks that
no PROP and no SLOT is named like a secret, with positive controls, and that the view has no
password field. The descriptors are a SLOT's return value, shown on Settings and dropped when it
is left.

## Intents

The app **uses** `keystore.accounts.open` (the keys app, `evm_keystore_ui`) and
`evm.signing.approve` (the signer app). Their answers are advisory: `wallet_status` and
`send_status` settle what happened. `unavailable` is shown with what to do by hand.

## Checks

```bash
nix build .#lgx
qmllint -I <qt qml> -I <logos-design-system>/src/qml -W 0 --unqualified disable qml/*.qml
QT_QPA_PLATFORM=offscreen qml -I <qt qml> -I <logos-design-system>/src/qml ci/construct.qml   # VIEW-READY
QT_QPA_PLATFORM=offscreen qml -I <qt qml> -I <logos-design-system>/src/qml ci/states.qml      # STATES-OK
doctests/run.sh
```

`ci/states.qml` drives the pure sync, send and activity functions through every state a live
wallet will not hold on demand, then renders the view against a fake backend.

The doctest opens the app in Basecamp's standalone mode with `doctests/fixture-backend`: a scripted
`bitcoin_wallet_backend` with the real backend's contract (its trait is copied verbatim) and
nothing behind it. A send's fate is picked by its amount; the fixture's header says how.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).
