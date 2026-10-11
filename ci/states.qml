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
            [mainnet({}), "Synchronized · block 935,500, tip 4 min old"],
            // No agreeing source: the core's own `synced` is not enough.
            [mainnet({ authority: { height: 935500, tipAgeSecs: 240, peers: 0 } }), "No source agrees · block 935,500, tip 4 min old"],
            [mainnet({ authority: { height: 935500, tipAgeSecs: 7300, peers: 0 } }), "No source agrees · block 935,500, tip 2 hours old"],
            // A tip older than an hour is never synchronized.
            [mainnet({ authority: { height: 935500, tipAgeSecs: 3601, peers: 3 } }), "Stalled · block 935,500, tip 1 hour old"],
            [mainnet({ authority: { height: 935500, tipAgeSecs: 200000, peers: 3 } }), "Stalled · block 935,500, tip 2 days old"],
            [mainnet({ state: "syncing", synced: false, walletTip: 900000, syncPercent: 42,
                       authority: { height: 935500, tipAgeSecs: 300, peers: 2 } }), "Syncing 42% · block 900,000 of 935,500"],
            [mainnet({ state: "syncing", synced: false, walletTip: undefined }), "Syncing · the chain is at block 935,500"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { height: 150, tipAgeSecs: 9000, peers: 1 } }), "Local chain · block 150"],
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
        expect("source line", v.walletSourceLine({ state: "ok", roles: ["chain", "history"], history: true }), "ok · chain, history · history server")
        expect("suspect line", v.walletSourceLine({ state: "suspect", suspect: true, suspectReason: "served invalid headers", error: "x" }), "suspect: served invalid headers")
        expect("failing line", v.walletSourceLine({ state: "failing", roles: ["chain"], error: "connection refused" }), "failing · chain · connection refused")
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
            expect("synced line", prop("syncLine", "text"), "Synchronized · block 935,500, tip 4 min old")
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
            expect("rendered: no peers is never synchronized", prop("syncLine", "text"), "No source agrees · block 935,500, tip 4 min old")
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
        }
    ]
    property int step: 0
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
