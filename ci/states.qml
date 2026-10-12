import QtQuick

// Drives the view through states a live wallet will not hold on demand, then renders it against a
// fake backend. Prints STATES-OK, or STATES-FAIL with the cases that disagree.
Item {
    id: scene
    width: 1280; height: 900

    // The host injects `logos`; the view finds this one by name up its context chain.
    property QtObject logos: QtObject {
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        property var requests: []
        property var lastCallback: null
        function module(name) { return fake }
        function isViewModuleReady(name) { return true }
        function request(intent, params, cb) {
            requests = requests.concat([{ intent: intent, params: params }])
            lastCallback = cb
        }
        function respond(id, ok, result, error) {}
        function watch(reply, ok, err) { ok(reply) }
    }

    QtObject {
        id: fake
        property string lastError: ""
        property bool busy: false
        property string pendingJobKind: ""
        property string lastJobJson: ""
        property string statusJson: ""
        property string networksJson: ""
        property string walletsJson: "[]"
        property string balancesJson: ""
        property string historyJson: ""
        property int historyPage: 0
        property string receiveJson: ""
        property string receiveQrJson: ""
        property string feeRatesJson: ""
        property string sourcesJson: ""
        property string healthJson: ""
        property string exposureJson: ""
        property string alertsJson: "[]"
        property string sendRequestId: ""
        property string sendStatusJson: "{}"
        property string sendError: ""
        property string birthdayJson: ""
        property string probeJson: ""
        property string switchJson: ""
        property string openQueuedJson: ""
        property string peerListJson: ""
        property string gapLimitJson: ""
        property var calls: []
        function note(name, args) { calls = calls.concat([[name].concat(args)]) }
        function last(name) {
            for (var i = calls.length - 1; i >= 0; i--) if (calls[i][0] === name) return calls[i]
            return null
        }
        function count(name) { return calls.filter(function (c) { return c[0] === name }).length }
        function refresh() {}
        function clearAndRefresh() {}
        function setActiveNetwork(n) { note("setActiveNetwork", [n]) }
        function openWallet(p) { note("openWallet", [p]) }
        function closeWallet() { note("closeWallet", []) }
        function setBirthday(p) { note("setBirthday", [p]) }
        function setGapLimit(p) { note("setGapLimit", [p]) }
        function probeSource(id) { note("probeSource", [id]) }
        function requestSend(r) { note("requestSend", [r]) }
        function requestFeeBump(t, rate) { note("requestFeeBump", [t, rate]) }
        function cancelSend() { note("cancelSend", []) }
        function dismissSend() { note("dismissSend", []); sendRequestId = ""; sendStatusJson = "{}" }
        function rebroadcast() { note("rebroadcast", []) }
        function abandonSend(t) {
            note("abandonSend", [t])
            return JSON.stringify({ ok: true, jobId: "j9", requestId: "s2", txid: t, note: "Abandoned: its coins are free to spend again." })
        }
        function newAddress() { note("newAddress", []) }
        function setReceiveAmount(a) { note("setReceiveAmount", [a]) }
        function addressValid(t) {
            if (t.indexOf("bcrt1q") === 0) return JSON.stringify({ ok: true, valid: true, address: t, type: "p2wpkh" })
            if (t.indexOf("bitcoin:") === 0) return JSON.stringify({ ok: true, valid: true, address: t.slice(8).split("?")[0], type: "p2wpkh", amountSat: "150000" })
            return JSON.stringify({ ok: true, valid: false, reason: "this address is for another network" })
        }
        function refreshHistory() {}
        function showHistoryPage(p) {}
        function dismissAlerts() { alertsJson = "[]" }
        function setSource(id, changes) { note("setSource", [id, changes]); return "" }
        function addSource(a, k, n) { note("addSource", [a, k, n]); return "" }
        function removeSource(id) { note("removeSource", [id]); return "" }
        function setProxy(p) { note("setProxy", [p]); return "" }
        function setOwnPeers(p) { note("setOwnPeers", [p]); return "" }
        function clearSuspect(id) { note("clearSuspect", [id]); return "" }
        function refreshSources() {}
        function descriptors() { return JSON.stringify({ ok: true, external: "wpkh([73c5da0a/84h/1h/0h]tpubD6/0/*)", internal: "wpkh([73c5da0a/84h/1h/0h]tpubD6/1/*)" }) }
    }

    property var bad: []
    function expect(name, got, want) {
        if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want))
    }
    // Finds an object by objectName through items, popups and loaders.
    function find(obj, name, depth) {
        if (!obj || (depth || 0) > 80) return null
        if (obj.objectName === name) return obj
        var kids = []
        if (obj.data) for (var i = 0; i < obj.data.length; i++) kids.push(obj.data[i])
        // A dialog's footer buttons live in its action lists.
        var lists = [obj.leftActions, obj.rightActions]
        for (var l = 0; l < lists.length; l++)
            if (lists[l]) for (var a = 0; a < lists[l].length; a++) kids.push(lists[l][a])
        if (obj.contentItem && kids.indexOf(obj.contentItem) < 0) kids.push(obj.contentItem)
        if (obj.item && kids.indexOf(obj.item) < 0) kids.push(obj.item)
        for (var k = 0; k < kids.length; k++) {
            var r = find(kids[k], name, (depth || 0) + 1)
            if (r) return r
        }
        return null
    }
    function prop(name, p) {
        var o = find(view.item, name, 0)
        return o ? o[p] : "<no " + name + ">"
    }
    function shown(name) { return prop(name, "visible") }
    // The sources pane is in Settings and in a sheet: true when any copy of `name` is visible.
    function findAll(obj, name, depth, out) {
        if (!obj || (depth || 0) > 80) return out
        if (obj.objectName === name) out.push(obj)
        var kids = []
        if (obj.data) for (var i = 0; i < obj.data.length; i++) kids.push(obj.data[i])
        var lists = [obj.leftActions, obj.rightActions]
        for (var l = 0; l < lists.length; l++)
            if (lists[l]) for (var a = 0; a < lists[l].length; a++) kids.push(lists[l][a])
        if (obj.contentItem && kids.indexOf(obj.contentItem) < 0) kids.push(obj.contentItem)
        if (obj.item && kids.indexOf(obj.item) < 0) kids.push(obj.item)
        for (var k = 0; k < kids.length; k++) findAll(kids[k], name, (depth || 0) + 1, out)
        return out
    }
    function shownAny(name) { return findAll(view.item, name, 0, []).some(function (o) { return o.visible === true }) }

    readonly property string syncedMainnet: JSON.stringify({ state: "ready", network: "mainnet", activeNetwork: "mainnet", family: "bitcoin",
        group: "g_test", synced: true, walletTip: 935500, syncPercent: 100, label: "Savings",
        authority: { kind: "electrum_headers", height: 935500, tipAgeSecs: 240, peers: 2 } })

    function pureCases(v) {
        var mainnet = function (extra) {
            var s = { state: "ready", network: "mainnet", synced: true, walletTip: 935500,
                      authority: { kind: "electrum_headers", height: 935500, tipAgeSecs: 240, peers: 2 } }
            for (var k in extra) s[k] = extra[k]
            return s
        }
        var sync = [
            [{ state: "no_wallet" }, ""],
            [{ state: "awaiting_open", openHandle: "sma_1" }, "Waiting for the keys app"],
            [{ state: "opening" }, "Opening the wallet…"],
            [{ state: "closing" }, "Closing…"],
            [{ state: "failed", lastError: "the keystore opened a wallet of another family" }, "Failed: the keystore opened a wallet of another family"],
            [mainnet({ state: "syncing", authority: { height: null, peers: 0 } }), "Connecting to the chain's sources…"],
            [mainnet({ state: "syncing", authority: { height: null, peers: 2 } }), "Reading the chain's headers…"],
            [mainnet({}), "Synchronized · block 935,500, tip 4 min old · Servers' headers"],
            [mainnet({ authority: { kind: "kyoto", height: 935500, tipAgeSecs: 240, peers: 3 } }), "Synchronized · block 935,500, tip 4 min old · Kyoto · 3 peers"],
            [mainnet({ authority: { kind: "kyoto", height: 935500, tipAgeSecs: 240, peers: 1 } }), "Synchronized · block 935,500, tip 4 min old · Kyoto · 1 peer"],
            [mainnet({ authority: { kind: "local_node", height: 935500, tipAgeSecs: 240, peers: 1 } }), "Synchronized · block 935,500, tip 4 min old · Your node"],
            // No agreeing source: the core's own `synced` is not enough.
            [mainnet({ authority: { height: 935500, tipAgeSecs: 240, peers: 0 } }), "No source agrees · block 935,500, tip 4 min old"],
            [mainnet({ authority: { height: 935500, tipAgeSecs: 7300, peers: 0 } }), "No source agrees · block 935,500, tip 2 hours old"],
            // A tip older than an hour is never synchronized.
            [mainnet({ authority: { height: 935500, tipAgeSecs: 3601, peers: 3 } }), "Stalled · block 935,500, tip 1 hour old"],
            [mainnet({ authority: { height: 935500, tipAgeSecs: 200000, peers: 3 } }), "Stalled · block 935,500, tip 2 days old"],
            [mainnet({ state: "syncing", synced: false, walletTip: 900000, syncPercent: 42,
                       authority: { height: 935500, tipAgeSecs: 300, peers: 2 } }), "Syncing 42% · block 900,000 of 935,500"],
            [mainnet({ state: "syncing", synced: false, walletTip: undefined }), "Syncing · the chain is at block 935,500 · Servers' headers"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { height: 150, tipAgeSecs: 9000, peers: 1 } }), "Local chain · block 150"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { kind: "local_node", height: 150, tipAgeSecs: 9000, peers: 1 } }), "Local chain · block 150 · Your node"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { height: 150, tipAgeSecs: 9000, peers: 0 } }), "No source agrees · block 150, tip 2 hours old"],
            [mainnet({ unavailable: true, error: "the wallet core did not answer" }), "The wallet backend is not answering"]
        ]
        for (var i = 0; i < sync.length; i++) expect("sync " + i, v.syncLabel(sync[i][0]), sync[i][1])
        expect("chip synced", v.syncChip(mainnet({})), "Synced · 935,500")
        expect("chip no peers", v.syncChip(mainnet({ authority: { height: 935500, tipAgeSecs: 240, peers: 0 } })), "No sources")
        expect("chip stalled", v.syncChip(mainnet({ authority: { height: 935500, tipAgeSecs: 4000, peers: 2 } })), "Stalled")

        var sends = [
            [{ state: "preparing" }, "live", "Building the transaction…", 0],
            [{ state: "awaiting_approval", approval: "offered", approvalHandle: "smh_1" }, "live", "Approve it in the signer app", 1],
            [{ state: "awaiting_approval", approval: "rendered" }, "live", "The signer app is showing it", 1],
            [{ state: "awaiting_approval", cancelling: true }, "live", "Cancelling…", 1],
            [{ state: "committing" }, "live", "Approved · broadcasting…", 2],
            [{ state: "sent", kind: "send" }, "sent", "Sent", 4],
            [{ state: "sent", kind: "fee_bump" }, "sent", "Fee raised", 4],
            [{ state: "unknown", error: "the transaction may have left" }, "unknown", "The outcome is unknown: it may have left", 2],
            [{ state: "failed", errorCode: "expired", error: "expired: nobody acknowledged the approval within 60 s", summary: {} }, "expired", "Nobody approved it within 60 s", 1],
            [{ state: "failed", error: "expired: nobody acknowledged the approval within 60 s; request the send again" }, "expired", "Nobody approved it within 60 s", 0],
            [{ state: "failed", errorCode: "rejected", error: "anything" }, "rejected", "Rejected in the signer app", 0],
            [{ state: "failed", error: "rejected: the person declined in the signer app" }, "rejected", "Rejected in the signer app", 0],
            [{ state: "cancelled", errorCode: "cancelled", error: "cancelled by bitcoin_wallet_ui" }, "cancelled", "Cancelled", 0],
            [{ state: "failed", errorCode: "insufficient_funds", error: "x" }, "failed", "Not enough confirmed bitcoin for this and its fee", 0],
            [{ state: "failed", errorCode: "no_route", error: "no source is enabled for broadcast" }, "failed", "No source can broadcast it", 0],
            [{ state: "failed", errorCode: "refused", error: "electrum-0 refused the transaction: min relay fee not met" }, "failed", "A source refused the transaction", 0],
            [{ state: "failed", errorCode: "signer_unavailable", error: "x" }, "failed", "The signer could not be reached", 0],
            [{ state: "failed", error: "the wallet's coins changed while the send waited" }, "failed", "The send failed", 0],
            [{ state: "failed", errorCode: "coins_changed", error: "x" }, "failed", "The wallet's coins changed while it waited", 0],
            [{ state: "failed", errorCode: "core_lost", error: "x" }, "failed", "The wallet core stopped answering", 0],
            [{ state: "failed", errorCode: "backend_restarted", error: "x" }, "failed", "The wallet backend restarted", 0],
            [{ state: "failed", errorCode: "no_wallet", error: "the wallet closed before the send was approved" }, "failed", "The wallet closed before it was sent", 0],
            [{ state: "unknown", abandoned: true, offer: [] }, "forgotten", "Forgotten", 2]
        ]
        for (var s = 0; s < sends.length; s++) {
            expect("outcome " + s, v.sendOutcome(sends[s][0]), sends[s][1])
            expect("headline " + s, v.sendHeadline(sends[s][0]), sends[s][2])
            expect("stage " + s, v.sendStage(sends[s][0]), sends[s][3])
        }
        expect("detail refused", v.sendDetail(sends[15][0]), "electrum-0 refused the transaction: min relay fee not met")
        expect("retry expired", v.canRetry(sends[8][0]), true)
        expect("retry coins changed", v.canRetry(sends[18][0]), true)
        expect("retry restarted", v.canRetry(sends[20][0]), true)
        expect("no retry rejected", v.canRetry(sends[10][0]), false)
        expect("no retry refused", v.canRetry(sends[15][0]), false)
        var unknownSend = { state: "unknown", offer: ["rebroadcast", "request_fee_bump", "abandon_send"] }
        expect("offer forget", v.offers(unknownSend, "abandon_send"), true)
        expect("offer nothing once forgotten", v.offers({ state: "unknown", abandoned: true, offer: [] }, "rebroadcast"), false)
        expect("old backend offers", v.offers({ state: "unknown" }, "rebroadcast"), true)
        expect("detail expired", v.sendDetail(sends[8][0]), "The signer app never showed the request, so it expired. Ask again to send it once more.")

        var rows = [
            [{ intent: "send", amountSat: "60000", feeSat: "141" }, "−0.0006 BTC · fee 141 sats"],
            [{ intent: "self", amountSat: "1000000", feeSat: "141" }, "0.01 BTC to yourself · fee 141 sats"],
            [{ intent: "combine", amountSat: "90000", coins: 3, feeSat: "300" }, "3 coins combined · fee 300 sats"],
            [{ intent: "fee_bump", amountSat: "60000", feeSat: "1205" }, "Fee raised to 1,205 sats"],
            [{ intent: "receive", amountSat: "125000000" }, "+1.25 BTC"],
            [{ intent: "send", amountSat: "60000", feeSat: null }, "−0.0006 BTC"]
        ]
        for (var r = 0; r < rows.length; r++) expect("intent " + r, v.intentLine(rows[r][0]), rows[r][1])
        expect("row pending", v.rowState({ state: "pending", reportedBy: "electrum.example" }), "pending · reported by electrum.example")
        expect("row conf", v.rowState({ state: "confirmed", confirmations: 1 }), "1 confirmation")
        expect("row deep", v.rowState({ state: "confirmed", confirmations: 12 }), "confirmed")
        expect("speed up sent", v.canSpeedUp({ state: "sent", intent: "send" }), true)
        expect("no speed up replaced", v.canSpeedUp({ state: "replaced", intent: "send" }), false)
        expect("no speed up receive", v.canSpeedUp({ state: "sent", intent: "receive" }), false)

        expect("sat btc", v.satFromInput("0.0006", "btc"), "60000")
        expect("sat whole", v.satFromInput("1", "btc"), "100000000")
        expect("sat dot", v.satFromInput(".5", "btc"), "50000000")
        expect("sat 9 decimals", v.satFromInput("0.000000001", "btc"), "")
        expect("sat sats", v.satFromInput("1500", "sat"), "1500")
        expect("sat zero", v.satFromInput("0", "sat"), "")
        expect("btc supply", v.btcOf("2100000000000000"), "21000000")
        expect("btc small", v.btcOf(1), "0.00000001")
        expect("group", v.group(935500), "935,500")
        expect("one sat", v.satsText(1), "1 sat")
        expect("request", v.buildRequest("bcrt1qx", "60000", false, 6), { recipients: [{ address: "bcrt1qx", amountSat: "60000" }], feeRate: 6 })
        expect("request max", v.buildRequest("bcrt1qx", "", true, 2), { recipients: [{ address: "bcrt1qx" }], feeRate: 2, sendMax: true })

        // Operators, not hosts, decide whether one operator decides the chain.
        var list = [{ id: "kyoto", kind: "kyoto", use: false }, { id: "a", kind: "electrum", use: true, operator: "Example" },
                    { id: "b", kind: "electrum", use: true, operator: "example" }, { id: "c", kind: "esplora", use: true, operator: "other" }]
        expect("chain servers", v.chainSourcesOf(list).map(function (x) { return x.id }), ["a", "b"])
        expect("chain operators", v.operatorsOf(v.chainSourcesOf(list)), ["Example"])
        list[0].use = true
        expect("chain kyoto", v.chainSourcesOf(list).map(function (x) { return x.id }), ["kyoto"])

        // The open wallet's own view decides the badge; a source not asked yet does not count.
        expect("overall ok", v.walletOverall([{ state: "ok" }, { state: "ok" }, { state: "unknown" }]), "ok")
        expect("overall degraded", v.walletOverall([{ state: "ok" }, { state: "failing" }]), "degraded")
        expect("overall offline", v.walletOverall([{ state: "failing" }, { state: "down" }]), "offline")
        expect("overall suspect", v.walletOverall([{ state: "suspect", suspect: true }, { state: "ok" }]), "degraded")
        expect("overall disagree", v.walletOverall([{ state: "ok", operator: "A", tip: 100 }, { state: "ok", operator: "b", tip: 104 }]), "disagreement")
        expect("overall one operator", v.walletOverall([{ state: "ok", operator: "A", tip: 100 }, { state: "ok", operator: "a", tip: 104 }]), "ok")
        expect("overall not asked", v.walletOverall([{ state: "unknown" }]), "")
        var nodeAt = function (peers) { return { state: "ready", network: "regtest", walletTip: 150,
                                                 authority: { kind: "local_node", height: 150, tipAgeSecs: 30, peers: peers } } }
        expect("your node alone", v.walletOverall([], nodeAt(1)), "ok")
        expect("your node unreachable", v.walletOverall([], nodeAt(0)), "offline")
        expect("kyoto isolated, a server fine", v.walletOverall([{ state: "ok" }],
               { state: "ready", network: "regtest", walletTip: 150, authority: { kind: "kyoto", height: 150, peers: 0 } }), "degraded")
        expect("servers decide", v.walletOverall([], { state: "ready", authority: { kind: "electrum_headers", height: 1, peers: 1 } }), "")
        expect("source line", v.walletSourceLine({ state: "ok", roles: ["chain", "history"], history: true }), "ok · chain, history · history server")
        expect("suspect line", v.walletSourceLine({ state: "suspect", suspect: true, suspectReason: "served invalid headers", error: "x" }), "suspect: served invalid headers")
        expect("failing line", v.walletSourceLine({ state: "failing", roles: ["chain"], error: "connection refused" }), "failing · chain · connection refused")
        expect("plain line", v.walletSourceLine({ state: "ok", roles: ["chain"], encrypted: false }), "ok · chain · not encrypted")

        expect("authority kyoto", v.authorityLine({ authority: { kind: "kyoto", peers: 2 } }), "The chain: Bitcoin peers, through block filters · 2 peers")
        expect("authority node", v.authorityLine({ authority: { kind: "local_node" } }), "The chain: your own node, checked here")
        expect("gap", v.gapBlocks({ from: 100, below: 300 }), "blocks 100–299")
        expect("gap one", v.gapBlocks({ from: 100, below: 101 }), "block 100")
        expect("change to fee", v.warningText({ kind: "change_to_fee", amountSat: "450", costToSpendSat: "680" }),
               "450 sats of change would have cost about 680 sats to spend, so it is part of the fee and no change comes back.")
        expect("fingerprint", v.fingerprint("ab".repeat(32)), Array(33).join("AB:").slice(0, -1))
        expect("fingerprint colons", v.fingerprint("ab:cd"), "AB:CD")
        expect("cert text", v.certText({ certSha256: "0f".repeat(32), subject: "CN=electrum.test", issuer: "CN=electrum.test",
                                          notBefore: "2026-10-11T01:43:03Z", notAfter: "2126-09-17T01:43:03Z", trusted: false }),
               "Subject CN=electrum.test, issued by CN=electrum.test\nValid 2026-10-11 to 2126-09-17\nSHA-256 " + Array(33).join("0F:").slice(0, -1))
        expect("plain text", v.notEncrypted({ id: "x", encrypted: false }), true)
        expect("via your node", v.viaName("local"), "your node")
        expect("via kyoto", v.viaName("kyoto"), "Kyoto's peers")
        expect("via a server", v.viaName("electrum-0"), "electrum-0")
        expect("tls", v.isTls({ url: "ssl://h:50002" }) && v.isTls({ url: "https://h/api" }) && !v.isTls({ url: "tcp://h:50001" }), true)
    }

    // What renders, against the fake backend; each step runs after the previous one settled.
    property var steps: [
        function (v) {
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet4", "signet", "regtest"], active: "regtest" })
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "socks5h://127.0.0.1:9050", walletOpen: false,
                sources: [{ id: "kyoto", kind: "kyoto", url: "p2p://peer-list", operator: "peers", label: "Bitcoin peers", use: false, history: false, tor: true, lan: false, route: "tor" },
                          { id: "electrum.example", kind: "electrum", url: "ssl://electrum.example:50002", operator: "example", label: "Example Electrum", use: true, history: false, tor: true, lan: false, route: "tor" },
                          { id: "esplora.example", kind: "esplora", url: "https://esplora.example/api", operator: "example", label: "Example Esplora", use: true, history: false, tor: true, lan: false, route: "tor" }],
                exposes: [], withoutTor: [], crossCheck: false })
        },
        function (v) {
            expect("open page", shown("openPage"), true)
            expect("form", shown("openForm"), true)
            expect("no tabs", shown("walletTabs"), false)
            expect("status line", prop("statusLine", "text"), "No wallet open")
            expect("network chip", prop("networkChip", "text"), "regtest")
            expect("no password field", find(view.item, "openPasswordField", 0), null)
            find(view.item, "familyTaproot", 0).clicked()
            find(view.item, "openWalletButton", 0).clicked()
            expect("open asked", fake.last("openWallet"), ["openWallet", JSON.stringify({ family: "bitcoin_taproot" })])
            fake.pendingJobKind = "open"
            fake.busy = true
            fake.statusJson = JSON.stringify({ state: "awaiting_open", network: "regtest", activeNetwork: "regtest", openHandle: "sma_t1" })
        },
        function (v) {
            expect("keys panel", shown("keysWaitPanel"), true)
            expect("keys title", prop("keysWaitTitle", "text"), "Waiting for the keys app")
            expect("form hidden", shown("openForm"), false)
            var asked = logos.requests.filter(function (q) { return q.intent === "keystore.accounts.open" })
            expect("keys intent", asked.length === 1 ? asked[0].params.handle : asked.length, "sma_t1")
            logos.lastCallback({ ok: false, error: "unavailable" })
            fake.statusJson = JSON.stringify({ state: "awaiting_open", network: "regtest", activeNetwork: "regtest", openHandle: "sma_t1", authority: {} })
        },
        function (v) {
            expect("keys asked once", logos.requests.filter(function (q) { return q.intent === "keystore.accounts.open" }).length, 1)
            expect("keys note", String(prop("keysNote", "text")).indexOf("The keys app is not installed") === 0, true)
            find(view.item, "cancelOpenButton", 0).clicked()
            expect("cancel closes", fake.count("closeWallet"), 1)
            fake.pendingJobKind = ""
            fake.busy = false
            fake.statusJson = scene.syncedMainnet
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "125000000", confirmedBtc: "1.25000000", waiting: "50000", pending: "30000",
                                                 sent: "0", immature: "0", tooSmall: { count: 2, sat: "540", btc: "0.00000540" } })
            fake.feeRatesJson = JSON.stringify({ fast: 12, normal: 6, slow: 2, minimum: 1, sources: ["esplora.example"] })
            fake.historyJson = JSON.stringify({ page: 0, pageSize: 50, total: 3, rows: [
                { txid: "aa".repeat(32), intent: "receive", amountSat: "30000", state: "pending", reportedBy: "electrum.example", confirmations: 0 },
                { txid: "bb".repeat(32), intent: "send", amountSat: "60000", feeSat: "141", state: "sent", counterparties: ["bcrt1qpay"], confirmations: 0 },
                { txid: "cc".repeat(32), intent: "receive", amountSat: "125000000", state: "confirmed", height: 100, confirmations: 50 }] })
        },
        function (v) {
            expect("tabs", shown("walletTabs"), true)
            expect("synced line", prop("syncLine", "text"), "Synchronized · block 935,500, tip 4 min old · Servers' headers")
            expect("confirmed", prop("confirmedCard", "value"), "1.25 BTC")
            expect("waiting row", shown("waitingRow"), true)
            expect("pending row", shown("pendingRow"), true)
            expect("too small row", prop("tooSmallRowAmount", "text"), "2 coins, 0.0000054 BTC")
            expect("sent row", shown("sentRow"), true)
            expect("home speed up", shown("homeSpeedUp_" + "bb".repeat(32)), true)
            fake.healthJson = JSON.stringify({ overall: "offline", sources: [], wallet: { sources: [
                { id: "regtest-0", url: "tcp://127.0.0.1:61701", state: "ok", suspect: false, roles: ["chain", "history"], history: true },
                { id: "regtest-1", url: "tcp://127.0.0.1:61711", state: "ok", suspect: false, roles: ["chain"] }] } })
        },
        function (v) {
            expect("badge from the open wallet's sources", prop("healthBadge", "text"), "Sources OK")
            expect("wallet's own servers", v.walletOnlySources.map(function (s) { return s.id }), ["regtest-0", "regtest-1"])
            expect("a server's line, through its delegate", prop("walletSourceState_regtest-0", "text"), "ok · chain, history · history server")
            fake.healthJson = ""
            var st = JSON.parse(scene.syncedMainnet)
            st.authority.peers = 0
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("rendered: no peers is never synchronized", prop("syncLine", "text"), "No source agrees · block 935,500, tip 4 min old · Servers' headers")
            fake.statusJson = scene.syncedMainnet
            v.selectTab(1)
            find(view.item, "sendRecipientField", 0).text = "bcrt1qrecipient"
            v.checkRecipient()
            find(view.item, "sendAmountField", 0).text = "0.0006"
        },
        function (v) {
            expect("recipient badge", prop("recipientBadge", "text"), "native segwit")
            expect("amount note", prop("amountNote", "text"), "= 60,000 sats")
            expect("can review", prop("reviewButton", "enabled"), true)
            v.review()
        },
        function (v) {
            expect("draft pane", shown("reviewDraftPane"), true)
            expect("draft amount", prop("draftAmount", "text"), "0.0006 BTC (60,000 sats)")
            expect("draft fee", prop("draftFee", "text"), "6 sat/vB, about 846 sats for a payment from one coin")
            find(view.item, "approveInSignerButton", 0).clicked()
            expect("request", fake.last("requestSend"), ["requestSend", JSON.stringify({ recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], feeRate: 6 })])
            fake.sendRequestId = "s1"
            fake.sendStatusJson = JSON.stringify({ requestId: "s1", kind: "send", state: "awaiting_approval", requester: "bitcoin_wallet_ui",
                approvalHandle: "smh_1", approval: "offered",
                summary: { recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], change: [{ address: "bcrt1qchange", amountSat: "400" }],
                           inputs: 1, inputSat: "61000", feeSat: "600", feeRate: 6, vsize: 141, totalSat: "60600",
                           warnings: [{ kind: "change_too_small", amountSat: "400", costToSpendSat: "408" }] } })
        },
        function (v) {
            var asked = logos.requests.filter(function (q) { return q.intent === "evm.signing.approve" })
            expect("signer intent", asked.length === 1 ? asked[0].params.handle : asked.length, "smh_1")
            expect("lane", prop("sendStageLane", "currentIndex"), 1)
            expect("headline", prop("sendHeadline", "text"), "Approve it in the signer app")
            expect("summary fee", prop("summaryFee", "text"), "600 sats · 6 sat/vB · 141 vB")
            expect("change warning", shown("changeTooSmallNotice"), true)
            expect("cancel offered", shown("cancelSendButton"), true)
            logos.lastCallback({ ok: false, error: "unavailable" })
            fake.sendStatusJson = JSON.stringify({ requestId: "s1", kind: "send", state: "failed", errorCode: "expired", requester: "bitcoin_wallet_ui",
                error: "expired: nobody acknowledged the approval within 60 s; request the send again", summary: { recipients: [], change: [] } })
        },
        function (v) {
            expect("expired headline", prop("sendHeadline", "text"), "Nobody approved it within 60 s")
            expect("ask again", shown("askAgainButton"), true)
            expect("done", shown("doneSendButton"), true)
            find(view.item, "askAgainButton", 0).clicked()
            expect("asked again", fake.count("requestSend"), 2)
            expect("same request", fake.last("requestSend")[1], JSON.stringify({ recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], feeRate: 6 }))
            fake.sendRequestId = "s2"
            fake.sendStatusJson = JSON.stringify({ requestId: "s2", kind: "send", state: "unknown", requester: "bitcoin_wallet_ui", txid: "dd".repeat(32),
                broadcast: "unknown", via: "electrum.example", error: "the transaction may have left", offer: ["rebroadcast", "request_fee_bump", "abandon_send"] })
        },
        function (v) {
            expect("unknown banner", shown("sendUnknownBanner"), true)
            expect("rebroadcast", shown("rebroadcastButton"), true)
            expect("speed up unknown", shown("speedUpUnknownButton"), true)
            expect("forget", shown("forgetPaymentButton"), true)
            expect("review blocked", prop("reviewButton", "enabled"), false)
            expect("unknown never claims a broadcast", prop("sendVia", "text"), "Last tried: electrum.example, which may or may not have taken it")
            find(view.item, "rebroadcastButton", 0).clicked()
            expect("rebroadcast called", fake.count("rebroadcast"), 1)
            find(view.item, "forgetPaymentButton", 0).clicked()
        },
        function (v) {
            expect("forget asks first", prop("forgetSheet", "visible"), true)
            expect("forget not yet", fake.count("abandonSend"), 0)
            find(view.item, "confirmForgetButton", 0).clicked()
            expect("forgotten", fake.last("abandonSend"), ["abandonSend", "dd".repeat(32)])
            // The send stays unknown, abandoned, and offers nothing more.
            fake.sendStatusJson = JSON.stringify({ requestId: "s2", kind: "send", state: "unknown", abandoned: true, offer: [], requester: "bitcoin_wallet_ui",
                txid: "dd".repeat(32), broadcast: "unknown", error: "the transaction may have left" })
        },
        function (v) {
            expect("forgotten headline", prop("sendHeadline", "text"), "Forgotten")
            expect("forget note", prop("forgetNote", "text"), "Abandoned: its coins are free to spend again.")
            expect("no unknown banner once forgotten", shown("sendUnknownBanner"), false)
            expect("no rebroadcast once forgotten", shown("rebroadcastButton"), false)
            expect("no forget twice", shown("forgetPaymentButton"), false)
            expect("review free again", prop("reviewButton", "enabled"), true)
            fake.sendStatusJson = JSON.stringify({ requestId: "s2", kind: "send", state: "failed", errorCode: "rejected", requester: "bitcoin_wallet_ui", error: "rejected" })
        },
        function (v) {
            expect("rejected", prop("sendHeadline", "text"), "Rejected in the signer app")
            var cancels = fake.count("cancelSend")
            find(view.item, "doneSendButton", 0).clicked()
            // Done on a settled send is local: no cancel the backend would refuse.
            expect("done dismisses", fake.count("dismissSend") > 0, true)
            expect("done never cancels", fake.count("cancelSend"), cancels)
            expect("send cleared", v.sendOpen, false)
        },
        function (v) {
            fake.sendRequestId = "s3"
            fake.sendStatusJson = JSON.stringify({ requestId: "s3", kind: "send", state: "awaiting_approval", requester: "some_dapp", approvalHandle: "smh_3" })
        },
        function (v) {
            var asked = logos.requests.filter(function (q) { return q.intent === "evm.signing.approve" })
            expect("no intent for another app's send", asked.length, 1)
            expect("foreign shows", shown("askSignerButton"), true)
            fake.sendRequestId = ""
            fake.sendStatusJson = "{}"
            v.selectTab(3)
        },
        function (v) {
            expect("intent row", prop("historyIntent_" + "bb".repeat(32), "text"), "−0.0006 BTC · fee 141 sats")
            expect("pending row state", prop("historyState_" + "aa".repeat(32), "text"), "pending · reported by electrum.example")
            expect("speed up row", shown("speedUp_" + "bb".repeat(32)), true)
            expect("no speed up confirmed", shown("speedUp_" + "cc".repeat(32)), false)
            find(view.item, "speedUp_" + "bb".repeat(32), 0).clicked()
        },
        function (v) {
            expect("speed up sheet", prop("speedUpSheet", "visible"), true)
            expect("speed up rate", prop("speedUpRateField", "text"), "12")
            find(view.item, "confirmSpeedUpButton", 0).clicked()
            expect("bump asked", fake.last("requestFeeBump"), ["requestFeeBump", "bb".repeat(32), 12])
            v.selectTab(4)
        },
        function (v) {
            expect("settings locked", shown("networkLockedNotice"), true)
            expect("no switches while open", shown("useSwitch_electrum.example"), false)
            expect("one operator", shown("oneOperatorNotice"), true)
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
        },
        function (v) {
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            expect("sheet", prop("networkSheet", "visible"), true)
            // A network the backend has not set up yet is "setting up", never "nothing defines the chain".
            var keep = fake.sourcesJson
            fake.sourcesJson = JSON.stringify({ network: "regtest", configured: false, walletOpen: false, sources: [], exposes: [], withoutTor: [] })
            expect("unconfigured is not empty", prop("sourcesEmpty", "text"), "Setting up the sources for regtest…")
            expect("unconfigured says nothing of the chain", shown("noChainNotice"), false)
            fake.sourcesJson = keep
            expect("unlocked", shown("networkLockedNotice"), false)
            expect("one operator, no wallet", shown("oneOperatorNotice"), true)
            find(view.item, "historySwitch_esplora.example", 0).clicked()
        },
        function (v) {
            expect("history asks first", shown("historyConfirm_esplora.example"), true)
            expect("history not yet", fake.count("setSource"), 0)
            find(view.item, "confirmHistory_esplora.example", 0).clicked()
            expect("history on", fake.last("setSource"), ["setSource", "esplora.example", JSON.stringify({ history: true })])
            find(view.item, "torSwitch_electrum.example", 0).clicked()
        },
        function (v) {
            expect("tor asks first", shown("torOffConfirm_electrum.example"), true)
            expect("tor says what it sees", String(prop("torOffConfirm_electrum.example", "message")).indexOf("IP address") >= 0, true)
            find(view.item, "skipTor_electrum.example", 0).clicked()
            expect("tor off", fake.last("setSource"), ["setSource", "electrum.example", JSON.stringify({ tor: false })])
            var s = JSON.parse(fake.sourcesJson)
            s.sources[1].tor = false
            s.sources[1].route = "direct"
            s.withoutTor = [{ id: "electrum.example", url: "ssl://electrum.example:50002", operator: "example", lan: false }]
            fake.sourcesJson = JSON.stringify(s)
        },
        function (v) {
            expect("without tor badge", shown("withoutTorBadge_electrum.example"), true)
            expect("without tor notice", shown("withoutTorNotice"), true)
            v.closeSheets()
            var st = JSON.parse(scene.syncedMainnet)
            st.needsBirthday = true
            fake.statusJson = JSON.stringify(st)
            fake.alertsJson = JSON.stringify([{ source: "kyoto", kind: "authority_suspect", detail: "a filter header the quorum did not agree on", at: 1 }])
            v.selectTab(0)
        },
        function (v) {
            expect("birthday notice", shown("needsBirthdayHomeNotice"), true)
            expect("authority suspect banner", shown("authoritySuspectBanner"), true)
            expect("its own banner only", shown("alertBanner"), false)
            find(view.item, "setBirthdayButton", 0).clicked()
        },
        function (v) {
            expect("birthday sheet", prop("birthdaySheet", "visible"), true)
            expect("no day yet", prop("confirmBirthdayButton", "enabled"), false)
            find(view.item, "birthdayDateField", 0).text = "2026-01-02"
            expect("a day", prop("confirmBirthdayButton", "enabled"), true)
            find(view.item, "confirmBirthdayButton", 0).clicked()
            expect("birthday asked", fake.last("setBirthday"), ["setBirthday", JSON.stringify({ date: "2026-01-02" })])
            fake.birthdayJson = JSON.stringify({ state: "failed", error: "the day is after the wallet's first transaction" })
        },
        function (v) {
            expect("refusal said", prop("birthdayError", "text"), "Not set: the day is after the wallet's first transaction")
            expect("sheet stays", prop("birthdaySheet", "visible"), true)
            find(view.item, "birthdayUnknown", 0).checked = true
            find(view.item, "confirmBirthdayButton", 0).clicked()
            expect("from the start", fake.last("setBirthday"), ["setBirthday", JSON.stringify({ height: 0 })])
            fake.birthdayJson = JSON.stringify({ state: "done", birthday: { height: 481824, source: "set" }, rescanFrom: 481824 })
            var st = JSON.parse(scene.syncedMainnet)
            st.rescanFrom = 481824
            st.syncPercent = 42
            st.birthdaySource = "set"
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("sheet closes", prop("birthdaySheet", "visible"), false)
            expect("rescan line", prop("rescanLine", "text"), "Rescanning from block 481,824 · 42%")
            var st2 = JSON.parse(fake.statusJson)
            delete st2.syncPercent
            fake.statusJson = JSON.stringify(st2)
            expect("a full scan has no share", prop("rescanLine", "text"), "Rescanning from block 481,824…")
            expect("notice gone", shown("needsBirthdayHomeNotice"), false)
            fake.alertsJson = "[]"
            var st = JSON.parse(scene.syncedMainnet)
            st.lastReorg = { height: 935490, depth: 1, moved: ["ee".repeat(32)], at: 1 }
            fake.statusJson = JSON.stringify(st)
            fake.historyJson = JSON.stringify({ page: 0, pageSize: 50, total: 2, rows: [
                { txid: "ee".repeat(32), intent: "receive", amountSat: "70000", state: "confirmed", height: 935490, confirmations: 11, blockHash: "00".repeat(32) },
                { txid: "cc".repeat(32), intent: "receive", amountSat: "125000000", state: "confirmed", height: 100, confirmations: 50, blockHash: "11".repeat(32) }] })
            v.selectTab(3)
        },
        function (v) {
            expect("re-anchored", prop("historyReanchored_" + "ee".repeat(32), "text"), "re-anchored at height 935,490")
            expect("re-anchored shown", shown("historyReanchored_" + "ee".repeat(32)), true)
            expect("not moved", shown("historyReanchored_" + "cc".repeat(32)), false)
            expect("its block", prop("historyBlock_" + "ee".repeat(32), "text"),
                   "Moved to a new block by a reorg of 1 block: re-anchored at height 935,490, block " + "00".repeat(32))
            expect("a block", prop("historyBlock_" + "cc".repeat(32), "text"), "11".repeat(32))
            v.lastRequest = { send: { recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], feeRate: 6 } }
            fake.sendRequestId = "s5"
            fake.sendStatusJson = JSON.stringify({ requestId: "s5", kind: "send", state: "awaiting_approval", requester: "bitcoin_wallet_ui",
                approvalHandle: "smh_5", approval: "rendered",
                summary: { recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], change: [{ address: "bcrt1qchange", amountSat: "400" }],
                           inputs: 1, inputSat: "61000", feeSat: "600", feeRate: 6, vsize: 141, totalSat: "60600",
                           warnings: [{ kind: "change_too_small", amountSat: "400", costToSpendSat: "408" }] } })
        },
        function (v) {
            expect("change into the fee offered", prop("addChangeToFeeButton", "text"), "Add it to the fee (+400 sats)")
            expect("offered", shown("addChangeToFeeButton"), true)
            var cancels = fake.count("cancelSend"), asks = fake.count("requestSend")
            find(view.item, "addChangeToFeeButton", 0).clicked()
            expect("withdrawn first", fake.count("cancelSend"), cancels + 1)
            expect("not asked yet", fake.count("requestSend"), asks)
            fake.sendStatusJson = JSON.stringify({ requestId: "s5", kind: "send", state: "cancelled", errorCode: "cancelled", requester: "bitcoin_wallet_ui",
                error: "cancelled by bitcoin_wallet_ui" })
        },
        function (v) {
            expect("asked again with the change in the fee", fake.last("requestSend"),
                   ["requestSend", JSON.stringify({ recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], feeRate: 6, smallChangeToFee: true })])
            fake.sendRequestId = "s6"
            fake.sendStatusJson = JSON.stringify({ requestId: "s6", kind: "send", state: "awaiting_approval", requester: "bitcoin_wallet_ui",
                approvalHandle: "smh_6", approval: "rendered",
                summary: { recipients: [{ address: "bcrt1qrecipient", amountSat: "60000" }], change: [],
                           inputs: 1, inputSat: "61000", feeSat: "1000", feeRate: 7.1, vsize: 141, totalSat: "61000",
                           warnings: [{ kind: "change_to_fee", amountSat: "400", costToSpendSat: "408" }] } })
        },
        function (v) {
            expect("change to fee line", prop("changeToFeeNotice", "message"),
                   "400 sats of change would have cost about 408 sats to spend, so it is part of the fee and no change comes back.")
            expect("no change left to add", v.warningsOf("change_too_small", true).length, 0)
            fake.sendRequestId = ""
            fake.sendStatusJson = "{}"
            v.closeSheets()
            var st = JSON.parse(scene.syncedMainnet)
            st.authority.kind = "local_node"
            st.node = { pruned: true, pruneHeight: 300, filters: true, prunedGap: { from: 100, below: 300, heights: [150], via: "electrum.example", resolved: false } }
            fake.statusJson = JSON.stringify(st)
            v.selectTab(0)
        },
        function (v) {
            expect("named node", prop("syncLine", "text"), "Synchronized · block 935,500, tip 4 min old · Your node")
            expect("gap covered", prop("prunedGapLine", "text"), "Older blocks via electrum.example (blocks 100–299)")
            expect("no gap notice", shown("prunedGapNotice"), false)
            var st = JSON.parse(fake.statusJson)
            st.node.prunedGap.via = null
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("gap notice", shown("prunedGapNotice"), true)
            expect("no via line", shown("prunedGapLine"), false)
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
            var cert = { certSha256: "ab".repeat(32), subject: "CN=electrs.lan", issuer: "CN=electrs.lan", notBefore: "2026-10-11T01:43:03Z", notAfter: "2126-09-17T01:43:03Z", trusted: false }
            fake.sourcesJson = JSON.stringify({ network: "regtest", configured: true, walletOpen: false, exposes: [], withoutTor: [], sources: [
                { id: "mine", kind: "electrum", url: "ssl://electrs.lan:50002", operator: "electrs.lan", label: "My server", use: true, history: true, tor: false, lan: true, route: "direct", userAdded: true, certificate: cert },
                { id: "plain", kind: "electrum", url: "tcp://192.168.1.20:50001", operator: "192.168.1.20", label: "Plain", use: true, history: false, tor: false, lan: true, route: "direct", userAdded: true, encrypted: false },
                { id: "newsrv", kind: "electrum", url: "ssl://new.lan:50002", operator: "new.lan", label: "New", use: true, history: false, tor: false, lan: true, route: "direct", userAdded: true }] })
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            expect("untrusted certificate shown", String(prop("certDetails_mine", "text")).indexOf("Subject CN=electrs.lan, issued by CN=electrs.lan") === 0, true)
            expect("trust offered", shown("trustCert_mine"), true)
            expect("plain text marked", shown("notEncryptedBadge_plain"), true)
            expect("tls not marked", shown("notEncryptedBadge_mine"), false)
            expect("check offered", shown("probeSource_newsrv"), true)
            find(view.item, "trustCert_mine", 0).clicked()
            expect("pinned", fake.last("setSource"), ["setSource", "mine", JSON.stringify({ certSha256: "ab".repeat(32) })])
            var s = JSON.parse(fake.sourcesJson)
            s.sources[0].certSha256 = "ab".repeat(32)
            fake.sourcesJson = JSON.stringify(s)
            fake.probeJson = JSON.stringify({ sourceId: "newsrv", state: "probing" })
        },
        function (v) {
            expect("pin shown", prop("certPin_mine", "text"), "Pinned certificate, SHA-256 " + Array(33).join("AB:").slice(0, -1))
            expect("pinned badge", shown("pinnedBadge_mine"), true)
            expect("no trust once pinned", shown("trustCert_mine"), false)
            expect("probing", shown("certProbing_newsrv"), true)
            find(view.item, "removePin_mine", 0).clicked()
            expect("unpinned", fake.last("setSource"), ["setSource", "mine", JSON.stringify({ certSha256: null })])
            fake.probeJson = JSON.stringify({ sourceId: "newsrv", state: "done", certificate: { certSha256: "cd".repeat(32), subject: "CN=new.lan", issuer: "CN=Example CA", notBefore: "2026-01-01T00:00:00Z", notAfter: "2027-01-01T00:00:00Z", trusted: true } })
            var st = JSON.parse(scene.syncedMainnet)
            st.network = "regtest"
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("a probed certificate", String(prop("certDetails_newsrv", "text")).indexOf("issued by CN=Example CA") > 0, true)
            v.selectTab(4)
            expect("locked while open", shownAny("pinLocked_mine"), true)
            expect("no unpin while open", shownAny("removePin_mine"), false)
            expect("no trust while open", shownAny("trustCert_newsrv"), false)
            v.closeSheets()
            fake.statusJson = JSON.stringify({ state: "closing", network: "regtest", activeNetwork: "regtest" })
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet4", "signet", "regtest"], active: "regtest", pending: "signet" })
        },
        function (v) {
            expect("a switch can be asked for while the wallet closes", v.canPickNetwork, true)
            expect("queued behind the close", prop("switchNote", "text"), "Switching to signet when the wallet has closed")
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet4", "signet", "regtest"], active: "regtest", pending: null })
            fake.switchJson = JSON.stringify({ network: "signet", state: "refused", code: "send_open", error: "send s3 is still open" })
        },
        function (v) {
            expect("send open", prop("switchNote", "text"), "A send is still open: approve, reject or cancel it, then switch networks.")
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
        },
        function (v) {
            expect("a reason that no longer holds is not shown", shown("switchNote"), false)
            fake.statusJson = JSON.stringify({ state: "opening", network: "regtest", activeNetwork: "regtest" })
            fake.switchJson = JSON.stringify({ network: "signet", state: "refused", code: "busy", error: "a wallet is opening" })
        },
        function (v) {
            expect("busy", prop("switchNote", "text"), "A wallet is opening: let it open, or cancel it, then switch networks.")
            var st = JSON.parse(scene.syncedMainnet)
            st.network = "regtest"
            fake.statusJson = JSON.stringify(st)
            fake.switchJson = JSON.stringify({ network: "signet", state: "refused", code: "wallet_open", error: "close the open wallet" })
        },
        function (v) {
            expect("wallet open, said on any page", prop("switchNote", "text"), "Close the wallet before switching networks.")
            expect("...and shown there", shown("switchNote"), true)
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
            fake.switchJson = JSON.stringify({ network: "signet", state: "done" })
            fake.openQueuedJson = JSON.stringify({ network: "signet", error: "switching to signet once the wallet has closed; try again" })
        },
        function (v) {
            expect("done says nothing", shown("switchNote"), false)
            expect("an open waits for the switch", prop("openQueuedNote", "text"), "Opening on signet once the switch applies…")
            fake.openQueuedJson = ""
            fake.sourcesJson = JSON.stringify({ network: "regtest", configured: true, walletOpen: false, exposes: [], withoutTor: [], sources: [
                { id: "kyoto", kind: "kyoto", url: "p2p://peer-list", operator: "peers", label: "Bitcoin peers", use: true, history: false, tor: true, lan: false, route: "tor" }] })
            var peers = []
            for (var i = 0; i < 11; i++) peers.push("p" + i + ".onion:38333")
            fake.peerListJson = JSON.stringify({ network: "regtest", source: "shipped", ownPeers: [], usable: peers, route: "onion", kyotoTor: true,
                list: { format: 1, network: "regtest", version: "1", peers: peers, keyId: "test-d680f3cac9837bf9",
                        note: "PROVISIONAL: from 1 run, not the plan's 6 of 7 days. Signed with a TEST key: not a release." } })
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            expect("the curated list", prop("curatedLine", "text"), "The curated list: 11 peers, provisional, signed with a test key, not a release")
            expect("no peers of your own yet", shownAny("useCuratedButton"), false)
            findAll(view.item, "ownPeerField", 0, []).forEach(function (f) { f.text = "192.168.1.20:8333" })
            var add = findAll(view.item, "addOwnPeerButton", 0, []).filter(function (b) { return b.visible })[0]
            add.clicked()
            expect("added", fake.last("setOwnPeers"), ["setOwnPeers", JSON.stringify(["192.168.1.20:8333"])])
            var list = JSON.parse(fake.peerListJson)
            list.ownPeers = ["192.168.1.20:8333"]
            list.usable = ["192.168.1.20:8333"]
            list.route = "direct"
            fake.peerListJson = JSON.stringify(list)
        },
        function (v) {
            expect("your peer", shownAny("ownPeer_192.168.1.20:8333"), true)
            expect("reached directly", prop("ownPeersRoute", "text"), "Kyoto reaches them directly, on your network.")
            var off = JSON.parse(fake.peerListJson)
            off.kyotoTor = false
            fake.peerListJson = JSON.stringify(off)
        },
        function (v) {
            expect("direct with Kyoto's Tor off", prop("ownPeersRoute", "text"), "Kyoto reaches them directly: its Tor is off.")
            var t = JSON.parse(fake.peerListJson)
            t.kyotoTor = true
            t.ownPeers = ["example.org:38333"]
            t.route = "tor"
            fake.peerListJson = JSON.stringify(t)
        },
        function (v) {
            expect("through Tor", prop("ownPeersRoute", "text"), "Kyoto reaches them through Tor.")
            findAll(view.item, "useCuratedButton", 0, []).filter(function (b) { return b.visible })[0].clicked()
            expect("the curated list again", fake.last("setOwnPeers"), ["setOwnPeers", "[]"])
            var st = JSON.parse(scene.syncedMainnet)
            st.network = "regtest"
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            v.selectTab(4)
        },
        function (v) {
            expect("own peers locked while open", shownAny("ownPeersLocked"), true)
            expect("no adding while open", shownAny("addOwnPeerButton"), false)
            expect("no picking a network while open", v.canPickNetwork, false)
            // Kyoto below its quorum, a conflict, a chain from block 150, and payments below it.
            var st = JSON.parse(scene.syncedMainnet)
            st.network = "regtest"
            st.activeNetwork = "regtest"
            st.authority = { kind: "kyoto", height: 400, tipAgeSecs: 60, peers: 1, base: 150 }
            st.kyoto = { running: true, phase: "synced", quorum: 1, onePeerDecides: true, rescans: 0, window: [25, 25],
                         lastConflict: { at: 1791590400, peers: ["127.0.0.1:28554"] } }
            fake.statusJson = JSON.stringify(st)
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "100000000", waiting: "0", unchecked: "250000", pending: "0",
                                                 sent: "0", immature: "0", tooSmall: { count: 0, sat: "0" } })
            fake.historyJson = JSON.stringify({ page: 0, pageSize: 25, total: 2, rows: [
                { txid: "aa".repeat(32), intent: "receive", amountSat: "250000", feeSat: null, counterparties: [], height: 120,
                  blockHash: "11".repeat(32), confirmations: 281, time: 1791500000, state: "unchecked", reportedBy: null, confirmedVia: "bb".repeat(32) },
                { txid: "cc".repeat(32), intent: "receive", amountSat: "100000000", feeSat: null, counterparties: [], height: null,
                  blockHash: null, confirmations: 3, time: 1791500000, state: "confirmed", confirmedVia: "dd".repeat(32) }] })
            fake.alertsJson = JSON.stringify([{ source: "esplora-0", kind: "unchecked_anchor", detail: "1 transaction reported below block 150", at: 1791590400 }])
        },
        function (v) {
            expect("one peer decides: the one-operator notice", shownAny("oneOperatorNotice"), true)
            expect("...titled so", prop("oneOperatorNotice", "title"), "One peer decides this wallet's chain")
            expect("a conflict, quietly", prop("kyotoConflictLine", "text"), "Peers that disagreed were set aside at " + v.whenOf(1791590400))
            expect("the chain's start in the wallet details", prop("walletChainBase", "text"), "block 150")
            v.selectTab(0)
        },
        function (v) {
            expect("unchecked apart from the balance", prop("uncheckedRow", "amount"), v.btcOf("250000") + " BTC")
            expect("...and shown", shown("uncheckedRow"), true)
            expect("the confirmed balance leaves it out", prop("confirmedCard", "value"), v.btcOf("100000000") + " BTC")
            expect("the unchecked banner", shown("uncheckedBanner"), true)
            expect("...not the shared one", shown("alertBanner"), false)
            expect("it says where the chain starts", String(prop("uncheckedBanner", "message")).indexOf("starts, block 150. Nothing could check them") > 0, true)
            find(view.item, "uncheckedBirthdayButton", 0).clicked()
        },
        function (v) {
            expect("an earlier birthday, from the banner", prop("birthdaySheet", "visible"), true)
            v.closeSheets()
            v.selectTab(3)
            v.openTx = "aa".repeat(32)
        },
        function (v) {
            expect("reported, not checked", prop("historyState_" + "aa".repeat(32), "text"), "Reported by esplora-0, not checked")
            expect("never confirmed-coloured", prop("historyState_" + "aa".repeat(32), "color") === v.rowStateColor({ state: "confirmed" }), false)
            expect("its spend is confirmed", prop("historyVia_" + "aa".repeat(32), "text"), "bb".repeat(32) + ", confirmed; this one's own block is not checked")
            scene.keptAlerts = fake.alertsJson
            fake.alertsJson = "[]"
        },
        function (v) {
            expect("no alert to name the source", prop("historyState_" + "aa".repeat(32), "text"), "Reported by a server, not checked")
            fake.alertsJson = scene.keptAlerts
            v.openTx = "cc".repeat(32)
        },
        function (v) {
            expect("confirmed through its spend", prop("historyVia_" + "cc".repeat(32), "text"), "dd".repeat(32) + ", a later transaction that spends it")
            var st = JSON.parse(fake.statusJson)
            st.rescanFrom = 0
            st.syncPercent = 40
            st.kyoto.rescans = 1
            fake.statusJson = JSON.stringify(st)
            v.selectTab(0)
        },
        function (v) {
            expect("a wider rescan", prop("rescanLine", "text"), "Rescanning with a wider address range (pass 1) · 40%")
            var st = JSON.parse(fake.statusJson)
            st.authority.kind = "local_node"
            st.node = { blocks: 400, headers: 400, synced: true, rescans: 2, window: [60, 25] }
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("the node's count under the node", prop("rescanLine", "text"), "Rescanning with a wider address range (pass 2) · 40%")
            expect("no one-peer notice off Kyoto", v.onePeerDecides, false)
            var st = JSON.parse(fake.statusJson)
            st.node.rescans = 0
            fake.statusJson = JSON.stringify(st)
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "100250000", waiting: "0", unchecked: "0", pending: "0",
                                                 sent: "0", immature: "0", tooSmall: { count: 0, sat: "0" } })
        },
        function (v) {
            expect("a plain rescan", prop("rescanLine", "text"), "Rescanning from block 0 · 40%")
            expect("checked now: no unchecked line", shown("uncheckedRow"), false)
            expect("...and the banner goes", shown("uncheckedBanner"), false)
            // A coin found past a 20-address gap limit: apart from the balance, yet spendable.
            var st = JSON.parse(fake.statusJson)
            delete st.rescanFrom
            st.gapLimit = 20
            st.birthday = 101
            st.historyServer = "esplora-0"
            fake.statusJson = JSON.stringify(st)
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "100250000", waiting: "0", unchecked: "0", pending: "0",
                                                 sent: "0", immature: "0", tooSmall: { count: 0, sat: "0" }, beyondGap: { count: 1, sat: "70000", confirmedSat: "70000" } })
            fake.historyJson = JSON.stringify({ page: 0, pageSize: 25, total: 1, rows: [
                { txid: "ee".repeat(32), intent: "receive", amountSat: "70000", feeSat: null, counterparties: [], height: 140,
                  blockHash: "22".repeat(32), confirmations: 11, time: 1791500000, state: "confirmed", beyondGap: true }] })
        },
        function (v) {
            expect("beyond the gap: its own line", prop("beyondGapRow", "title"), "Found beyond your 20-address gap limit")
            expect("...its amount", prop("beyondGapRowAmount", "text"), v.btcOf("70000") + " BTC")
            expect("...spendable", prop("beyondGapRow", "note"), "1 coin, yours and spendable: Send counts them.")
            expect("...and what it means", prop("beyondGapRowInfo", "text"), "These coins are yours, and you can spend them. Other wallets "
                   + "that use a gap limit of 20 won't show them. Raising the gap limit in Settings makes them part of the normal balance.")
            expect("the balance leaves them out", prop("confirmedCard", "value"), v.btcOf("100250000") + " BTC")
            expect("...but what Send spends counts them", prop("confirmedCard", "caption"), "Confirmed on the wallet's own chain. Send "
                   + "spends this and the coins found beyond the gap limit: " + v.btcOf("100320000") + " BTC in all.")
            expect("Send says so too", prop("sendAvailable", "text"), "Send spends confirmed coins, those found beyond the gap limit included: "
                   + v.btcOf("100320000") + " BTC.")
            v.selectTab(3)
        },
        function (v) {
            expect("a quiet label in Activity", prop("historyBeyondGap_" + "ee".repeat(32), "text"), "Beyond the gap limit")
            expect("...shown", shown("historyBeyondGap_" + "ee".repeat(32)), true)
            var w = { kind: "beyond_gap_inputs", count: 1, sat: "70000", message: "1 input was found beyond the gap limit" }
            expect("the review says when it spends them", v.beyondGapInputsLine(v.beyondGapInputs({ warnings: [w] })),
                   "1 coin it spends, " + v.btcOf("70000") + " BTC, was found beyond the gap limit.")
            expect("...in the plural too", v.beyondGapInputsLine({ kind: "beyond_gap_inputs", count: 2, sat: "90000" }),
                   "2 coins it spends, " + v.btcOf("90000") + " BTC, were found beyond the gap limit.")
            expect("...and only then", [v.beyondGapInputs({ warnings: [{ kind: "change_to_fee" }] }), v.beyondGapInputs(null)], [null, null])
            // Part of it unconfirmed: what Send counts is the confirmed part.
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "100250000", waiting: "0", unchecked: "0", pending: "0",
                                                 sent: "0", immature: "0", tooSmall: { count: 0, sat: "0" }, beyondGap: { count: 2, sat: "90000", confirmedSat: "70000" } })
        },
        function (v) {
            expect("the confirmed part is spendable", prop("beyondGapRow", "note"), "2 coins, yours: " + v.btcOf("70000")
                   + " BTC of it is confirmed and spendable, and Send counts that.")
            expect("...the line shows them all", prop("beyondGapRowAmount", "text"), v.btcOf("90000") + " BTC")
            expect("...and Send counts the confirmed part", prop("sendAvailable", "text"), "Send spends confirmed coins, those found beyond "
                   + "the gap limit included: " + v.btcOf("100320000") + " BTC.")
            v.selectTab(4)
        },
        function (v) {
            expect("the gap limit in the wallet's details", prop("walletGapLimit", "text"), "20 addresses")
            find(view.item, "gapLimitField", 0).text = "10"
        },
        function (v) {
            expect("below 20 is refused here", prop("gapLimitNote", "text"), "A whole number from 20 to 1,000.")
            expect("...and cannot be sent", prop("gapLimitButton", "enabled"), false)
            find(view.item, "gapLimitField", 0).text = "40"
        },
        function (v) {
            expect("raising is offered", prop("gapLimitButton", "enabled"), true)
            find(view.item, "gapLimitButton", 0).clicked()
        },
        function (v) {
            expect("raising asks first", prop("gapLimitSheet", "visible"), true)
            expect("...naming the limit", prop("gapLimitSheet", "title"), "Raise the gap limit to 40?")
            expect("...the rescan, and the history server", prop("gapLimitSheet", "message"), "The wallet scans again from its birthday, block 101, "
                   + "watching 40 unused addresses past the last one used. That downloads more. Your history server, esplora-0, will be asked about more addresses.")
            expect("nothing asked yet", fake.count("setGapLimit"), 0)
            find(view.item, "confirmGapLimitButton", 0).clicked()
        },
        function (v) {
            expect("raised once confirmed", fake.last("setGapLimit"), ["setGapLimit", JSON.stringify({ gapLimit: 40 })])
            fake.gapLimitJson = JSON.stringify({ state: "failed", code: "busy", error: "busy: a rescan is running" })
            find(view.item, "gapLimitField", 0).text = ""
        },
        function (v) {
            expect("a busy refusal, in plain words", prop("gapLimitNote", "text"), "The wallet is busy opening, rescanning or sending: try again once it settles.")
            var st = JSON.parse(fake.statusJson)
            st.gapLimit = 40
            fake.statusJson = JSON.stringify(st)
            fake.gapLimitJson = ""
            find(view.item, "gapLimitField", 0).text = "25"
        },
        function (v) {
            find(view.item, "gapLimitButton", 0).clicked()
            expect("lowering needs no asking", fake.last("setGapLimit"), ["setGapLimit", JSON.stringify({ gapLimit: 25 })])
            expect("...and no sheet", prop("gapLimitSheet", "visible"), false)
            var st = JSON.parse(fake.statusJson)
            st.historyServer = "kyoto"
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("Kyoto's filters learn no address: no server is named", String(prop("gapLimitSheet", "message")).indexOf("history server"), -1)
        }
    ]
    property int step: 0
    property string keptAlerts: ""
    Timer {
        id: driver
        interval: 30
        repeat: true
        onTriggered: {
            var v = view.item
            try { scene.steps[scene.step](v) } catch (e) { bad.push("step " + scene.step + " threw " + e) }
            scene.step += 1
            if (scene.step >= scene.steps.length) {
                driver.stop()
                console.log(bad.length ? "STATES-FAIL " + bad.join("; ") : "STATES-OK " + scene.steps.length + " steps")
                Qt.quit()
            }
        }
    }

    Loader {
        id: view
        anchors.fill: parent
        source: "../qml/BitcoinWalletView.qml"
        onStatusChanged: {
            if (status === Loader.Error) { console.log("STATES-FAIL load"); Qt.quit(); return }
            if (status !== Loader.Ready) return
            try { scene.pureCases(view.item) } catch (e) { bad.push("pure cases threw " + e) }
            driver.start()
        }
    }
}
