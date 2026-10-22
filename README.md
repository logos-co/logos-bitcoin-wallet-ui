# logos-bitcoin-wallet-ui

`bitcoin_wallet_ui`: the Bitcoin wallet app for Logos Basecamp, built on the Logos Design System.
It talks to `bitcoin_wallet_backend`, whose default custodian it is, and reads the account roster
from `signer_manager_module`. It takes no signing password and
holds no key material: wallets are created and restored in the keys app, each wallet is unlocked
and each open allowed in the Signer app, and every send is approved there.

- **Account selector:** [logos-account-kit](https://github.com/logos-co/logos-account-kit)'s
  picker, vendored in `qml/accountkit`, over `signer_manager.roster()`. It lists each Bitcoin and
  Taproot account once, never once per signer, including accounts never opened in this app. Mainnet
  uses `chain: main`; test networks use `chain: test`. A row shows the account's name, script type and
  number, the wallet it comes from (name and master fingerprint), and every signer holding it, the
  keystore first, never a module. Picking a row selects the holder that already has a wallet on this
  network, else the first holder, which is the keystore's when it holds it; the wallet's database
  follows that holder. From an older manager without `roster()`, the rows are `accounts()`, one per
  holder, as before. A device account (any signer but the keystore) opens while its device is unplugged, since a device signs by
  itself and only sending needs it: its row says "Keycard not connected", with one line on what
  signing needs (a card in a reader or a Keycard Shell, and applet 4.0 for Taproot), and Send says
  the same. A failure while it is unplugged says to connect it, and can be asked again. An
  unavailable keystore account stays visible but cannot be selected. Names and availability refresh
  on `accounts_changed`, manual refresh and periodic reconciliation. A failed roster read keeps the
  current identity visible and disables selection until a successful refresh. **Manage in Keystore**
  raises `evm.accounts.manage` for creation, restoration and management. One wallet is open at a
  time: while one is open, opening or closing, the picker is locked on it and **Open** is disabled
  ("Close this wallet to open another."), and the backend refuses an open as well. Once it has
  closed the picker unlocks with that account still selected. Selecting an entry only changes the
  choice; nothing opens until **Open** is pressed. Dropdown entries have consistent hover highlights.
- **Open an account:** select it in the picker, then press **Open**. The backend's
  `open_wallet` answers a job, and while `wallet_status` carries an `openHandle` the app raises
  `logos.unlock` with `{ openHandle }` and shows "Waiting for the Signer app", with Ask again and
  Cancel. The Signer app unlocks the wallet first if it is locked, then asks to allow the open.
  Cancel closes the wallet, which withdraws the open.
- **Locked wallets:** a wallet still locked in the Signer app offers no accounts. The app reads the
  signer manager's `wallets()` and shows the account kit's `LockedBanner` above the picker; its
  Unlock raises `logos.unlock` with `{ seeds }`. The manager's `wallets_changed` and `wallets_locked`
  read the accounts and the wallets again.
- **An unplugged device** says "sending needs the device" only when no other holder of the account
  (the keystore, a connected device, a QR wallet) can sign.
  - A network picked while the wallet closes waits for the close: "Switching to X when the wallet
    has closed" (`set_active_network`'s `pending`, also in `list_networks`). A refusal says why
    (`wallet_open`, `send_open` or `busy`). An open the backend answers `busy` meanwhile is asked
    again once the switch applies, so it never opens on the old network.
- **Home:** the confirmed balance, then rows for payments waiting for the wallet's chain, pending
  payments with the source that reported them, sent transactions not yet confirmed (with Speed
  up), mined coins not yet mature, and coins too small to spend at today's fee rate. A busy read
  is "not read": the last read stays, and an empty amount shows as a dash, never as zero.
  - The sync line gives the chain authority's height and tip age, and names the authority:
    "Kyoto · N peers", "Your node" or "Servers' headers". It never says "Synchronized" when no
    source agrees with the wallet's chain, nor when the tip is older than an hour; it says "No
    source agrees" or "Stalled" instead. Regtest reads "Local chain". A pruned node's gap reads
    "Older blocks via <source>", or a notice while nothing can scan it. Until the open's first
    round of asking the chain's sources ends (`authority.asked` false), last session's chain reads
    "Connecting to the chain's sources… · last known block N", never "No source agrees": the chip,
    the authority line and the sources badge wait for that answer too. While the chain's headers
    come in (`authority.headers`), it reads "Reading the chain's headers… 84,000 of 157,000", or
    "… block 6,000" under Kyoto, whose peers' tip isn't known, and the chip "Headers 53%"; the
    server sending them counts as agreeing.
  - A wallet restored without a birthday (`needsBirthday`) asks for one: a day, or "I don't know"
    (`set_birthday`, a job; `{ height: 0 }` scans from where the wallet's kind of address began).
    A refusal, such as a day after its first payment, shows with the core's reason; while
    `rescanFrom` holds, Home reads "Rescanning from block H", with a share only under Kyoto.
  - Source alerts show as a banner above the tabs; Kyoto naming a chain the checks refuse
    (`authority_suspect`) has a banner of its own.
  - An enabled source reporting `Proxy server unreachable` shows a Tor setup notice with the
    configured SOCKS address and a connection-check button. A peerless chain routed entirely
    through Tor reads "Tor unavailable" instead of "Connecting". Working peers and direct/local
    chain sources keep their own status. A successful health probe clears the notice.
  - Payments a server reported below where the wallet's chain starts (history state `unchecked`,
    `balances.unchecked`) show apart from the confirmed balance, as "Reported, not checked", and
    in Activity as "Reported by X, not checked", never as confirmed. The core leaves `reportedBy`
    empty on them, so X is the source of the `unchecked_anchor` alert when one source raised it.
    That alert has a banner of its own, whose "Set an earlier birthday" lets Kyoto check them; it
    goes once a read says nothing is unchecked.
  - A scan from the birthday started over wider (`kyoto.rescans`, `node.rescans`, by the
    authority's kind) reads "Rescanning with a wider address range (pass N)".
  - Coins found beyond the gap limit (`balances.beyondGap`: `count`, `sat`, `confirmedSat`) show on
    their own line, "Found beyond your N-address gap limit", outside the confirmed balance, with an
    info button: they are yours and spendable, wallets with a gap limit of N won't show them, and
    raising it makes them part of the normal balance. What Send can spend counts their confirmed
    part.
- **Send:** an address or a BIP21 URI, checked as you type with `address_valid`; the amount in BTC
  or sats (a URI's amount fills it); fast, normal or slow from `fee_rates`, or a custom sat/vB
  rate; and Send max, which takes coins found beyond the gap limit too. The presets need an
  estimate: while `fee_rates` has none (Kyoto alone) Send says "Fee estimate not available
  yet" and takes a rate of your own. Every level the same reads "The network is quiet: every speed
  costs N sat/vB", with the source the estimate came from, or "X's mempool" when the core read it
  off that server's mempool (`basis: "mempool"`). A review whose inputs
  include such coins (the `beyond_gap_inputs` warning) says so in one line.
  - An amount below the address's dust limit (`address_valid`'s `dustSat`: 294 sats native segwit,
    330 taproot) reads "The smallest amount this address can receive is 294 sats." under the
    amount, and Review stays off. So does Send max when the spendable coins less a one-coin fee are
    below it. A send the core refuses as dust (`errorCode` `dust`) says "The amount is too small for
    this address" with the core's sentence, never the library's text.
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
  drawn as rectangles. Copy the address or the payment request. An open shows the first unused
  address (`current_address`) and reveals none. New address at the gap limit (`fresh` false) keeps
  showing the first unused one and says so: "You already have N unused addresses…", with the gap
  limit setting as the way to more.
- **Activity:** one row per transaction saying what it was for: "−X · fee F", "X to yourself ·
  fee F", "N coins combined · fee F", "Fee raised to F" and "+X". Each shows its state, and an
  unconfirmed send has Speed up (`request_fee_bump`). Details list the addresses paid, what it
  replaces or was replaced by, the source that reported a pending payment, its block, the later
  transaction that confirms it (`confirmedVia`) and the txid.
  A payment a reorg moved (`lastReorg.moved`) reads "re-anchored at height H", and its details name
  the new block. A row found beyond the gap limit (`beyondGap`) carries a quiet "Beyond the gap
  limit".
- **Settings:** the wallet (with where its chain starts, `authority.base`), its public descriptors
  behind a privacy warning, Close wallet, and the sources pane, which also opens from the Open a
  wallet screen.
  - The address gap limit (`wallet_status.gapLimit`, 20 by default): a restore stops after this
    many unused addresses in a row, and coins past it are invisible to wallets with the same
    limit. `set_gap_limit` takes 20 to 1000 as a job; raising it asks first, since the wallet
    rescans from its birthday and downloads more, and an enabled history server is asked about
    more addresses. The rescan shows on Home as a birthday's does; refusals (`invalid`, `busy`)
    are said in plain words.
  - Sources groups **Public service** by **Bitcoin Core RPC**, **Electrum** and **Esplora**,
    followed by **Your own node**. Public RPC endpoints appear in the RPC group; local-network
    endpoints appear with the bundled node. PublicNode is built in for mainnet, disabled until
    selected, with Tor off. Add an HTTP/HTTPS endpoint with optional RPC basic
    authentication, check its network and block-filter capability, then choose **Use only this**.
    This atomically disables the other sources. RPC starts with Tor off; Details offers Tor and
    certificate pinning. The wallet checks headers and scans payments locally, using block filters
    where available and full blocks otherwise. Full-block restores can be very slow.
  - Compact provider rows show Enabled/Disabled, route and health, even while settings are
    locked. Details reveals History, optional Tor, certificates and removal. Expansion survives
    health refreshes. History and Tor changes apply without extra privacy confirmations.
  - One short public-service disclosure explains that direct connections reveal the IP and
    wallet-related requests. Running your own node, with public services disabled, is presented
    as the privacy-focused option. The help popup explains connection types and providers.
  - **Use without Tor**, under Electrum, selects a regular TLS server. `useDirectSource` enables
    it with History on and Tor off and disables every other source in one `set_sources` call
    against a freshly read list. Pins and credentials remain intact; a wallet must be closed.
  - **Advanced settings** holds the Tor proxy, custom-server form, Kyoto peers, operator
    diagnostics and connection record. Tor must run separately; onion addresses require it.
    Kyoto does not automatically hand the chain to Electrum when it cannot connect. Enabled
    sources are summarized above the groups, including Kyoto when Advanced is collapsed.
  - No-chain, unreachable-proxy and source-health errors remain visible. A server reached in
    plain text outside Tor is marked Not encrypted. One-operator diagnostics live in Advanced.
  - Under Kyoto, the install's peer book (`peer_list`'s `counts`): "N known peers: M from the
    signed list, K learned · L worked in the last 30 days", whether the signed list is provisional
    or signed with a test key, and how it grows: the wallet learns working peers from the ones it
    uses, and asks a few of Bitcoin Core's built-in onion nodes for more if too few work. Your own
    peers (`set_own_peers`, at most 64) replace all of these, so Kyoto connects to them alone,
    directly on your network, otherwise through Tor; "Use the known peers again" sends `[]`.
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

Signing secrets never cross the view's interface (`src/bitcoin_wallet_ui.rep`). CI keeps the
signing-secret tripwire and permits only the masked RPC service password field. Optional RPC
credentials are submitted to the node module, never returned as view properties, and the field
is cleared on submission. They authenticate a node service, not a wallet or signer. The descriptors
are a SLOT's return value, shown on Settings and dropped when it is left.

## The backend's contract

`contracts/bitcoin_wallet_backend.lidl` is bitcoin_wallet_backend's published LIDL contract, named
by `dependency_overrides` in `metadata.json`: the generated client comes from it, so the app builds
without the backend's repository. Replace it with the backend's `nix build .#lidl` output when its
interface changes; this copy is from logos-bitcoin-wallet-backend 95b8f0c.
`contracts/signer_manager_module.lidl` supplies the account-read API (`accounts`, `roster`) and
the `accounts_changed` event; only public identity fields are copied into the view's account roster.
This copy is logos-signer-manager-module cd661b5's `nix build .#lidl` (#11, roster).

## Intents

The app **uses** `evm.accounts.manage` (Keystore account management), `logos.unlock` (the Signer
app: unlock a wallet, allow an open) and `evm.signing.approve` (the signer app). Their answers are advisory: `wallet_status` and
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
  nothing behind it, and `doctests/fixture-manager`, a `signer_manager_module` whose `accounts`
  and `roster` answer a keystore wallet on each chain and a Keycard account with no card inserted: every flow,
  to every send outcome, a birthday refused and set, change added to the fee, a reorg, Kyoto as the
  authority and a chain it names that is refused, a TLS server's certificate pinned, a Kyoto peer of
  your own, a network switch queued behind a close with an open refused until it applies, the
  account picker locked on an open wallet with another account's open refused, a payment
  reported below the chain's start until an earlier birthday checks it (with a wider pass), one peer
  deciding the chain on testnet4, and a coin past the 20-address gap limit that a small send spends
  and a gap limit of 30 takes into the balance. Each open shows last session's chain as connecting for
  its first 4 s, and the first open on a network then reads the chain's headers for 4 s; reopens show the first unused address again; testnet4's wallet already holds 20 unused
  ones, so New address there says so; Kyoto on testnet4 has no fee estimate and Esplora's under Kyoto
  on signet is a quiet network's. An amount below the address's dust limit keeps Review off. A send's
  fate is picked by its amount; the header of `sim.rs` says how.
- `real-backend-open.test.yaml` runs against the real backend, wallet core, node module, signer
  manager and keystore: the node module's sources, certificate pin and curated Kyoto list with a
  peer of your own, and an open up to the keys app's handle, withdrawn. Nothing can approve an open there, so sends are not reached.

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
started on regtest from the node app) as the chain authority. The core takes the node module's
routes whenever it routes anything on regtest, so the driver switches off the node module's Kyoto,
its only regtest default, before each open: the chain's sources then come from the core's
`regtest.json`. The Kyoto spec then restores twice:
once with no day in the keys app, so the wallet asks for its birthday and gets it in the wallet
app; once with Blockstream's electrs as the only server and a `regtest.json` checkpoint above the
first two payments, which it reports below the chain's start. A front that answers no block header
(`doctests/e2e/esplora_front.py`) keeps the core from linking them there, so they stay unchecked
until the banner's earlier birthday lets Kyoto check them. That restore opens with open_wallet's own birthday (the app
takes no block height, and a regtest day names none) and runs on Linux and macOS only. Last, user
A's wallet pays itself at receive index 72 while its gap limit is 100; at 20 the coin shows apart
and labelled, a raise to 80 takes it into the balance, and a reopen keeps 80.

On Windows the three e2e specs run as their emitted Windows leg (`doctest emit-smoke <spec>
--platform windows`) under Git Bash, with the Windows builds staged under `e2e/build` and the
chain on a Linux machine of the LAN behind logos-bitcoin-windows-tests' chainctl: `E2E_CHAIN_URL`
names it and `E2E_CHAIN_HOST` is the address the wallet dials. That repository's
`winvm/e2e-run.sh` runs one spec.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).
