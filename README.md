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
  - The sync line gives the chain authority's height and tip age, and names the authority:
    "Kyoto · N peers", "Your node" or "Servers' headers". It never says "Synchronized" when no
    source agrees with the wallet's chain, nor when the tip is older than an hour; it says "No
    source agrees" or "Stalled" instead. Regtest reads "Local chain". A pruned node's gap reads
    "Older blocks via <source>", or a notice while nothing can scan it.
  - A wallet restored without a birthday (`needsBirthday`) asks for one: a day, or "I don't know"
    (`set_birthday`, a job; `{ height: 0 }` scans from where the wallet's kind of address began).
    A refusal, such as a day after its first payment, shows with the core's reason; while
    `rescanFrom` holds, Home reads "Rescanning from block H", with a share only under Kyoto.
  - Source alerts show as a banner above the tabs; Kyoto naming a chain the checks refuse
    (`authority_suspect`) has a banner of its own.
- **Send:** an address or a BIP21 URI, checked as you type with `address_valid`; the amount in BTC
  or sats (a URI's amount fills it); fast, normal or slow from `fee_rates`, or a custom sat/vB
  rate; and Send max.
  - Review shows what the form says. Approve in Signer calls `request_send`; once `send_status`
    carries an `approvalHandle` the app raises `evm.signing.approve` with `{ handle }`. The review
    then shows the wallet's own summary: recipients, change, fee, what leaves the wallet, and
    warnings. Change too small to spend offers "Add it to the fee (+X sats)": the send is withdrawn
    and asked again with `smallChangeToFee`, and the review then says the change went to the fee.
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
  replaces or was replaced by, the source that reported a pending payment, its block and the txid.
  A payment a reorg moved (`lastReorg.moved`) reads "re-anchored at height H", and its details name
  the new block.
- **Settings:** the wallet, its public descriptors behind a privacy warning, Close wallet, and
  the sources pane, which also opens from the Open a wallet screen.
  - Each source has Use, History and Tor switches (`set_source`). Turning History on asks first:
    the server will learn every address. Turning Tor off asks first, in that row, and says what
    the source would see.
  - The info button says what a second operator adds, claiming only what the design does.
    Notices name the sources reached without Tor, and say when Kyoto is off and the Electrum
    servers of one operator alone decide the chain.
  - Your own servers, added by address; the Tor proxy; the exposure record. A server reached in
    plain text outside Tor is marked "Not encrypted".
  - A server you add is probed (`probe`), and a TLS certificate that no authority this computer
    trusts shows its subject, issuer, validity and SHA-256 fingerprint, with "Trust this
    certificate", which pins it (`set_source` `certSha256`). A pinned server shows its pin, with
    "Remove pin". Pins are locked while a wallet is open, like every source setting.
  - With a wallet open, the sources badge applies the node module's rules to the wallet's own
    view of its sources (`source_health`'s `wallet`), and servers it uses that the list lacks,
    such as a test chain's own, are listed with their state.
  - An unknown send names the source last tried, never one it was "broadcast through".
  - While a wallet is open, opening or closing, these settings show but do not change. A suspect
    mark can still be cleared.

## Secrets

None cross the view's interface (`src/bitcoin_wallet_ui.rep`), in either direction. CI checks that
no PROP and no SLOT is named like a secret, with positive controls, and that the view has no
password field. The descriptors are a SLOT's return value, shown on Settings and dropped when it
is left.

## The backend's contract

`contracts/bitcoin_wallet_backend.lidl` is bitcoin_wallet_backend's published LIDL contract, named
by `dependency_overrides` in `metadata.json`: the generated client comes from it, so the app builds
without the backend's repository. Replace it with the backend's `nix build .#lidl` output when its
interface changes; this copy is from logos-bitcoin-wallet-backend 13566b6.

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
doctests/run.sh                                                                # all doctests
SPECS=basecamp-e2e OUT=/a/big/disk doctests/run.sh                             # the full-Basecamp e2e
SPECS=basecamp-e2e-kyoto OUT=/a/big/disk2 doctests/run.sh                      # ...with Kyoto deciding the chain
SPECS=basecamp-e2e-node OUT=/a/big/disk3 doctests/run.sh                       # ...with the local node
```

`ci/states.qml` drives the pure sync, send and activity functions through every state a live
wallet will not hold on demand, then renders the view against a fake backend.

Two doctests open the app in Basecamp's standalone mode, offscreen:

- `wallet-ui-app.test.yaml` runs against `doctests/fixture-backend`, a scripted
  `bitcoin_wallet_backend` with the real backend's contract (its trait is copied verbatim) and
  nothing behind it: every flow, to every send outcome, a birthday refused and set, change added
  to the fee, a reorg, Kyoto as the authority and a chain it names that is refused, and a TLS
  server's certificate pinned. A send's fate is picked by its amount; the header of `sim.rs` says
  how.
- `real-backend-open.test.yaml` runs against the real backend, wallet core, node module, signer
  manager and keystore: the node module's sources, and an open up to the keys app's handle,
  withdrawn. Nothing can approve an open there, so sends are not reached.

`basecamp-e2e.test.yaml` runs the app in the full Basecamp bundle beside the real keys app and
signer app, on a regtest chain from the wallet core's chain script (bitcoind, two electrs and a
fork node): create and open in the keys app, receive, a send left unapproved until it expires and
then asked again, approvals, a fee bump, a rejection, a reorg, a restore from the phrase in a fresh
user dir, and two unknown outcomes, one rebroadcast and one forgotten. `doctests/e2e/drive.py`
drives the apps over Basecamp's QML inspector and the chain over the script, one phase per step,
since the phrase, addresses and txids can't be written into a static test. It generates its own
test passwords, and each Basecamp run gets its own HOME and user dir. `basecamp-e2e-kyoto` and
`basecamp-e2e-node` run open, receive, send, confirm and a reorg with Kyoto (the chain's three
filter-serving nodes as its peers, quorum 2) and with the local node (bitcoind_module and its app,
started on regtest from the node app) as the chain authority.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).
