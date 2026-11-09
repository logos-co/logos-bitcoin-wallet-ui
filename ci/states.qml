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
        property string accountsJson: ""
        property string accountsError: ""
        property string accountRosterJson: "[]"
        property string signerWalletsJson: "[]"
        property string balancesJson: ""
        property string historyJson: ""
        property int historyPage: 0
        property string receiveJson: ""
        property string receiveQrJson: ""
        property string addressesJson: ""
        // What setAddressLabel answers: "" saves it, as the backend patches the row.
        property string addressLabelReply: ""
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
        // What setTorUse answers: "" takes the mode, as the backend's reply patches the sources.
        property string torUseReply: ""
        property var calls: []
        function note(name, args) { calls = calls.concat([[name].concat(args)]) }
        function last(name) {
            for (var i = calls.length - 1; i >= 0; i--) if (calls[i][0] === name) return calls[i]
            return null
        }
        function count(name) { return calls.filter(function (c) { return c[0] === name }).length }
        function refresh() {}
        function clearAndRefresh() {}
        function selectAccount(id, birthday) { note("selectAccount", [id, birthday]) }
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
        function refreshAddresses() { note("refreshAddresses", []) }
        function showAddress(i) { note("showAddress", [i]) }
        function setAddressLabel(i, l) {
            note("setAddressLabel", [i, l])
            if (addressLabelReply !== "") return addressLabelReply
            var o = JSON.parse(addressesJson || "{}")
            o.addresses = (o.addresses || []).map(function (r) { if (r.index === i) r.label = l.trim(); return r })
            addressesJson = JSON.stringify(o)
            return ""
        }
        function setReceiveAmount(a) { note("setReceiveAmount", [a]) }
        function addressValid(t) {
            if (t.indexOf("bcrt1q") === 0) return JSON.stringify({ ok: true, valid: true, address: t, type: "p2wpkh", dustSat: "294" })
            if (t.indexOf("bitcoin:") === 0) return JSON.stringify({ ok: true, valid: true, address: t.slice(8).split("?")[0], type: "p2wpkh", amountSat: "150000" })
            return JSON.stringify({ ok: true, valid: false, reason: "this address is for another network" })
        }
        function refreshHistory() {}
        function showHistoryPage(p) {}
        function dismissAlerts() { alertsJson = "[]" }
        function setSource(id, changes) { note("setSource", [id, changes]); return "" }
        function addRpcSource(a,u,p,n,t) { note("addRpcSource", [a,u,p,n,t]); return "" }
        function useDirectSource(id) { note("useDirectSource", [id]); return "" }
        function addSource(a, k, n) { note("addSource", [a, k, n]); return "" }
        function removeSource(id) { note("removeSource", [id]); return "" }
        function setProxy(p) { note("setProxy", [p]); return "" }
        function setTorUse(m) {
            note("setTorUse", [m])
            if (torUseReply !== "") return torUseReply
            var o = JSON.parse(sourcesJson || "{}")
            o.torUse = m
            o.torUseChosen = true
            sourcesJson = JSON.stringify(o)
            return ""
        }
        // What setLocalSends answers: "" takes the route, as the backend's reply patches the sources.
        property string sendsReply: ""
        function setLocalSends(v) {
            note("setLocalSends", [v])
            if (sendsReply !== "") return sendsReply
            var o = JSON.parse(sourcesJson || "{}")
            if (o.sends) { o.sends.localSends = v; o.sends.localSendsChosen = true; if (v === "node") o.sends.sendServers = [] }
            sourcesJson = JSON.stringify(o)
            return ""
        }
        function setOwnPeers(p) { note("setOwnPeers", [p]); return "" }
        function clearSuspect(id) { note("clearSuspect", [id]); return "" }
        function refreshSources() {}
        function descriptors() { return JSON.stringify({ ok: true, external: "wpkh([73c5da0a/84h/1h/0h]tpubD6/0/*)", internal: "wpkh([73c5da0a/84h/1h/0h]tpubD6/1/*)" }) }
    }

    property var bad: []
    // What a detour leaves in the fake, put back after it.
    property string keptSources: ""
    property string keptHealth: ""
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

    function expandAdvanced() {
        findAll(view.item, "advancedSourcesButton", 0, []).forEach(function (b) { if (!b.expanded) b.clicked() })
    }
    function expandSources(ids) {
        view.item.expandedSources = view.item.expandedSources.concat(ids)
    }

    function cardRow(available) {
        return {id:"keycard-cdcdcdcd-84-1-0",family:"bitcoin",chain:"test",label:"Card account",signer:"keycard_module",available:available,
                origin:{devices:[{kind:"keycard",id:"ab".repeat(32),name:"Keycard"}],phrase:{id:"seed:"+"cd".repeat(32),name:"Black Card"}}}
    }
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
            [{ state: "awaiting_open", openHandle: "sma_1" }, "Waiting for the Signer app"],
            [{ state: "opening" }, "Opening the wallet…"],
            [{ state: "closing" }, "Closing…"],
            [{ state: "failed", lastError: "the keystore opened a wallet of another family" }, "Failed: the keystore opened a wallet of another family"],
            [mainnet({ state: "syncing", authority: { height: null, peers: 0 } }), "Connecting to the chain's sources…"],
            [mainnet({ state: "syncing", authority: { height: null, peers: 2 } }), "Reading the chain's headers…"],
            [mainnet({}), "Synchronized · block 935,500 · from 2 Electrum servers"],
            [mainnet({ authority: { kind: "kyoto", height: 935500, tipAgeSecs: 240, peers: 3 } }), "Synchronized · block 935,500 · from 3 Bitcoin peers"],
            [mainnet({ authority: { kind: "kyoto", height: 935500, tipAgeSecs: 240, peers: 1 } }), "Synchronized · block 935,500 · from 1 Bitcoin peer"],
            [mainnet({ authority: { kind: "local_node", height: 935500, tipAgeSecs: 240, peers: 1 } }), "Synchronized · block 935,500 · from your node"],
            [mainnet({ authority: { kind: "electrum_headers", height: 935500, tipAgeSecs: 240, peers: 1 } }), "Synchronized · block 935,500 · from 1 Electrum server"],
            // No agreeing source: the core's own `synced` is not enough. The words follow who decides the chain.
            [mainnet({ authority: { kind: "kyoto", height: 935500, tipAgeSecs: 240, peers: 0 } }), "Can't confirm the chain · no peer answered · last block 935,500, 4 min old"],
            [mainnet({ authority: { kind: "electrum_headers", height: 935500, tipAgeSecs: 7300, peers: 0 } }), "Can't confirm the chain · no server answered · last block 935,500, 2 hours old"],
            // Last session's chain before any source answered this open: connecting, never "none agrees".
            [mainnet({ synced: false, authority: { height: 935500, tipAgeSecs: 75600, peers: 0, asked: false } }), "Connecting to the chain's sources… · last known block 935,500"],
            [mainnet({ authority: { height: 935500, tipAgeSecs: 240, peers: 0, asked: true } }), "Can't confirm the chain · no source answered · last block 935,500, 4 min old"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { height: 150, tipAgeSecs: 30, peers: 0, asked: false } }), "Connecting to the chain's sources… · last known block 150"],
            // A header download: how far it read of the server's tip, never "stalled" or "can't confirm".
            [mainnet({ state: "syncing", synced: false, walletTip: 84000, authority: { kind: "electrum_headers", height: 84000, tipAgeSecs: 50000000, peers: 1, asked: true,
                       headers: { have: 84000, target: 157000 } } }), "Reading the chain's headers… 84,000 of 157,000"],
            [mainnet({ state: "syncing", synced: false, authority: { height: 2016, tipAgeSecs: 50000000, peers: 0, asked: false, headers: { have: 2016, target: 157000 } } }),
             "Reading the chain's headers… 2,016 of 157,000"],
            // Kyoto's peers' tip is unknown: only how far it read.
            [mainnet({ state: "syncing", synced: false, authority: { kind: "kyoto", height: 0, tipAgeSecs: 50000000, peers: 2, asked: true, headers: { have: 6000, target: null } } }),
             "Reading the chain's headers… block 6,000"],
            // A first sync from peers: its best header against the core's estimate of the tip, counted
            // from where the chain starts; then Kyoto's own share once it checks block filters.
            [mainnet({ state: "syncing", synced: false, authority: { kind: "kyoto", height: null, peers: 1, asked: true, base: 481823,
                       headers: { have: 727000, target: null } }, kyoto: { estimatedTip: 973823, progress: 0 } }),
             "Reading the chain's headers… block 727,000 of about 973,823 · about 49%"],
            [mainnet({ state: "syncing", synced: false, authority: { kind: "kyoto", height: null, peers: 3, asked: true, base: 481823,
                       headers: { have: 973823, target: null } }, kyoto: { estimatedTip: 973830, progress: 0.42 } }),
             "Checking block filters… 42%"],
            // Kyoto's scan behind its headers, which the wallet's chain follows: the scan's own height,
            // never "Synchronized". Without `scanned` (an older core) the rule above holds.
            [mainnet({ state: "syncing", synced: false, walletTip: 973920, syncPercent: 100, birthday: 481824,
                       authority: { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3 }, kyoto: { scanned: 501959, phase: "filters" } }),
             "Checking block filters… block 501,959 of 973,920 · 4% · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 973920, birthday: 481824,
                       authority: { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3 }, kyoto: { scanned: 501959, phase: "filter_headers" } }),
             "Checking block filters… block 501,959 of 973,920 · 4% · fetching filter headers · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 973920, birthday: 481824, rescanFrom: 973700,
                       authority: { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3 }, kyoto: { scanned: null, phase: "syncing" } }),
             "Checking block filters from block 973,700… · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 973920, birthday: 481824,
                       authority: { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3 }, kyoto: { scanned: 973917, phase: "filters" } }),
             "Checking block filters… block 973,917 of 973,920 · 99% · from 3 Bitcoin peers"],
            // A scan's first update brings Kyoto's newer headers: an old tip until then is no stall.
            [mainnet({ state: "syncing", synced: false, walletTip: 974135, birthday: 481824,
                       authority: { kind: "kyoto", height: 974135, tipAgeSecs: 126000, peers: 3 },
                       kyoto: { scanned: null, phase: "filter_headers", progress: 0.03, headers: 974330 } }),
             "Checking block filters from block 481,824… · fetching filter headers 12% · from 3 Bitcoin peers"],
            // Its peers with nothing newer, or the scan done, and the tip still old: stalled.
            [mainnet({ state: "syncing", synced: false, walletTip: 974135, birthday: 481824,
                       authority: { kind: "kyoto", height: 974135, tipAgeSecs: 126000, peers: 3 },
                       kyoto: { scanned: null, phase: "filter_headers", progress: 0.03, headers: 974135 } }),
             "Stalled · block 974,135, tip 35 hours old · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 974135, birthday: 481824,
                       authority: { kind: "kyoto", height: 974135, tipAgeSecs: 126000, peers: 3 },
                       kyoto: { scanned: 974134, phase: "synced", headers: 974330 } }),
             "Stalled · block 974,135, tip 35 hours old · from 3 Bitcoin peers"],
            // The open's first catch-up (the core's `catchingUp`): an old tip with news still coming,
            // as on 2026-11-04 after 18 hours closed. Past the core's grace it is a stall again.
            [mainnet({ state: "syncing", synced: false, walletTip: 974439, birthday: 481824,
                       authority: { kind: "kyoto", height: 974439, tipAgeSecs: 64800, peers: 3, catchingUp: true },
                       kyoto: { scanned: 974439, phase: "syncing", headers: 974431 } }),
             "Catching up · block 974,439, tip 18 hours old · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 974439, birthday: 481824,
                       authority: { kind: "kyoto", height: 974439, tipAgeSecs: 64800, peers: 3, catchingUp: true },
                       kyoto: { scanned: 974439, phase: "filters", headers: 974543 } }),
             "Catching up · block 974,439 of 974,543 · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 974439, birthday: 481824,
                       authority: { kind: "kyoto", height: 974439, tipAgeSecs: 64800, peers: 3, catchingUp: false },
                       kyoto: { scanned: 974439, phase: "filters", headers: 974543 } }),
             "Stalled · block 974,439, tip 18 hours old · from 3 Bitcoin peers"],
            [mainnet({ state: "syncing", synced: false, walletTip: 974439,
                       authority: { kind: "local_node", height: 974439, tipAgeSecs: 64800, peers: 1, catchingUp: true },
                       node: { blocks: 974500, headers: 974543 } }),
             "Catching up · block 974,439 of 974,543 · from your node"],
            // The newest block or two still being checked is caught up.
            [mainnet({ state: "syncing", synced: false, walletTip: 973920, birthday: 481824,
                       authority: { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3 }, kyoto: { scanned: 973918, phase: "synced" } }),
             "Synchronized · block 973,920 · from 3 Bitcoin peers"],
            // At the tip the core says null: the usual states.
            [mainnet({ authority: { kind: "electrum_headers", height: 935500, tipAgeSecs: 240, peers: 2, headers: null } }), "Synchronized · block 935,500 · from 2 Electrum servers"],
            // A tip older than an hour is never synchronized.
            [mainnet({ authority: { height: 935500, tipAgeSecs: 3601, peers: 3 } }), "Stalled · block 935,500, tip 1 hour old"],
            [mainnet({ authority: { height: 935500, tipAgeSecs: 200000, peers: 3 } }), "Stalled · block 935,500, tip 2 days old"],
            [mainnet({ state: "syncing", synced: false, walletTip: 900000, syncPercent: 42,
                       authority: { height: 935500, tipAgeSecs: 300, peers: 2 } }), "Syncing 42% · block 900,000 of 935,500"],
            [mainnet({ state: "syncing", synced: false, walletTip: undefined }), "Syncing · the chain is at block 935,500 · from 2 Electrum servers"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { height: 150, tipAgeSecs: 9000, peers: 1 } }), "Local chain · block 150"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { kind: "local_node", height: 150, tipAgeSecs: 9000, peers: 1 } }), "Local chain · block 150 · from your node"],
            [mainnet({ network: "regtest", walletTip: 150, authority: { kind: "rpc_node", height: 150, tipAgeSecs: 9000, peers: 0 } }), "Can't confirm the chain · your node didn't answer · last block 150, 2 hours old"],
            [mainnet({ unavailable: true, error: "the wallet core did not answer" }), "The wallet backend is not answering"]
        ]
        for (var i = 0; i < sync.length; i++) expect("sync " + i, v.syncLabel(sync[i][0]), sync[i][1])
        expect("chip synced", v.syncChip(mainnet({})), "Synced · 935,500")
        expect("chip catching up", v.syncChip(mainnet({ authority: { kind: "kyoto", height: 974439, tipAgeSecs: 64800, peers: 3, catchingUp: true } })), "Catching up")
        expect("chip no peers", v.syncChip(mainnet({ authority: { height: 935500, tipAgeSecs: 240, peers: 0 } })), "No answer")
        expect("chip not asked yet", v.syncChip(mainnet({ authority: { height: 935500, tipAgeSecs: 240, peers: 0, asked: false } })), "Connecting…")
        expect("chip reading headers", v.syncChip(mainnet({ authority: { height: 84000, tipAgeSecs: 50000000, peers: 1, headers: { have: 84000, target: 157000 } } })), "Headers 53%")
        expect("chip never says done before the tip", v.syncChip(mainnet({ authority: { height: 156999, peers: 1, headers: { have: 156999, target: 157000 } } })), "Headers 99%")
        expect("chip reading Kyoto's headers", v.syncChip(mainnet({ authority: { kind: "kyoto", height: 0, peers: 2, headers: { have: 6000, target: null } } })), "Reading headers…")
        var firstSync = mainnet({ state: "syncing", authority: { kind: "kyoto", height: null, peers: 1, base: 481823, headers: { have: 727000, target: null } },
                                  kyoto: { estimatedTip: 973823, progress: 0 } })
        expect("chip: a first sync's headers, estimated", v.syncChip(firstSync), "Headers ~49%")
        expect("...its bar", v.headerPhaseShare(firstSync), 49)
        firstSync.kyoto = { estimatedTip: 973830, progress: 0.42 }
        expect("chip: then its block filters", v.syncChip(firstSync), "Filters 42%")
        expect("...its bar", v.headerPhaseShare(firstSync), 42)
        var scanning = mainnet({ state: "syncing", synced: false, birthday: 481824, authority: { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3 },
                                 kyoto: { scanned: 501959, phase: "filters" } })
        expect("chip: Kyoto's scan", v.syncChip(scanning), "Filters 4%")
        scanning.kyoto.scanned = null
        expect("...before its first block", v.syncChip(scanning), "Checking filters…")
        scanning.authority.tipAgeSecs = 126000
        scanning.kyoto = { scanned: null, phase: "filter_headers", progress: 0.03, headers: 974330 }
        expect("...an old tip behind its headers: no stall", v.syncChip(scanning), "Checking filters…")
        expect("an estimate behind the chain: no share", v.headersShare({ have: 900000, target: null }, 935424, 935000), null)
        expect("chip without a height, as before", v.syncChip(mainnet({ state: "syncing", authority: { height: null, peers: 2 } })), "Connecting…")
        expect("servers not asked yet: connecting, no second line", v.syncLabel(mainnet({ authority: { kind: "electrum_headers", height: 935500, peers: 0, asked: false } })),
               "Connecting to the chain's sources… · last known block 935,500")
        expect("no authority line any more", find(view.item, "authorityLine", 0), null)
        // A Kyoto restart still dialling connects; it reads as isolated once its dials failed and it stopped.
        var servers = [{ id: "fee", state: "ok", tip: 974135, operator: "a" }]
        var restart = mainnet({ state: "syncing", synced: false, walletTip: 974135, birthday: 969082, rescanFrom: 969082,
                                authority: { kind: "kyoto", height: 974135, tipAgeSecs: 300, peers: 0, asked: true },
                                kyoto: { running: true, scanned: 970000, phase: "syncing", progress: 0 } })
        expect("a Kyoto start dialling", v.syncLabel(restart), "Connecting to the chain's sources… · last known block 974,135")
        expect("...its chip", v.syncChip(restart), "Connecting…")
        restart.kyoto.running = false
        expect("its dials failed: no peer answered", v.syncLabel(restart), "Can't confirm the chain · no peer answered · last block 974,135, 5 min old")
        expect("...its chip", v.syncChip(restart), "No answer")
        restart.kyoto.running = true
        restart.authority.kind = "electrum_headers"
        expect("servers' headers with none agreeing: not Kyoto's dials", v.syncChip(restart), "No answer")
        restart.authority = { kind: "kyoto", height: 974135, tipAgeSecs: 300, peers: 3, asked: true }
        restart.kyoto = { running: true, scanned: 969582, phase: "filters", progress: 0.34 }
        restart.syncPercent = 34
        expect("a rescan the sync line counts", v.syncLabel(restart), "Checking block filters… block 969,582 of 974,135 · 9% · from 3 Bitcoin peers")
        expect("...so the rescan pane gives no figure", v.syncLineCounts(restart), true)
        restart.kyoto.scanned = 974134
        expect("a finished scan: the rescan pane counts", v.syncLineCounts(restart), false)
        expect("history from Kyoto", v.historyName("kyoto"), "Bitcoin peers")
        expect("...from your node", v.historyName("local_node"), "your node")
        expect("...from your node at an address", v.historyName("rpc_node"), "your node")
        expect("...from a server not listed", v.historyName("gone"), "gone")
        expect("history line: Kyoto", v.historyLine("kyoto"), "Payments found on this device, through block filters")
        expect("history line: your node", v.historyLine("rpc_node"), "Payments found through your node")
        expect("history line: a server", v.historyLine("gone"), "Payments looked up at gone")
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
            [{ state: "unknown", abandoned: true, offer: [] }, "forgotten", "Forgotten", 2],
            [{ state: "failed", errorCode: "dust", error: "The smallest amount this address can receive is 294 sats." }, "failed", "The amount is too small for this address", 0],
            [{ state: "failed", errorCode: "failed", error: "cannot build the send: Output below the dust limit: 0" }, "failed", "The amount is too small for this address", 0],
            // Failed after the signer approved it: the lane marks Broadcast, not Approve.
            [{ state: "failed", errorCode: "not_sent", error: "not sent: no peer reached over Tor took the transaction (timed out)", summary: {},
               approval: "settled", sawSettled: true, sawBroadcasting: true }, "failed", "Not sent: no peer took it over Tor", 2],
            [{ state: "failed", errorCode: "no_route", error: "no broadcast source answered", summary: {}, sawSettled: true }, "failed", "No source can broadcast it", 2],
            [{ state: "failed", errorCode: "not_sent", summary: {}, sawBroadcasting: true,
               error: "not sent: no peer reached over Tor took the transaction (Tor can't be reached at 127.0.0.1:9050: refused)" }, "failed", "Not sent: no peer took it over Tor", 2]
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
        expect("not sent: nothing went out", v.sendDetail(sends[25][0]), "Nothing went out: the peers tried over Tor didn't take it in time. Try again.")
        expect("...Tor down says so", v.sendDetail(sends[27][0]), "Nothing went out: Tor can't be reached. Try again once it connects.")
        expect("...and can be tried again", v.canRetry(sends[25][0]), true)
        var unknownSend = { state: "unknown", offer: ["rebroadcast", "request_fee_bump", "abandon_send"] }
        expect("offer forget", v.offers(unknownSend, "abandon_send"), true)
        expect("offer nothing once forgotten", v.offers({ state: "unknown", abandoned: true, offer: [] }, "rebroadcast"), false)
        expect("old backend offers", v.offers({ state: "unknown" }, "rebroadcast"), true)
        expect("detail expired", v.sendDetail(sends[8][0]), "The signer app never showed the request, so it expired. Ask again to send it once more.")
        expect("detail dust: the core's words", v.sendDetail(sends[23][0]), "The smallest amount this address can receive is 294 sats.")
        expect("detail dust from an older core: never the library's text", v.sendDetail(sends[24][0]), "The amount is below the smallest this address can receive.")
        expect("no retry dust", v.canRetry(sends[23][0]), false)

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
                    { id: "b", kind: "electrum", use: true, operator: "example" }, { id: "c", kind: "electrum", use: false, operator: "other" }]
        expect("chain servers", v.chainSourcesOf(list).map(function (x) { return x.id }), ["a", "b"])
        expect("chain operators", v.operatorsOf(v.chainSourcesOf(list)), ["Example"])
        list[0].use = true
        expect("chain kyoto", v.chainSourcesOf(list).map(function (x) { return x.id }), ["kyoto"])

        // No badge and no roles: a source's state, and why it is not fine.
        expect("no badge any more", typeof v.walletOverall, "undefined")
        expect("source line, no roles", v.walletSourceLine({ state: "ok", roles: ["chain", "history"], history: true }), "ok")
        expect("suspect line", v.walletSourceLine({ state: "suspect", suspect: true, suspectReason: "served invalid headers", error: "x" }), "suspect: served invalid headers")
        expect("failing line", v.walletSourceLine({ state: "failing", roles: ["chain"], error: "connection refused" }), "failing · connection refused")
        expect("behind line", v.walletSourceLine({ state: "stale", roles: ["check"] }), "behind")
        expect("plain line", v.walletSourceLine({ state: "ok", roles: ["chain"], encrypted: false }), "ok · not encrypted")

        expect("authority kyoto", v.authorityName({ authority: { kind: "kyoto", peers: 2 } }), "2 Bitcoin peers")
        expect("authority node", v.authorityName({ authority: { kind: "local_node" } }), "your node")
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

        // Kyoto's matched blocks over Tor: nothing goes direct while Tor is down.
        expect("tor waits", v.kyotoTorLine({ kyoto: { tor: { pending: 3, waiting: true } } }), "Waiting for Tor: 3 blocks with your payments not fetched yet")
        expect("tor waits, nothing pending", v.kyotoTorLine({ kyoto: { tor: { pending: 0, waiting: true } } }), "Waiting for Tor")
        expect("tor fetching", v.kyotoTorLine({ kyoto: { tor: { pending: 1, waiting: false } } }), "Fetching 1 block with your payments over Tor")
        expect("tor idle", v.kyotoTorLine({ kyoto: { tor: { pending: 0, waiting: false } } }), "")
        expect("no split", v.kyotoTorLine({ kyoto: { tor: null } }), "")
    }

    // What renders, against the fake backend; each step runs after the previous one settled.
    property var steps: [
        function (v) {
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet4", "signet", "regtest"], active: "regtest" })
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
            fake.accountsJson = JSON.stringify([
                {id:"g_test",family:"bitcoin_taproot",chain:"test",label:"Test wallet",signer:"keystore_module",available:true},
                {id:"g_main",family:"bitcoin",chain:"main",label:"Main wallet",signer:"keystore_module",available:true},
                // Routed Keycard rows (signer manager 3ef020c): seed-centric, unplugged; one kept the Shell's copy.
                {id:"keycard-cdcdcdcd-84-1-0",family:"bitcoin",chain:"test",label:"Card account",signer:"keycard_module",available:false,
                 origin:{devices:[{kind:"keycard",id:"ab".repeat(32),name:"Keycard"}],phrase:{id:"seed:"+"cd".repeat(32),name:"Black Card"}}},
                {id:"shell-cdcdcdcd-86-1-0",family:"bitcoin_taproot",chain:"test",label:"Taproot",signer:"keycard_shell_module",available:false,
                 origin:{devices:[{kind:"keycard",id:"ab".repeat(32),name:"Keycard"}],phrase:{id:"seed:"+"cd".repeat(32),name:"Black Card"}}},
                {id:"g_gone",family:"bitcoin",chain:"test",label:"Gone",signer:"keystore_module",available:false},
                {id:"0x123",family:"evm",chain:"test",available:true}])
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "socks5h://127.0.0.1:9050", walletOpen: false, torUse: "identifying", torUseChosen: true,
                sources: [{ id: "kyoto", kind: "kyoto", url: "p2p://peer-list", operator: "peers", label: "Bitcoin peers", use: false, history: false, tor: true, lan: false, route: "tor" },
                          { id: "electrum.example", kind: "electrum", url: "ssl://electrum.example:50002", operator: "example", label: "Example Electrum", use: true, history: false, tor: true, lan: false, route: "tor" }],
                exposes: [], withoutTor: [] })
        },
        function (v) {
            expect("open page", shown("openPage"), true)
            expect("form", shown("openForm"), true)
            expect("no tabs", shown("walletTabs"), false)
            expect("status line", prop("statusLine", "text"), "No wallet open")
            expect("the network, picked in the header", prop("networkPicker", "displayText") + " " + prop("networkPicker", "enabled"), "regtest true")
            expect("...no second picker on the page", find(view.item, "networkBox", 0), null)
            expect("no password field", find(view.item, "openPasswordField", 0), null)
            expect("only Bitcoin accounts on the network", v.accountsOnNetwork.map(function(a) { return a.id }), ["g_test", "keycard-cdcdcdcd-84-1-0", "shell-cdcdcdcd-86-1-0", "g_gone"])
            v.selectAccount(v.accountsOnNetwork[3])
            expect("an unavailable keystore account is not selected", v.selectedAccount, null)
            expect("...and does not open", fake.last("selectAccount"), null)
            expect("...and says why", v.availabilityLine(v.accountsOnNetwork[3]), " · unavailable")
            expect("...with no device reason", v.reasonLine(v.accountsOnNetwork[3]), "")
            // A device signs by itself: its wallet opens while it is unplugged.
            v.selectAccount(v.accountsOnNetwork[1])
            expect("an unplugged Keycard's account is selected", v.selectedAccount.id, "keycard-cdcdcdcd-84-1-0")
            expect("the provider is Keycard and its seed wallet", v.accountProvider(v.selectedAccount), "Keycard · Black Card")
            expect("...and its row says it is not connected", v.availabilityLine(v.selectedAccount), " · Keycard not connected")
            expect("a quiet note says what works", prop("deviceAbsentNote", "text"),
                   "Keycard not connected · you can view this wallet; sending needs the device")
            expect("...and what signing needs", prop("deviceReasonLine", "text"),
                   "Insert Black Card in a reader or connect a Keycard Shell to sign")
            expect("a row that kept the Shell's copy still reads Keycard", v.accountProvider(v.accountsOnNetwork[2]), "Keycard · Black Card")
            expect("Taproot names the applet it needs", v.reasonLine(v.accountsOnNetwork[2]),
                   "Insert Black Card in a reader or connect a Keycard Shell to sign. Taproot needs a Keycard with applet 4.0")
            expect("an unrouted Keycard row is still Keycard", v.accountProvider({ signer: "keycard_shell_module" }), "Keycard")
            expect("any other signer is Signer", v.accountProvider({ signer: "mock_device_signer" }), "Signer")
            expect("no row names a module", v.accountsOnNetwork.filter(function (a) {
                return (v.accountProvider(a) + v.availabilityLine(a) + v.reasonLine(a)).indexOf("_module") >= 0 }).length, 0)
            expect("Open is enabled", prop("openWalletButton", "enabled"), true)
            find(view.item, "openWalletButton", 0).clicked()
        },
        function (v) {
            // The wallet keeps each account's birthday: its first open on a network asks for it first.
            expect("a first open asks when it was first used", prop("birthdaySheet", "visible") && prop("birthdaySheet", "title"),
                   "When was this account first used?")
            expect("...before opening", fake.last("selectAccount"), null)
            expect("...offering a new account", prop("birthdayNew", "visible"), true)
            expect("...with no day yet", prop("confirmBirthdayButton", "enabled") + " " + prop("confirmBirthdayButton", "text"), "false Open")
            find(view.item, "birthdayNew", 0).checked = true
            find(view.item, "confirmBirthdayButton", 0).clicked()
            expect("a new account opens from today", fake.last("selectAccount"), ["selectAccount", "keycard-cdcdcdcd-84-1-0", v.todayUtc()])
            find(view.item, "accountPicker", 0).currentIndex = 0
            find(view.item, "accountPicker", 0).activated(0)
            expect("selection alone does not open", fake.count("selectAccount"), 1)
            expect("chosen account stays selected", v.selectedAccount.id, "g_test")
            find(view.item, "openWalletButton", 0).clicked()
        },
        function (v) {
            expect("another account's first open asks too", prop("birthdaySheet", "visible"), true)
            find(view.item, "birthdayDateField", 0).text = "2024-04-20"
            find(view.item, "confirmBirthdayButton", 0).clicked()
            expect("...and opens it from that day", fake.last("selectAccount"), ["selectAccount", "g_test", "2024-04-20"])
            fake.walletsJson = JSON.stringify([{ group: "g_test", family: "bitcoin", network: "regtest" }])
        },
        function (v) {
            expect("the sheet closed", prop("birthdaySheet", "visible"), false)
            find(view.item, "openWalletButton", 0).clicked()
            expect("an account opened before opens at once, with no day", fake.last("selectAccount"), ["selectAccount", "g_test", ""])
            expect("...asking nothing", prop("birthdaySheet", "visible"), false)
            fake.walletsJson = "[]"
            find(view.item, "openWalletButton", 0).clicked()
        },
        function (v) {
            find(view.item, "birthdayUnknown", 0).checked = true
            find(view.item, "confirmBirthdayButton", 0).clicked()
            expect("not knowing opens with none", fake.last("selectAccount"), ["selectAccount", "g_test", ""])
            expect("...four opens in all", fake.count("selectAccount"), 4)
            find(view.item, "manageAccountsButton", 0).clicked()
            expect("management goes to Keystore", logos.requests[logos.requests.length-1].intent, "evm.accounts.manage")
            fake.pendingJobKind = "open"
            fake.busy = true
            fake.statusJson = JSON.stringify({ state: "awaiting_open", network: "regtest", activeNetwork: "regtest", openHandle: "sma_t1" })
        },
        function (v) {
            expect("keys panel", shown("keysWaitPanel"), true)
            expect("keys title", prop("keysWaitTitle", "text"), "Waiting for the Signer app")
            expect("form hidden", shown("openForm"), false)
            var asked = logos.requests.filter(function (q) { return q.intent === "wallets.unlock" })
            expect("the Signer app is asked to allow the open", asked.length === 1 ? asked[0].params.openHandle : asked.length, "sma_t1")
            logos.lastCallback({ ok: false, error: "unavailable" })
            fake.statusJson = JSON.stringify({ state: "awaiting_open", network: "regtest", activeNetwork: "regtest", openHandle: "sma_t1", authority: {} })
        },
        function (v) {
            expect("keys asked once", logos.requests.filter(function (q) { return q.intent === "wallets.unlock" }).length, 1)
            expect("keys note", String(prop("keysNote", "text")).indexOf("The Signer app is not installed") === 0, true)
            find(view.item, "cancelOpenButton", 0).clicked()
            expect("cancel closes", fake.count("closeWallet"), 1)
            fake.pendingJobKind = ""
            fake.busy = false
            fake.statusJson = scene.syncedMainnet
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "125000000", confirmedBtc: "1.25000000", waiting: "50000", pending: "30000",
                                                 sent: "0", immature: "0", tooSmall: { count: 2, sat: "540", btc: "0.00000540" } })
            fake.feeRatesJson = JSON.stringify({ fast: 12, normal: 6, slow: 2, minimum: 1, sources: ["electrum.example"] })
            fake.historyJson = JSON.stringify({ page: 0, pageSize: 50, total: 3, rows: [
                { txid: "aa".repeat(32), intent: "receive", amountSat: "30000", state: "pending", reportedBy: "electrum.example", confirmations: 0 },
                { txid: "bb".repeat(32), intent: "send", amountSat: "60000", feeSat: "141", state: "sent", counterparties: ["bcrt1qpay"], confirmations: 0 },
                { txid: "cc".repeat(32), intent: "receive", amountSat: "125000000", state: "confirmed", height: 100, confirmations: 50 }] })
        },
        function (v) {
            expect("tabs", shown("walletTabs"), true)
            expect("synced line", prop("syncLine", "text"), "Synchronized · block 935,500 · from 2 Electrum servers")
            expect("confirmed", prop("confirmedCard", "value"), "1.25 BTC")
            expect("waiting row", shown("waitingRow"), true)
            expect("pending row", shown("pendingRow"), true)
            expect("too small row", prop("tooSmallRowAmount", "text"), "2 coins, 0.0000054 BTC")
            expect("sent row", shown("sentRow"), true)
            expect("home speed up", shown("homeSpeedUp_" + "bb".repeat(32)), true)
            expect("the tip watch, in the servers' words", v.alertMessage({ kind: "authority_behind", source: "electrum.example" }),
                   "Example Electrum has seen blocks the Electrum servers haven't sent for 30 minutes; the Electrum servers may be cut off from the network.")
            expect("your node, asked alone, in its own report's words",
                   v.alertMessage({ kind: "authority_behind", source: "local", detail: "your node has had no new block for 120 minutes" }),
                   "Your node has had no new block for 120 minutes; it may be cut off from the network.")
            var st = JSON.parse(scene.syncedMainnet)
            st.authority = { kind: "kyoto", height: 935500, tipAgeSecs: 240, peers: 8 }
            fake.statusJson = JSON.stringify(st)
            fake.alertsJson = JSON.stringify([{ source: "electrum.example", kind: "authority_behind", detail: "3 checked blocks ahead for half an hour", at: 1 }])
        },
        function (v) {
            expect("the tip watch's banner", prop("alertBanner", "title"), "Your wallet may be behind")
            expect("...in the peers' words", prop("alertBanner", "message"),
                   "Example Electrum has seen blocks your peers haven't sent for 30 minutes; your peers may be cut off from the network.")
            expect("...from 8 Bitcoin peers", prop("syncLine", "text"), "Synchronized · block 935,500 · from 8 Bitcoin peers")
            fake.alertsJson = "[]"
            fake.statusJson = scene.syncedMainnet
            fake.healthJson = JSON.stringify({ overall: "offline", sources: [], wallet: { sources: [
                { id: "regtest-0", url: "tcp://127.0.0.1:61701", state: "ok", suspect: false, roles: ["chain", "history"], history: true },
                { id: "regtest-1", url: "tcp://127.0.0.1:61711", state: "ok", suspect: false, roles: ["chain"] }] } })
        },
        function (v) {
            expect("no sources badge", find(view.item, "healthBadge", 0), null)
            expect("wallet's own servers", v.walletOnlySources.map(function (s) { return s.id }), ["regtest-0", "regtest-1"])
            expect("a server's line, through its delegate, without roles", prop("walletSourceState_regtest-0", "text"), "ok")
            fake.healthJson = ""
            var st = JSON.parse(scene.syncedMainnet)
            st.authority.peers = 0
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("rendered: no peers is never synchronized", prop("syncLine", "text"), "Can't confirm the chain · no server answered · last block 935,500, 4 min old")
            var st = JSON.parse(scene.syncedMainnet)
            st.synced = false
            st.authority = { kind: "electrum_headers", height: 935432, tipAgeSecs: 75600, peers: 0, asked: false }
            fake.statusJson = JSON.stringify(st)
            fake.healthJson = JSON.stringify({ overall: "ok", sources: [], wallet: { sources: [
                { id: "regtest-0", state: "unknown", suspect: false, roles: ["chain", "history"] }, { id: "regtest-1", state: "unknown", suspect: false, roles: ["chain"] }] } })
        },
        function (v) {
            expect("rendered: before the first answer", prop("syncLine", "text"), "Connecting to the chain's sources… · last known block 935,432")
            expect("...the chip", prop("syncChip", "text"), "Connecting…")
            fake.healthJson = ""
            var st = JSON.parse(scene.syncedMainnet)
            st.state = "syncing"
            st.synced = false
            st.walletTip = 84000
            st.authority = { kind: "electrum_headers", height: 84000, tipAgeSecs: 50000000, peers: 1, asked: true, headers: { have: 84000, target: 157000 } }
            fake.statusJson = JSON.stringify(st)
        },
        function (v) {
            expect("rendered: a header download", prop("syncLine", "text"), "Reading the chain's headers… 84,000 of 157,000")
            expect("...the chip", prop("syncChip", "text"), "Headers 53%")
            expect("...with a bar for the header phase", shown("headersProgress") && !prop("headersProgress", "indeterminate"), true)
            var scan = JSON.parse(scene.syncedMainnet)
            scan.state = "syncing"
            scan.synced = false
            scan.walletTip = 973920
            scan.birthday = 481824
            scan.authority = { kind: "kyoto", height: 973920, tipAgeSecs: 1500, peers: 3, asked: true }
            scan.kyoto = { scanned: 501959, phase: "filters", progress: 0.3 }
            fake.statusJson = JSON.stringify(scan)
        },
        function (v) {
            expect("rendered: Kyoto's scan behind its headers", prop("syncLine", "text"), "Checking block filters… block 501,959 of 973,920 · 4% · from 3 Bitcoin peers")
            expect("...the chip", prop("syncChip", "text"), "Filters 4%")
            expect("...its bar, not the backend's 100%", shown("syncProgress") && !prop("syncProgress", "indeterminate")
                   && Math.abs(prop("syncProgress", "value") - 0.04) < 1e-9, true)
            var rescan = JSON.parse(fake.statusJson)
            rescan.rescanFrom = 481824
            rescan.syncPercent = 30
            fake.statusJson = JSON.stringify(rescan)
        },
        function (v) {
            expect("rendered: a Kyoto rescan, one figure", prop("syncLine", "text"), "Checking block filters… block 501,959 of 973,920 · 4% · from 3 Bitcoin peers")
            expect("...the rescan pane names where it starts", prop("rescanLine", "text"), "Rescanning from block 481,824")
            expect("...one bar", shown("syncProgress") && !shown("rescanProgress"), true)
            fake.statusJson = scene.syncedMainnet
            fake.feeRatesJson = ""
            v.selectTab(1)
        },
        function (v) {
            expect("no estimate: said so", shown("feeUnknownNote"), true)
            expect("...in plain words", prop("feeUnknownNote", "text"), "Fee estimate not available yet. Give a rate of your own, in sat/vB.")
            expect("...no preset offered", shown("feeNormal"), false)
            expect("...a rate of your own", prop("feeCustomChoice", "checked"), true)
            fake.feeRatesJson = JSON.stringify({ fast: 1, normal: 1, slow: 1, minimum: 1, sources: ["electrum.example"], estimated: true })
        },
        function (v) {
            expect("a quiet network, said plainly with its source", prop("feeQuietNote", "text"), "The network is quiet: every speed costs 1 sat/vB. Estimate from Example Electrum.")
            expect("...the presets back", shown("feeNormal"), true)
            expect("...no unknown note", shown("feeUnknownNote"), false)
            expect("...no floor note", shown("feeFloorNote"), false)
            fake.feeRatesJson = JSON.stringify({ fast: 1, normal: 1, slow: 1, minimum: 1, sources: [], estimated: true, basis: "floor" })
        },
        function (v) {
            expect("signet's floor, said as the peers' lowest rate", prop("feeFloorNote", "text"), "Fees: the lowest rate peers relay (signet has no useful fee estimates).")
            expect("...not as a quiet network", shown("feeQuietNote"), false)
            expect("...the presets stay", shown("feeNormal"), true)
            fake.feeRatesJson = JSON.stringify({ fast: 1, normal: 1, slow: 1, minimum: 1, sources: ["electrum.example"], estimated: true, basis: "mempool" })
        },
        function (v) {
            expect("a quiet mempool, named as the source", prop("feeQuietNote", "text"), "The network is quiet: every speed costs 1 sat/vB. Estimate from Example Electrum's mempool.")
            fake.feeRatesJson = JSON.stringify({ fast: 1, normal: 1, slow: 1, minimum: 1, sources: ["electrum.example", "electrum.other"], estimated: true, basis: "mempool" })
        },
        function (v) {
            expect("...two of them", prop("feeQuietNote", "text"), "The network is quiet: every speed costs 1 sat/vB. Estimate from the mempools of Example Electrum, electrum.other.")
            fake.feeRatesJson = JSON.stringify({ fast: 12, normal: 6, slow: 2, minimum: 1, sources: ["electrum.example"], estimated: true })
        },
        function (v) {
            expect("levels apart: no quiet note", shown("feeQuietNote"), false)
            v.selectTab(2)
            fake.receiveJson = JSON.stringify({ address: "bcrt1qfirst", index: 0, uri: "bitcoin:bcrt1qfirst", amount: "", gap: { unused: 20, gapLimit: 20 } })
        },
        function (v) {
            expect("New address at the gap limit, before the list is read: said in the button's place", prop("receiveAtGapNote", "text"),
                   "Pay into one of these first, or raise the gap limit in Settings.")
            expect("...no button", shown("newAddressButton"), false)
            expect("...the count beside it", prop("receiveUnusedCount", "text"), "20 of 20 unused")
            expect("...and shows the first unused one", prop("receiveAddress", "text"), "bcrt1qfirst")
            fake.receiveJson = JSON.stringify({ address: "bcrt1qfirst", index: 0, uri: "bitcoin:bcrt1qfirst", amount: "" })
            fake.addressesJson = JSON.stringify({ unused: 2, gapLimit: 20, addresses: [
                { index: 0, address: "bcrt1qfirst", used: false, receivedSat: "0", receivedBtc: "0.00000000", label: "" },
                { index: 1, address: "bcrt1qsecond", used: false, receivedSat: "0", receivedBtc: "0.00000000", label: "Rent from Ana" },
                { index: 2, address: "bcrt1qpaid", used: true, receivedSat: "125000000", receivedBtc: "1.25000000", label: "Salary" }] })
        },
        function (v) {
            expect("the list read: New address back", shown("newAddressButton") && !shown("receiveAtGapNote"), true)
            expect("...the count from it", prop("receiveUnusedCount", "text"), "2 of 20 unused")
            expect("the list's title", shown("receiveListTitle"), true)
            expect("the one on screen is Shown", prop("receiveRowState_0", "text"), "Shown")
            expect("...with no Show", shown("receiveRowShow_0"), false)
            expect("another unused one", prop("receiveRowState_1", "text"), "Unused")
            expect("...offers Show", shown("receiveRowShow_1"), true)
            expect("a label", prop("receiveRowLabel_1", "text"), "Rent from Ana")
            expect("...or none", prop("receiveRowLabel_0", "text"), "No label")
            expect("the index", prop("receiveRowIndex_1", "text"), "#1")
            expect("the address, shortened in the middle", prop("receiveRowAddress_1", "elide"), Text.ElideMiddle)
            expect("copy carries the address", prop("receiveRowCopy_1", "value"), "bcrt1qsecond")
            expect("used rows wait behind the toggle", find(view.item, "receiveRow_2", 0), null)
            expect("...which counts them", prop("showUsedButton", "text"), "Show used (1)")
            expect("...no reuse note yet", shown("usedNote"), false)
            find(view.item, "receiveRowShow_1", 0).clicked()
            expect("Show asks for that address", fake.last("showAddress"), ["showAddress", 1])
            find(view.item, "newAddressButton", 0).clicked()
            expect("New address asks the backend", fake.count("newAddress"), 1)
            find(view.item, "showUsedButton", 0).clicked()
        },
        function (v) {
            expect("newest first", prop("receiveRow_1", "y") < prop("receiveRow_0", "y"), true)
            expect("the toggle, open", prop("showUsedButton", "text"), "Hide used")
            expect("...the reuse note", prop("usedNote", "text"), "Reusing an address that was paid links your payments to each other on-chain.")
            expect("a used row says what it received", prop("receiveRowState_2", "text"), "Received 1.25 BTC")
            expect("...dimmed", prop("receiveRow_2", "opacity") < 1, true)
            expect("...below the toggle", prop("receiveRow_2", "y") > prop("showUsedButton", "y"), true)
            expect("...never offered to show again", shown("receiveRowShow_2"), false)
            expect("no editor open", shown("labelEditor_0") || shown("labelEditor_1"), false)
            find(view.item, "receiveRowLabelButton_0", 0).clicked()
        },
        function (v) {
            expect("Label opens its editor in the row", shown("labelEditor_0"), true)
            expect("...only that row's", shown("labelEditor_1"), false)
            expect("...empty for an unlabelled one", prop("labelField_0", "text"), "")
            expect("...64 characters at most", find(view.item, "labelField_0", 0).textInput.maximumLength, 64)
            find(view.item, "labelField_0", 0).text = " Savings jar "
            find(view.item, "saveLabelButton_0", 0).clicked()
            expect("Save sends the label", fake.last("setAddressLabel"), ["setAddressLabel", 0, " Savings jar "])
        },
        function (v) {
            expect("saved: the editor closes", shown("labelEditor_0"), false)
            expect("...and the row shows it", prop("receiveRowLabel_0", "text"), "Savings jar")
            fake.addressLabelReply = "a label is at most 64 characters"
            find(view.item, "receiveRowLabelButton_1", 0).clicked()
        },
        function (v) {
            expect("the editor starts from the label", prop("labelField_1", "text"), "Rent from Ana")
            find(view.item, "saveLabelButton_1", 0).clicked()
        },
        function (v) {
            expect("a refusal is said in the editor", prop("labelNote_1", "text"), "a label is at most 64 characters")
            expect("...which stays open", shown("labelEditor_1") && shown("labelNote_1"), true)
            fake.addressLabelReply = ""
            find(view.item, "clearLabelButton_1", 0).clicked()
            expect("Clear sends no label", fake.last("setAddressLabel"), ["setAddressLabel", 1, ""])
        },
        function (v) {
            expect("cleared", prop("receiveRowLabel_1", "text"), "No label")
            expect("...the editor closed", shown("labelEditor_1"), false)
            var n = fake.count("setAddressLabel")
            find(view.item, "receiveRowLabelButton_0", 0).clicked()
            find(view.item, "cancelLabelButton_0", 0).clicked()
            expect("Cancel closes it and saves nothing", [shown("labelEditor_0"), fake.count("setAddressLabel")], [false, n])
            var rows = []
            for (var i = 0; i < 20; i++) rows.push({ index: i, address: "bcrt1qunused" + i, used: false, receivedSat: "0", receivedBtc: "0.00000000", label: "" })
            fake.addressesJson = JSON.stringify({ unused: 20, gapLimit: 20, addresses: rows })
        },
        function (v) {
            expect("the list at the gap limit: said in the button's place", shown("receiveAtGapNote") && !shown("newAddressButton"), true)
            expect("...the count", prop("receiveUnusedCount", "text"), "20 of 20 unused")
            expect("...no used toggle without used rows", shown("showUsedButton"), false)
            fake.addressesJson = ""
            fake.receiveJson = JSON.stringify({ address: "bcrt1qnext", index: 1, uri: "bitcoin:bcrt1qnext", amount: "" })
        },
        function (v) {
            expect("a fresh one: no note", shown("receiveAtGapNote"), false)
            expect("...no count before the list is read", shown("receiveUnusedCount"), false)
            v.selectTab(1)
            find(view.item, "sendRecipientField", 0).text = "bcrt1qrecipient"
            v.checkRecipient()
            find(view.item, "sendAmountField", 0).text = "0.0006"
        },
        function (v) {
            expect("recipient badge", prop("recipientBadge", "text"), "native segwit")
            expect("amount note", prop("amountNote", "text"), "= 60,000 sats")
            expect("no dust note", shown("dustNote"), false)
            find(view.item, "sendAmountField", 0).text = "0.00000005"
        },
        function (v) {
            expect("below the address's dust limit, said plainly", prop("dustNote", "text"), "The smallest amount this address can receive is 294 sats.")
            expect("...under the amount", shown("dustNote") && prop("amountNote", "text") === "= 5 sats", true)
            expect("...and no review", prop("reviewButton", "enabled"), false)
            find(view.item, "sendAmountField", 0).text = "0.00000294"
        },
        function (v) {
            expect("the limit itself is enough", shown("dustNote"), false)
            expect("...review again", prop("reviewButton", "enabled"), true)
            // Send max of 400 sats: at 6 sat/vB the fee takes it all, at 1 sat/vB about 291 are left.
            scene.keptBalances = fake.balancesJson
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "400", waiting: "0", pending: "0", sent: "0", immature: "0", tooSmall: { count: 0, sat: "0" } })
            v.sendMax = true
        },
        function (v) {
            expect("send max the fee eats", prop("dustNote", "text"), "The fee would take all of it. The smallest amount this address can receive is 294 sats.")
            expect("...no review", prop("reviewButton", "enabled"), false)
            v.feeChoice = "custom"
            find(view.item, "feeCustomField", 0).text = "1"
        },
        function (v) {
            expect("send max left below the limit", prop("dustNote", "text"),
                   "After the fee, about 291 sats would be left. The smallest amount this address can receive is 294 sats.")
            expect("...no review", prop("reviewButton", "enabled"), false)
            fake.balancesJson = JSON.stringify({ busy: false, confirmed: "404", waiting: "0", pending: "0", sent: "0", immature: "0", tooSmall: { count: 0, sat: "0" } })
        },
        function (v) {
            expect("send max a vbyte's worth above: left to the core", shown("dustNote"), false)
            expect("...review", prop("reviewButton", "enabled"), true)
            fake.balancesJson = scene.keptBalances
            v.sendMax = false
            v.feeChoice = "normal"
            find(view.item, "feeCustomField", 0).text = ""
            find(view.item, "sendAmountField", 0).text = "0.0006"
        },
        function (v) {
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
            expect("operator diagnostic under the chain choice, not in Advanced", shown("oneOperatorNotice"), true)
            expect("...the choice itself locked", prop("chainChoice_electrum", "enabled"), false)
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
            expect("no public-service group", find(view.item, "publicServicesHeading", 0), null)
            expect("no Esplora group", find(view.item, "esploraSources", 0), null)
            expect("advanced starts collapsed", shown("advancedSourcesPane"), false)
            expect("details start collapsed", shown("sourceOptions_electrum.example"), false)
            expect("Electrum servers grouped", prop("electrumSources", "entries").map(function (s) { return s.id }), ["electrum.example"])
            expect("no custom server kind to pick", find(view.item, "addSourceKind", 0), null)
            find(view.item, "sourceDetails_electrum.example", 0).clicked()
            expect("Details expands the selected row", shown("sourceOptions_electrum.example"), true)
            expandAdvanced()
            expect("operator diagnostic", shown("oneOperatorNotice"), true)
            find(view.item, "historySwitch_electrum.example", 0).clicked()
        },
        function (v) {
            expect("history changes without another privacy prompt", fake.count("setSource"), 1)
            expect("history on", fake.last("setSource"), ["setSource", "electrum.example", JSON.stringify({ history: true })])
            find(view.item, "torSwitch_electrum.example", 0).clicked()
        },
        function (v) {
            expect("tor off", fake.last("setSource"), ["setSource", "electrum.example", JSON.stringify({ tor: false })])
            var s = JSON.parse(fake.sourcesJson)
            s.sources[1].tor = false
            s.sources[1].route = "direct"
            s.withoutTor = [{ id: "electrum.example", url: "ssl://electrum.example:50002", operator: "example", lan: false }]
            fake.sourcesJson = JSON.stringify(s)
        },
        function (v) {
            scene.keptSources = fake.sourcesJson
            var s = JSON.parse(fake.sourcesJson)
            s.sources[1].suspect = true
            fake.sourcesJson = JSON.stringify(s)
        },
        function (v) {
            expect("a suspect server keeps the Electrum choice, its list open on its row",
                   [prop("chainChoice_electrum", "checked"), shown("electrumPane"), shown("suspectBadge_electrum.example")], [true, true, true])
            fake.sourcesJson = scene.keptSources
        },
        function (v) {
            expect("details survive a source refresh", shown("sourceOptions_electrum.example"), true)
            expect("without tor badge", shown("withoutTorBadge_electrum.example"), true)
            // One decision top to bottom: your own node, then public sources and everything under them.
            var y = function (name) { var o = find(view.item, name, 0); return o.mapToItem(view.item, 0, 0).y }
            expect("sections in order", [y("chainHeading") < y("chainChoice_node"), y("chainChoice_node") < y("chainChoice_public"),
                                         y("chainChoice_public") < y("chainChoice_peers"), y("chainChoice_electrum") < y("torUse_all"),
                                         y("torUse_none") < y("whichTor_builtIn"), y("whichTor_own") < y("feesHeading"),
                                         y("feesHeading") < y("pendingHeading"), y("pendingHeading") < y("advancedSourcesButton")],
                   [true, true, true, true, true, true, true, true])
            expect("public sources: the Electrum servers in use", [prop("chainChoice_public", "checked"), prop("chainChoice_electrum", "checked")], [true, true])
            expect("...your own node's pane closed", shown("ownNodePane"), false)
            expect("...the network it applies to", prop("chainNetworkLine", "text"), "For regtest. Each network has its own setting.")
            expect("...and the rules that hold in every mode", prop("torUseEveryMode", "text"), v.torUseEveryMode)
            expect("the sheet is Node", [prop("networkSheet", "title"), prop("networkSettingsButton", "text")], ["Node", "Node"])
            expect("with Electrum servers, Only what identifies you says it is Everything",
                   v.torUseCopyOf("identifying", "electrum").happens.indexOf("With Electrum servers this works like Everything"), 0)
            expect("...and the options read so", findAll(view.item, "torUse_identifying", 0, []).length > 0
                   && find(view.item, "torUseSettings", 0).visible, true)
            expect("...listed under Fees, open", shown("electrumPane"), true)
            expect("fees from the server in use", prop("feeSourceLine", "text"), "From Example Electrum.")
            expect("payments need a server with History on", prop("pendingLine", "text"),
                   "With Electrum servers, the wallet finds payments only at a server with History on, which learns your addresses.")
            var sets = function (from) { return fake.calls.filter(function (c) { return c[0] === "setSource" }).slice(from) }
            var before = fake.count("setSource")
            find(view.item, "chainChoice_peers", 0).clicked()
            expect("Bitcoin peers: Kyoto on, the fee server left on", sets(before), [["setSource", "kyoto", JSON.stringify({ use: true })]])
            expect("...picked at once", prop("chainChoice_peers", "checked"), true)
            expect("...the Electrum list behind Change", shown("electrumPane") || !shown("feeServersButton"), false)
            find(view.item, "addSourceAddress", 0).text = "192.168.1.30:50001"
            find(view.item, "addSourceButton", 0).clicked()
            expect("a server added in Advanced opens the Electrum list, where its row is",
                   [fake.last("addSource"), shown("electrumPane")], [["addSource", "192.168.1.30:50001", "electrum", ""], true])
            find(view.item, "feeServersButton", 0).expanded = false
            expect("...and an offer to see payments before they confirm", prop("pendingLine", "text"),
                   "Bitcoin peers don't share unconfirmed payments. Turn this on to see incoming payments before they confirm; the server you pick learns your addresses.")
            expect("...at a server picked from the list", prop("pendingSwitch", "enabled") && shown("pendingServerChoice"), true)
            before = fake.count("setSource")
            find(view.item, "pendingSwitch", 0).clicked()
            expect("...which turns History on there", sets(before), [["setSource", "electrum.example", JSON.stringify({ use: true, history: true })]])
            v.chainPicked = ""
            scene.keptSources = fake.sourcesJson
            fake.sourcesJson = JSON.stringify({ network: "signet", configured: true, walletOpen: false, exposes: [], withoutTor: [], sources: [
                { id: "kyoto", kind: "kyoto", url: "p2p://peer-list", operator: "peers", label: "Bitcoin peers", use: true, route: "tor" },
                { id: "emzy", kind: "electrum", url: "ssl://electrum.emzy.de:50002", operator: "emzy.de", label: "emzy.de", use: false, history: true, route: "tor" },
                { id: "local", kind: "local", url: "logos://bitcoind_module", operator: "you", label: "Your node", use: false, route: "direct" }] })
        },
        function (v) {
            expect("signet under Bitcoin peers: fees are the relay floor", prop("feeSourceLine", "text"), "The lowest rate peers relay: signet has no useful fee estimates.")
            expect("...no payments before they confirm until a server is picked", prop("pendingSwitch", "checked"), false)
            var sets = function (from) { return fake.calls.filter(function (c) { return c[0] === "setSource" }).slice(from) }
            var before = fake.count("setSource")
            expect("no Use your node button nor In use badge: the radio is the state",
                   [find(view.item, "useOwnNodeButton", 0), find(view.item, "ownNodeInUse", 0), find(view.item, "ownNodeFinish", 0)], [null, null, null])
            find(view.item, "chainChoice_node", 0).clicked()
            expect("Your own node, in Logos: on, the public switches left as they are", sets(before), [["setSource", "local", JSON.stringify({ use: true })]])
            expect("...its pane under it, In Logos", [shown("ownNodePane"), prop("nodePlace_local", "checked"), shown("localNodePane")], [true, true, true])
            expect("...one note of benefits and costs", prop("ownNodeNote", "text").indexOf("<b>Benefits:</b>") === 0
                   && prop("ownNodeNote", "text").indexOf("<b>Costs:</b>") > 0, true)
            expect("...no Tor in Logos", [shown("torUseSettings"), shown("whichTor_builtIn"), shown("node_whichTor_builtIn"), shown("torBadge"),
                                          shown("manageTorLink")], [false, false, false, false, false])
            expect("...the node app for its own connections", shown("openNodeAppButton") && shown("localNodePeersLine"), true)
            expect("...no Sending payments from an older node module", shown("localSendsPane"), false)
            expect("...whose note says your node sends", prop("ownNodeNote", "text").indexOf("<b>Sending:</b> payments go through your node") > 0, true)
            var noSends = fake.sourcesJson
            var withSends = JSON.parse(noSends)
            withSends.sources[2].use = true
            withSends.sends = { localSends: "servers", localSendsChosen: false, localSendsRecommended: "servers",
                                sendServers: [{ id: "emzy", operator: "emzy.de", route: "tor" }, { id: "emzy-onion", operator: "emzy.de", route: "onion" }] }
            fake.sourcesJson = JSON.stringify(withSends)
            expect("Sending payments under your node: public servers, recommended",
                   [shown("localSendsPane"), prop("localSends_servers", "checked"), shown("localSendsRecommended_servers"), shown("localSendsRecommended_node")],
                   [true, true, true, false])
            expect("...through each operator once, over the Tor picked here", [prop("localSendsServersLine", "text"), shown("sends_whichTor_builtIn")],
                   ["Through emzy.de.", true])
            expect("...the note names both routes", prop("ownNodeNote", "text").indexOf("as Sending payments says") > 0, true)
            find(view.item, "localSends_node", 0).clicked()
            expect("...your node, picked", fake.last("setLocalSends"), ["setLocalSends", "node"])
            expect("...then no servers line and no Which Tor", [prop("localSends_node", "checked"), shown("localSendsServersLine"), shown("sends_whichTor_builtIn")],
                   [true, false, false])
            expect("...its note: peers see this computer", prop("localSendsNote_node", "text").indexOf("from this computer's IP address") > 0, true)
            withSends.sends = { localSends: "node", localSendsChosen: true, localSendsRecommended: "node", sendServers: [] }
            fake.sourcesJson = JSON.stringify(withSends)
            expect("The node app sends privately: no servers to send through, your node recommended",
                   [prop("localSendsServersLine", "text"), shown("localSendsRecommended_node"), shown("localSendsRecommended_servers"), shown("sends_whichTor_builtIn")],
                   ["No Electrum server is on for signet, so your node sends them itself.", true, false, false])
            expect("...its note: privately, over Tor", prop("localSendsNote_node", "text").indexOf("sends it privately, over Tor") > 0, true)
            fake.sendsReply = "Close your open accounts to change this."
            find(view.item, "localSends_servers", 0).clicked()
            expect("...a refusal shows under the choice", [shown("localSendsNotice"), prop("localSendsNotice", "message")],
                   [true, "Close your open accounts to change this."])
            fake.sendsReply = ""
            find(view.item, "localSends_servers", 0).clicked()
            expect("...and picking again clears it", [shown("localSendsNotice"), fake.last("setLocalSends")], [false, ["setLocalSends", "servers"]])
            fake.sourcesJson = noSends
            expect("...and nothing of public sources", [shown("publicPane"), shown("feesHeading"), shown("pendingChoice"), shown("advancedSourcesButton")],
                   [false, false, false, false])
            // The engine turns the node on: the public switches stay as they were, Kyoto on.
            var on = JSON.parse(fake.sourcesJson)
            on.sources[2].use = true
            fake.sourcesJson = JSON.stringify(on)
            v.chainPicked = ""
            expect("...the node's state from its health", prop("localNodeState", "text"), "not checked yet")
            before = fake.count("setSource")
            find(view.item, "chainChoice_public", 0).clicked()
            expect("Public sources: your node off, the switches before it back", sets(before), [["setSource", "local", JSON.stringify({ use: false })]])
            expect("...Bitcoin peers as they were", [prop("chainChoice_public", "checked"), prop("chainChoice_peers", "checked")], [true, true])
            v.chainPicked = ""
            on.sources[0].use = false
            fake.sourcesJson = JSON.stringify(on)
            before = fake.count("setSource")
            find(view.item, "chainChoice_public", 0).clicked()
            expect("...and Bitcoin peers when nothing public was on", sets(before),
                   [["setSource", "kyoto", JSON.stringify({ use: true })], ["setSource", "local", JSON.stringify({ use: false })]])
            v.chainPicked = ""
            on.sources[0].use = true
            on.sources[2].use = false
            fake.sourcesJson = JSON.stringify(on)
            before = fake.count("setSource")
            find(view.item, "chainChoice_electrum", 0).clicked()
            expect("Electrum servers: Kyoto off, the servers left as they are", sets(before), [["setSource", "kyoto", JSON.stringify({ use: false })]])
            expect("...the list open", shown("electrumPane") && !shown("feeServersButton"), true)
            v.chainPicked = ""
            fake.sourcesJson = scene.keptSources
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
            expect("named node", prop("syncLine", "text"), "Synchronized · block 935,500 · from your node")
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
            expandSources(["mine", "plain", "newsrv"])
            expect("Electrum servers on your network are Electrum servers", prop("electrumSources", "entries").length, 3)
            expect("history from a server: its label", v.historyName("mine"), "My server")
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
            fake.peerListJson = JSON.stringify({ network: "regtest", ownPeers: [], usable: peers, route: "onion", kyotoTor: true,
                counts: { list: 11, learned: 3, seed: 8, usable: 14, okLast30d: 6 },
                list: { format: 2, network: "regtest", version: "1", peers: peers,
                        note: "PROVISIONAL: from 1 run, not the plan's 6 of 7 days." } })
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            expandAdvanced()
            expandSources(["kyoto"])
            expect("Kyoto's Tor switch says what off means", [shownAny("torSwitch_kyoto"), shownAny("kyotoTorNote"), prop("kyotoTorNote", "text")],
                   [true, true, "With Tor off, Kyoto takes everything directly, as with Nothing: the blocks with your payments and your sends too."])
            expect("the peer book", prop("curatedLine", "text"), "14 known peers: 11 from the curated list, 3 learned · 6 worked in the last 30 days")
            expect("...the curated list's standing", prop("curatedListNote", "text"), "The curated list is provisional.")
            expect("...and how it grows", prop("peerBookLine", "text"), "The wallet learns working peers from the peers it already uses; "
                   + "if too few work, it asks a few of Bitcoin Core's built-in onion nodes for more.")
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
            expandAdvanced()
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
            fake.alertsJson = JSON.stringify([{ source: "electrum-0", kind: "unchecked_anchor", detail: "1 transaction reported below block 150", at: 1791590400 }])
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
            expect("reported, not checked", prop("historyState_" + "aa".repeat(32), "text"), "Reported by electrum-0, not checked")
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
            st.historyServer = "electrum-0"
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
                   + "watching 40 unused addresses past the last one used. That downloads more. Your history server, electrum-0, will be asked about more addresses.")
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
            expect("the history line says where payments are found", prop("historyLine", "text"), "Payments found on this device, through block filters")
            v.selectTab(0)
            fake.statusJson = JSON.stringify({ state: "syncing", network: "mainnet", authority: { kind: "kyoto", peers: 0 } })
            fake.sourcesJson = JSON.stringify({ network: "mainnet", proxy: "socks5h://127.0.0.1:9050", sources: [
                { id: "kyoto", kind: "kyoto", use: true, route: "tor" },
                { id: "fee", kind: "electrum", use: true, route: "onion" },
                { id: "backup", kind: "electrum", use: false, route: "tor", url: "ssl://example.com:50002" }] })
            fake.healthJson = JSON.stringify({ sources: [
                { id: "kyoto", state: "not_probed", peers: 1024 },
                { id: "fee", state: "unreachable", error: "connect to server: through the proxy 127.0.0.1:9050: Proxy server unreachable" }] })
        },
        function (v) {
            expect("proxy failure replaces endless connecting", prop("syncChip", "text"), "Tor unavailable")
            expect("proxy failure on Home", shown("torConnectionNotice"), true)
            expect("setup guidance names proxy", prop("torConnectionNotice", "message").indexOf("socks5h://127.0.0.1:9050") >= 0, true)
            expect("peer list is not a connection count", v.healthLine({ id: "kyoto", kind: "kyoto" }), "1024 known peers · not a connection count")
            find(view.item, "retryTorButton", 0).clicked()
            expect("retry probes the failing enabled source", fake.last("probeSource"), ["probeSource", "fee"])
            find(view.item, "torSourcesButton", 0).clicked()
        },
        function (v) {
            expect("sources shows Tor help", shown("torSettingsNotice"), true)
            expect("enabled source remains identifiable while locked", prop("sourceEnabled_kyoto", "text"), "Enabled")
            expect("disabled source remains identifiable while locked", prop("sourceEnabled_backup", "text"), "Disabled")
            var info = find(view.item, "operatorsInfo", 0)
            info.open()
            expect("sources help opens", info.opened, true)
            expect("sources help title", info.title, "How public sources work")
            expect("sources help has scrollable content", info.dialogContentItem !== null, true)
            info.close()
            // A peer already answering overrides an older failed server health probe.
            fake.statusJson = JSON.stringify({ state: "syncing", network: "mainnet", authority: { kind: "kyoto", peers: 1 } })
        },
        function (v) {
            expect("working peers are not labelled Tor blocked", v.syncState(v.status), "headers")
            expect("local node is not labelled Tor blocked", v.syncState({ state: "syncing", authority: { kind: "local_node", peers: 0 } }), "connecting")
            fake.statusJson = JSON.stringify({ state: "syncing", network: "mainnet", authority: { kind: "kyoto", peers: 0 } })
            // A remote failure after SOCKS connected does not prove the proxy is unreachable.
            fake.healthJson = JSON.stringify({ sources: [{ id: "fee", state: "unreachable", error: "through the proxy 127.0.0.1:9050: TTL expired" }] })
        },
        function (v) {
            expect("remote failure is not proxy failure", v.torFailureSource, null)
            expect("remote failure keeps connecting", v.syncState(v.status), "connecting")
            fake.healthJson = JSON.stringify({ sources: [{ id: "backup", state: "unreachable", error: "Proxy server unreachable" }] })
        },
        function (v) {
            expect("disabled sources cannot raise proxy warning", v.torFailureSource, null)
            fake.healthJson = JSON.stringify({ sources: [{ id: "fee", state: "ok", rttMs: 40 }] })
        },
        function (v) {
            expect("healthy probe clears warning", shown("torConnectionNotice"), false)
            expect("healthy probe clears settings warning", shown("torSettingsNotice"), false)
            expect("no Use without Tor control: Use Tor for decides", find(view.item, "connectDirectButton", 0), null)
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "mainnet" })
        },
        function (v) {
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            var before = fake.count("setSource")
            find(view.item, "chainChoice_node", 0).clicked()
            expect("your own node with none on this network: nothing to switch, the address form", [fake.count("setSource") - before,
                   prop("nodePlace_rpc", "checked"), shown("rpcAddress")], [0, true, true])
            find(view.item, "rpcAddress", 0).text = "http://192.168.1.20:8332"
            expect("on your network: reached directly, no Tor switch, no Which Tor", [prop("rpcAddressLine", "text"), shown("rpcAddTorSwitch"),
                   shown("node_whichTor_builtIn")], ["Reached directly. Tor can't reach your network.", false, false])
            find(view.item, "rpcUser", 0).text = "rpc-user"
            find(view.item, "rpcPass", 0).text = "rpc-test-password"
            find(view.item, "rpcName", 0).text = "My Core"
            find(view.item, "addRpcButton", 0).clicked()
            expect("RPC configuration reaches backend, without Tor on your network", fake.last("addRpcSource"),
                   ["addRpcSource", "http://192.168.1.20:8332", "rpc-user", "rpc-test-password", "My Core", false])
            expect("RPC password cleared after submission", prop("rpcPass", "text"), "")
            find(view.item, "rpcAddress", 0).text = "https://node.example:8332"
            expect("on the internet: Reach it through Tor, on, with Which Tor", [shown("rpcAddressLine"), shown("rpcAddTorSwitch"),
                   prop("rpcAddTorSwitch", "checked"), shown("node_whichTor_builtIn"), shown("node_whichTor_own")], [false, true, true, true, true])
            find(view.item, "addRpcButton", 0).clicked()
            expect("...added through Tor", fake.last("addRpcSource")[5], true)
            find(view.item, "rpcAddTorSwitch", 0).clicked()
            expect("...off: no Which Tor", [prop("rpcAddTorSwitch", "checked"), shown("node_whichTor_builtIn")], [false, false])
            find(view.item, "rpcAddress", 0).text = "https://node.example:8332"
            find(view.item, "addRpcButton", 0).clicked()
            expect("...added direct", fake.last("addRpcSource")[5], false)
            find(view.item, "rpcAddTorSwitch", 0).clicked()
            find(view.item, "rpcAddress", 0).text = "http://" + "a".repeat(56) + ".onion:8332"
            expect("an onion address: always through Tor, with Which Tor", [prop("rpcAddressLine", "text"), shown("rpcAddTorSwitch"),
                   shown("node_whichTor_builtIn")], ["Always reached through Tor.", false, true])
            find(view.item, "rpcAddress", 0).text = ""
            expect("host classes", ["[fd00::2]:8332", "10.0.0.5", "100.64.1.1", "nas.lan", "rpc:pw@172.20.0.1:8332", "8.8.8.8", "[2001:db8::1]"]
                   .map(v.addressPlace), ["lan", "lan", "lan", "lan", "lan", "internet", "internet"])
            fake.sourcesJson = JSON.stringify({sources:[
                {id:"rpc-public",kind:"rpc",url:"https://rpc.example",use:false,tor:false,route:"direct"},
                {id:"rpc-home",kind:"rpc",url:"http://192.168.1.20:8332",lan:true,use:true,tor:false,route:"direct"}]})
        },
        function (v) {
            expect("your node at an address: every endpoint in one place", prop("rpcSources", "entries").map(function (s) { return s.id }), ["rpc-public", "rpc-home"])
            expect("...with no node in Logos listed, the place is an address", prop("nodePlace_rpc", "checked"), true)
            expect("no Use only this any more", find(view.item, "useRpc_rpc-public", 0), null)
            expandSources(["rpc-public"])
            expect("RPC never offers address-history queries", shown("historySwitch_rpc-public"), false)
            var before = fake.count("setSource")
            find(view.item, "useSwitch_rpc-public", 0).clicked()
            expect("one node at a time: the other goes off first", fake.calls.filter(function (c) { return c[0] === "setSource" }).slice(before),
                   [["setSource", "rpc-home", JSON.stringify({ use: false })], ["setSource", "rpc-public", JSON.stringify({ use: true })]])
            expect("the address in use decides Tor: on your network, directly", [prop("rpcRouteLine", "text"), shown("rpcTorSwitch")],
                   ["Reached directly. Tor can't reach your network.", false])
            fake.sourcesJson = JSON.stringify({sources:[
                {id:"rpc-public",kind:"rpc",url:"https://rpc.example",use:true,tor:false,route:"direct"}]})
            expect("one address: no Use switch, the radio is the state", shown("useSwitch_rpc-public"), false)
            expect("an internet address: Reach it through Tor, off, and no Which Tor", [shown("rpcTorSwitch"), prop("rpcTorSwitch", "checked"),
                   shown("node_whichTor_builtIn")], [true, false, false])
            expect("...its card has no second Tor switch", shown("torSwitch_rpc-public"), false)
            find(view.item, "rpcTorSwitch", 0).clicked()
            expect("...turning it on asks for Tor", fake.last("setSource"), ["setSource", "rpc-public", JSON.stringify({ tor: true })])
            fake.sourcesJson = JSON.stringify({sources:[
                {id:"rpc-public",kind:"rpc",url:"https://rpc.example",use:true,tor:true,route:"tor"}]})
            expect("...then Which Tor under it", shown("node_whichTor_builtIn"), true)
            find(view.item, "nodePlace_local", 0).clicked()
            expect("In Logos, picked", prop("nodePlace_local", "checked"), true)
            expect("...hides the address form", shown("rpcAddress"), false)
            v.nodePlacePicked = ""
            v.chainPicked = ""
            expect("RPC names your node as the chain's source", v.authorityName({authority:{kind:"rpc_node"}}), "your node")
            // The Tor that comes with Logos, joining: the badge, Home and the sync chip follow it.
            scene.keptSources = fake.sourcesJson
            scene.keptHealth = fake.healthJson
            fake.sourcesJson = JSON.stringify({ network: "mainnet", proxy: "tor", sources: [
                { id: "kyoto", kind: "kyoto", use: true, route: "tor" },
                { id: "fee", kind: "electrum", use: true, route: "onion" }] })
            fake.healthJson = JSON.stringify({ overall: "offline", sources: [],
                tor: { state: "connecting", progress: 40, detail: "", socks: "socks5h://127.0.0.1:9250", answered: true } })
        },
        function (v) {
            var peerless = { state: "syncing", authority: { kind: "kyoto", peers: 0 } }
            expect("built-in Tor badge", prop("torBadge", "text"), "Connecting to Tor… 40%")
            expect("...its progress", shownAny("torProgress"), true)
            expect("...joining is no trouble", shownAny("torTroubleNotice") || v.torUnusable, false)
            expect("a peerless Kyoto waits for Tor", v.syncChip(peerless), "Tor 40%")
            expect("...and says so", v.syncStateLabel(peerless).indexOf("Connecting to Tor… 40%"), 0)
            expect("Manage Tor for the built-in one", shownAny("manageTorLink"), true)
            expect("Which Tor: the built-in one picked, your own offered, closed", [prop("whichTor_builtIn", "checked"), shown("whichTor_own"),
                   prop("whichTor_own", "checked"), shown("ownTorPane")], [true, true, false, false])
            find(view.item, "manageTorLink", 0).activated("")
            expect("Manage Tor raises tor.manage", logos.requests[logos.requests.length - 1].intent, "tor.manage")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the Tor app is missing", prop("torNote", "text"), "The Tor app is not installed.")
            fake.healthJson = JSON.stringify({ overall: "offline", sources: [],
                tor: { state: "ready", progress: 100, detail: "", socks: null, answered: true } })
        },
        function (v) {
            expect("Tor closed to apps is named", prop("torBadge", "text"), "Tor is off for apps")
            expect("...with what to do", shownAny("torTroubleNotice")
                   && prop("torTroubleNotice", "message").indexOf("Turn it on in the Tor app") >= 0, true)
            expect("...and Kyoto cannot connect", v.syncChip({ state: "syncing", authority: { kind: "kyoto", peers: 0 } }), "Tor unavailable")
            expect("...not the own-proxy notice", shownAny("torSettingsNotice"), false)
            fake.healthJson = JSON.stringify({ overall: "offline", sources: [],
                tor: { state: "failed", progress: 0, detail: "object_unavailable", socks: null, answered: false } })
        },
        function (v) {
            expect("tor_module not answering", prop("torBadge", "text"), "Tor is not available")
            expect("...without its raw error", prop("torTroubleNotice", "message").indexOf("object_unavailable"), -1)
            fake.healthJson = JSON.stringify({ overall: "ok", sources: [],
                tor: { state: "ready", progress: 100, detail: "", socks: "socks5h://127.0.0.1:9250", answered: true } })
        },
        function (v) {
            expect("connected", prop("torBadge", "text"), "Connected to Tor")
            expect("...no trouble", shownAny("torTroubleNotice"), false)
            find(view.item, "whichTor_own", 0).clicked()
        },
        function (v) {
            expect("own Tor opens its field first", shownAny("ownTorPane"), true)
            expect("...saving nothing yet", fake.count("setProxy"), 0)
            find(view.item, "proxyField", 0).text = "socks5h://127.0.0.1:9150"
            find(view.item, "saveProxyButton", 0).clicked()
            expect("Use it saves the user's Tor", fake.last("setProxy"), ["setProxy", "socks5h://127.0.0.1:9150"])
            fake.sourcesJson = JSON.stringify({ network: "mainnet", proxy: "socks5h://127.0.0.1:9150", sources: [
                { id: "kyoto", kind: "kyoto", use: true, route: "tor" }] })
            fake.healthJson = JSON.stringify({ overall: "ok", sources: [], tor: null })
        },
        function (v) {
            expect("own Tor: no built-in badge", shownAny("torBadge"), false)
            expect("...nor Manage Tor", shownAny("manageTorLink"), false)
            expect("...your own picked, with its address", [prop("whichTor_own", "checked"), prop("proxyField", "text")], [true, "socks5h://127.0.0.1:9150"])
            find(view.item, "whichTor_builtIn", 0).clicked()
            expect("switching back uses the built-in Tor", fake.last("setProxy"), ["setProxy", "tor"])
            fake.sourcesJson = scene.keptSources
            fake.healthJson = scene.keptHealth
        },
        function (v) {
            v.closeSheets()
            fake.networksJson = JSON.stringify({networks:["mainnet","signet"],active:"mainnet"})
            fake.statusJson = JSON.stringify({state:"ready",network:"mainnet",group:"g_main",family:"bitcoin",synced:true})
            fake.accountsJson = JSON.stringify([
                {id:"g_main",family:"bitcoin",chain:"main",label:"Savings",signer:"keystore_module",available:true},
                {id:"g_other",family:"bitcoin_taproot",chain:"main",label:"Other wallet",signer:"keystore_module",available:true}])
        },
        function (v) {
            expect("open account identity", v.selectedAccount.id, "g_main")
            expect("picker follows current wallet", prop("accountPicker","currentIndex"), 0)
            // One wallet at a time: the picker is locked on the open one until it closes.
            expect("an open wallet locks the picker", prop("accountPicker","enabled"), false)
            expect("...and Open", prop("openWalletButton","enabled"), false)
            expect("...and says why", shown("accountLockedNote") && prop("accountLockedNote","text"), "Close this wallet to open another.")
            find(view.item,"accountPicker",0).currentIndex = 1
            find(view.item,"accountPicker",0).activated(1)
            expect("picking another changes nothing", v.selectedAccount.id, "g_main")
            expect("...and the picker shows the open one", prop("accountPicker","currentIndex"), 0)
            v.selectAccount(v.accountsOnNetwork[1])
            expect("nor does a driver's pick", v.selectedAccount.id, "g_main")
            v.openSelectedAccount()
            expect("...nor an open", fake.last("selectAccount"), ["selectAccount", "g_test", ""])
            fake.accountsJson = JSON.stringify(JSON.parse(fake.accountsJson))
            fake.statusJson = JSON.stringify({state:"syncing",network:"mainnet",group:"g_main",family:"bitcoin"})
            expect("a refresh keeps the open one", v.selectedAccount.id, "g_main")
            fake.pendingJobKind = "close"
            fake.busy = true
            fake.statusJson = JSON.stringify({state:"closing",network:"mainnet",group:"g_main",family:"bitcoin"})
        },
        function (v) {
            expect("closing keeps the picker locked", prop("accountPicker","enabled"), false)
            expect("...on the closing account", v.selectedAccount.id, "g_main")
            expect("...with Open off", prop("openWalletButton","enabled"), false)
            fake.pendingJobKind = ""
            fake.busy = false
            fake.statusJson = JSON.stringify({state:"no_wallet",activeNetwork:"mainnet"})
        },
        function (v) {
            expect("closed, the picker unlocks", prop("accountPicker","enabled"), true)
            expect("...with the closed account still selected", v.selectedAccount.id, "g_main")
            expect("...and Open on", prop("openWalletButton","enabled"), true)
            expect("...and no hint", shown("accountLockedNote"), false)
            find(view.item,"accountPicker",0).currentIndex = 1
            find(view.item,"accountPicker",0).activated(1)
            expect("another can be picked now", v.selectedAccount.id, "g_other")
            fake.walletsJson = JSON.stringify([{ group: "g_other", family: "bitcoin_taproot", network: "mainnet" }])
            find(view.item,"openWalletButton",0).clicked()
            expect("...and opened", fake.last("selectAccount"), ["selectAccount","g_other",""])
            fake.pendingJobKind = "open"
            fake.busy = true
            fake.statusJson = JSON.stringify({state:"awaiting_open",network:"mainnet",openHandle:"sma_t2"})
        },
        function (v) {
            expect("opening locks the picker", prop("accountPicker","enabled"), false)
            expect("...on the account asked for", v.selectedAccount.id, "g_other")
            fake.pendingJobKind = ""
            fake.busy = false
            fake.statusJson = JSON.stringify({state:"ready",network:"mainnet",group:"g_other",family:"bitcoin_taproot",synced:true})
        },
        function (v) {
            expect("new wallet identity follows status", v.selectedAccount.id,"g_other")
            fake.accountsError = "Accounts unavailable"
        },
        function (v) {
            expect("roster failure preserves identity", v.selectedAccount.id,"g_other")
            expect("roster failure disables selector",prop("accountPicker","enabled"),false)
            fake.accountsError = ""
            fake.accountsJson = "[]"
        },
        function (v) {
            expect("removed account cannot become another account",prop("accountPicker","currentIndex"),-1)
            expect("empty roster disables selector",prop("accountPicker","enabled"),false)
            fake.statusJson = JSON.stringify({state:"no_wallet",activeNetwork:"mainnet"})
        },
        function (v) {
            expect("empty roster disables Open",prop("openWalletButton","enabled"),false)
            expect("management available with no accounts",shown("manageAccountsButton"),true)
            // An unplugged device's wallet is open: viewing works, sending says to connect it.
            fake.networksJson = JSON.stringify({networks:["mainnet","regtest"],active:"regtest"})
            fake.accountsJson = JSON.stringify([scene.cardRow(false)])
            fake.statusJson = JSON.stringify({state:"ready",network:"regtest",activeNetwork:"regtest",group:"keycard-cdcdcdcd-84-1-0",family:"bitcoin",synced:true})
        },
        function (v) {
            expect("the Keycard's wallet is open", v.openedAccount ? v.openedAccount.id : null, "keycard-cdcdcdcd-84-1-0")
            expect("Send says what signing needs", prop("sendDeviceNote", "text"), "Keycard not connected. Insert Black Card in a reader "
                   + "or connect a Keycard Shell to sign. You can view this wallet; sending needs it.")
            var gone = { state: "failed", errorCode: "signer_unavailable", error: "signer_manager_module: no answer" }
            expect("a failure while it is unplugged says so", v.sendHeadline(gone), "Keycard could not sign: it is not connected")
            expect("...that nothing went out", v.sendDetail(gone),
                   "Nothing went out. Insert Black Card in a reader or connect a Keycard Shell to sign, then try again.")
            expect("...and it can be asked again", v.canRetry(gone), true)
            var refused = { state: "failed", errorCode: "failed", error: "keycard_module: no card in the reader" }
            expect("the device's own refusal reads the same", v.sendHeadline(refused), "Keycard could not sign: it is not connected")
            expect("...and can be asked again", v.canRetry(refused), true)
            fake.accountsJson = JSON.stringify([scene.cardRow(true)])
        },
        function (v) {
            expect("plugged in, Send says nothing more", prop("sendDeviceNote", "text"), "")
            expect("...nor the row", prop("deviceAbsentNote", "text"), "")
            expect("...nor a reason", prop("deviceReasonLine", "text"), "")
            expect("...and a failure is the signer's again", v.sendHeadline({ state: "failed", errorCode: "signer_unavailable", error: "x" }),
                   "The signer could not be reached")
            // One account the keystore and a Keycard both hold, as the roster lists it: one row.
            fake.statusJson = JSON.stringify({state:"no_wallet",activeNetwork:"regtest"})
            fake.accountsJson = JSON.stringify([
                {id:"g_seg",family:"bitcoin",chain:"test",label:"Savings",signer:"keystore_module",available:true},
                scene.cardRow(true)])
            fake.walletsJson = JSON.stringify([{group:"keycard-cdcdcdcd-84-1-0",family:"bitcoin",network:"regtest"}])
            fake.accountRosterJson = JSON.stringify([{key:"btc_00112233445566778899aabbccddeeff",family:"bitcoin",chain:"test",
                path:"m/84'/1'/0'",label:"Savings",wallet:{fingerprint:"cdcdcdcd",name:"Black Card"},
                holders:[{signer:"keystore_module",accountId:"g_seg",kind:"keystore",model:"",transport:"keystore",presence:"local",available:true},
                         {signer:"keycard_module",accountId:"keycard-cdcdcdcd-84-1-0",kind:"keycard",model:"",transport:"reader",presence:"connected",available:true}]}])
        },
        function (v) {
            expect("one row for an account two signers hold", v.accountEntries.length, 1)
            find(view.item, "accountPicker", 0).activated(0)
            expect("...naming both, the keystore first", prop("accountPickerSelectedChip_0", "text") + " / "
                   + prop("accountPickerSelectedChip_1", "text"), "● This device (Keystore) / ● Keycard · reader")
            expect("it opens where it already has a wallet", v.selectedAccount ? v.selectedAccount.id : null, "keycard-cdcdcdcd-84-1-0")
            expect("...and the picker shows it", prop("accountPicker", "currentIndex"), 0)
            expect("...by its name, type and number", prop("accountPickerSelectedName", "text") + " / " + prop("accountPickerSelectedType", "text")
                   + " / " + prop("accountPickerSelectedAccount", "text"), "Savings / Native SegWit / account 0")
            expect("...with its wallet", prop("accountPickerSelectedWallet", "text"), "Wallet “Black Card” · cdcdcdcd")
            fake.walletsJson = "[]"
        },
        function (v) {
            find(view.item, "accountPicker", 0).activated(0)
            expect("with no wallet yet, it opens under the keystore's", v.selectedAccount ? v.selectedAccount.id : null, "g_seg")
            // Opened under the Keycard, whose own label is not the roster's name for the account.
            fake.statusJson = JSON.stringify({state:"ready",network:"regtest",activeNetwork:"regtest",group:"keycard-cdcdcdcd-84-1-0",
                                              family:"bitcoin",label:"Card account",synced:true})
        },
        function (v) {
            expect("the open wallet goes by the roster's name", prop("statusLine", "text"), "Open: Savings · regtest")
            expect("...as the picker's placeholder", prop("accountPicker", "placeholder"), "Savings")
            expect("...and in Settings", prop("walletName", "text"), "Savings")
            fake.accountRosterJson = "[]"
        },
        function (v) {
            expect("with no roster, it goes by the wallet's own label", prop("statusLine", "text"), "Open: Card account · regtest")
            // Hand-test fix 7: the Keycard is out, but the keystore holds the same account and signs.
            fake.accountsJson = JSON.stringify([scene.cardRow(false)])
            fake.accountRosterJson = JSON.stringify([{key:"btc_00112233445566778899aabbccddeeff",family:"bitcoin",chain:"test",
                path:"m/84'/1'/0'",label:"Savings",wallet:{fingerprint:"cdcdcdcd",name:"Black Card"},
                holders:[{signer:"keystore_module",accountId:"g_seg",kind:"keystore",model:"",transport:"keystore",presence:"local",available:true},
                         {signer:"keycard_module",accountId:"keycard-cdcdcdcd-84-1-0",kind:"keycard",model:"",transport:"reader",presence:"absent",available:false}]}])
        },
        function (v) {
            expect("another holder signs: sending needs no device", prop("deviceAbsentNote", "text"), "")
            expect("...and Send says nothing of it", prop("sendDeviceNote", "text"), "")
            fake.accountRosterJson = "[]"
            fake.statusJson = JSON.stringify({state:"no_wallet",activeNetwork:"regtest"})
            // A wallet still locked in the Signer app: its accounts aren't offered, and the banner says why.
            fake.signerWalletsJson = JSON.stringify([{seed:"s_1",name:"Main phrase",locked:true},{seed:"s_2",name:"Card",locked:false}])
        },
        function (v) {
            expect("the locked banner", shown("accountsLockedBanner"), true)
            expect("...names the wallet", prop("accountsLockedBanner", "title"), "Wallet “Main phrase” is locked")
            find(view.item, "accountsUnlockButton", 0).clicked()
            var asked = logos.requests[logos.requests.length - 1]
            expect("Unlock asks the Signer app for it", asked.intent + " " + JSON.stringify(asked.params.seeds), "wallets.unlock [\"s_1\"]")
            fake.signerWalletsJson = JSON.stringify([{seed:"s_1",name:"Main phrase",locked:false}])
        },
        function (v) {
            expect("gone once it unlocks", shown("accountsLockedBanner"), false)
            // "Use Tor for", saved per network in Node. A fresh node store: identifying, not chosen yet.
            fake.signerWalletsJson = "[]"
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "tor", torUse: "identifying", torUseChosen: false, sources: [
                { id: "kyoto", kind: "kyoto", use: true, route: "tor" }] })
            fake.healthJson = JSON.stringify({ overall: "ok", sources: [], torUse: "identifying", torUseChosen: false,
                tor: { state: "ready", progress: 100, detail: "", socks: "socks5h://127.0.0.1:9250", answered: true } })
        },
        function (v) {
            var modes = ["identifying", "all", "none"]
            expect("not saved yet: the account start shows, with a notice", [shown("openPage"), shown("accountSelectorRow"), shown("nodeSetupNotice")],
                   [true, true, true])
            expect("...naming the network", prop("nodeSetupNotice", "title"), "Set up Node for regtest")
            expect("...no first-run screen", findAll(view.item, "torUsePage", 0, []).length, 0)
            expect("...and Open waits for it", v.canOpenSelectedAccount, false)
            find(view.item, "nodeSetupButton", 0).clicked()
        },
        function (v) {
            var vis = function (n) { return findAll(view.item, n, 0, []).filter(function (o) { return o.visible })[0] || null }
            var modes = ["identifying", "all", "none"]
            expect("Open Node opens the sheet", prop("networkSheet", "visible"), true)
            expect("...saying it isn't saved", vis("nodeSetupSheetNotice") ? vis("nodeSetupSheetNotice").title : "", "Not saved for regtest yet")
            expect("...for this network", vis("chainNetworkLine") ? vis("chainNetworkLine").text : "", "For regtest. Each network has its own setting.")
            expect("the intro", vis("torUseIntro") ? vis("torUseIntro").text : "", v.torUseIntro)
            expect("three options", modes.map(function (m) { return vis("torUse_" + m) ? vis("torUse_" + m).text : "" }),
                   ["Only what identifies you", "Everything", "Nothing"])
            expect("each has an i beside it, nothing spelled out under it", modes.map(function (m) {
                return vis("torUse_info_" + m) !== null && ["happens_", "pros_", "cons_"].every(function (k) {
                    return find(view.item, "torUse_" + k + m, 0) !== null && vis("torUse_" + k + m) === null }) }), [true, true, true])
            var noneInfo = vis("torUse_info_none")
            noneInfo.clicked()
            expect("the i opens what happens, pros and cons", [noneInfo.opened, noneInfo.title, ["happens_", "pros_", "cons_"].every(function (k) {
                return vis("torUse_" + k + "none") !== null })], [true, "Nothing", true])
            expect("...in the plan's words", vis("torUse_happens_none").text, "<b>What happens:</b> Every connection is direct; Tor isn't used.")
            noneInfo.close()
            expect("the source choices' notes are behind an i too", ["ownNodeInfo", "chainInfo_peers", "chainInfo_electrum"].map(function (n) {
                return vis(n) !== null }), [true, true, true])
            expect("...Bitcoin peers' note", prop("chainNote_peers", "text").indexOf("The default. Block filters from Bitcoin peers") === 0
                   && !shown("chainNote_peers"), true)
            expect("fresh: identifying checked", modes.map(function (m) { return vis("torUse_" + m).checked }), [true, false, false])
            expect("...and Recommended", vis("torUse_recommended_identifying") !== null, true)
            expect("the button saves", prop("networkSheetDone", "text"), "Save")
            find(view.item, "networkSheetDone", 0).clicked()
            expect("Save sends the checked mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
        },
        function (v) {
            expect("saved: the sheet closes", prop("networkSheet", "visible"), false)
            expect("...the notice goes", shown("nodeSetupNotice"), false)
            expect("...and the node keeps it chosen", v.torUseUnchosen, false)
            // An existing install: today's all-Tor routing, not chosen yet. A new session, so nothing answered.
            v.torUseAnswered = false
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "tor", torUse: "all", torUseChosen: false, sources: [
                { id: "kyoto", kind: "kyoto", use: true, route: "tor" }] })
        },
        function (v) {
            expect("existing: the notice once more", shown("nodeSetupNotice"), true)
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            var vis = function (n) { return findAll(view.item, n, 0, []).filter(function (o) { return o.visible })[0] || null }
            expect("...its routing checked", ["identifying", "all", "none"].map(function (m) { return vis("torUse_" + m).checked }),
                   [false, true, false])
            fake.torUseReply = "invalid parameters: torUse must be all, identifying or none"
            find(view.item, "networkSheetDone", 0).clicked()
            expect("Save unchanged keeps all-Tor", fake.last("setTorUse"), ["setTorUse", "all"])
        },
        function (v) {
            var vis = function (n) { return findAll(view.item, n, 0, []).filter(function (o) { return o.visible })[0] || null }
            expect("a refusal shows in the sheet", vis("nodeSetupNote") ? vis("nodeSetupNote").message : "",
                   "invalid parameters: torUse must be all, identifying or none")
            expect("...which stays open", prop("networkSheet", "visible"), true)
            fake.torUseReply = ""
            vis("torUse_none").clicked()
            expect("picking an option saves it", fake.last("setTorUse"), ["setTorUse", "none"])
        },
        function (v) {
            expect("picked: saved, so the button is Done", [prop("networkSheetDone", "text"), v.nodeSetupNeeded], ["Done", false])
            v.closeSheets()
            v.torUseAnswered = false
            expect("...and the notice never shows again", shown("nodeSetupNotice"), false)
            // Another network asks on its own, the first time the person switches to it.
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet4", "signet", "regtest"], active: "signet" })
            fake.sourcesJson = JSON.stringify({ network: "signet", proxy: "tor", torUse: "identifying", torUseChosen: false, sources: [] })
        },
        function (v) {
            expect("a new network: the notice again", [shown("nodeSetupNotice"), v.torUseAnswered], [true, false])
            expect("...for that network", prop("nodeSetupNotice", "title"), "Set up Node for signet")
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet4", "signet", "regtest"], active: "regtest" })
            // Your own node: the existing mode stays stored, for a later switch to public sources.
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "tor", torUse: "all", torUseChosen: false, sources: [
                { id: "kyoto", kind: "kyoto", use: true, route: "tor" },
                { id: "local", kind: "local", url: "logos://bitcoind_module", label: "Your node", use: false, route: "direct" }] })
        },
        function (v) {
            find(view.item, "nodeSetupButton", 0).clicked()
        },
        function (v) {
            var vis = function (n) { return findAll(view.item, n, 0, []).filter(function (o) { return o.visible })[0] || null }
            var before = fake.count("setSource")
            vis("chainChoice_node").clicked()
            expect("your own node turns the node in Logos on", fake.calls.filter(function (c) { return c[0] === "setSource" }).slice(before),
                   [["setSource", "local", JSON.stringify({ use: true })]])
            expect("...without Use Tor for to answer", vis("torUseSettings"), null)
            find(view.item, "networkSheetDone", 0).clicked()
            expect("...and Save still stores the mode", fake.last("setTorUse"), ["setTorUse", "all"])
        },
        function (v) {
            expect("saved: the sheet closes", prop("networkSheet", "visible"), false)
            v.chainPicked = ""
            // Only while not chosen and no wallet is open: an older node without the key never asks.
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "tor", sources: [] })
            fake.healthJson = JSON.stringify({ overall: "ok", sources: [] })
        },
        function (v) {
            expect("an older node module: no notice", shown("nodeSetupNotice"), false)
            expect("...and no choice in the sources", v.torUse, "")
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "tor", torUse: "identifying", torUseChosen: false, sources: [] })
            fake.statusJson = JSON.stringify({ state: "ready", network: "regtest", activeNetwork: "regtest", group: "g_seg", family: "bitcoin", synced: true })
        },
        function (v) {
            expect("a wallet open: no notice", v.nodeSetupNeeded, false)
            expect("...its tabs instead", shown("walletTabs"), true)
            fake.statusJson = JSON.stringify({ state: "closing", network: "regtest", group: "g_seg", family: "bitcoin" })
        },
        function (v) {
            expect("closing: no notice", v.nodeSetupNeeded, false)
            // Settings, with an account open: the same three options, disabled.
            fake.sourcesJson = JSON.stringify({ network: "regtest", proxy: "tor", torUse: "identifying", torUseChosen: true, sources: [] })
            fake.statusJson = JSON.stringify({ state: "ready", network: "regtest", activeNetwork: "regtest", group: "g_seg", family: "bitcoin", synced: true })
            v.selectTab(4)
        },
        function (v) {
            expect("Settings has the choice", shown("torUseSettings"), true)
            expect("...the node's mode checked", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "checked") }),
                   [true, false, false])
            expect("...disabled while an account is open", ["identifying", "all", "none"].map(function (m) { return prop("torUse_" + m, "enabled") }),
                   [false, false, false])
            expect("...saying why", shown("torUseLocked") && prop("torUseLocked", "text"), "Close your open accounts to change this.")
            expect("...each option's text", prop("torUse_happens_all", "text"),
                   "<b>What happens:</b> Every connection goes through Tor, to Bitcoin nodes reachable only over Tor.")
            expect("...Recommended there too", shown("torUse_recommended_identifying"), true)
            // Closed: the sources sheet before an open, where it can change.
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
        },
        function (v) {
            find(view.item, "networkSettingsButton", 0).clicked()
        },
        function (v) {
            expect("the sheet", prop("networkSheet", "visible"), true)
            var all = findAll(view.item, "torUse_all", 0, []).filter(function (o) { return o.visible })[0]
            expect("closed: enabled", all ? all.enabled : "<none>", true)
            expect("...no lock line", shownAny("torUseLocked"), false)
            expect("identifying: which Tor shows", shownAny("whichTor_builtIn") && shownAny("manageTorLink"), true)
            var vis = function (n) { return findAll(view.item, n, 0, []).filter(function (o) { return o.visible })[0] || null }
            var ys = ["ownNodeOption", "chainChoice_public", "torUse_all", "torUse_identifying", "torUse_none"].map(function (n) {
                var o = vis(n); return o ? Math.round(o.mapToItem(null, 0, 0).y) : -1 })
            expect("most private first: your own node, then public sources, Everything to Nothing",
                   ys.every(function (y, i) { return y >= 0 && (i === 0 || y > ys[i - 1]) }) ? "in order" : JSON.stringify(ys), "in order")
            expect("...the public choices, Bitcoin peers first", v.publicOptions.map(function (o) { return o.mode }), ["peers", "electrum"])
            v.chainPicked = "node"
            v.nodePlacePicked = "local"
            expect("your own node keeps one note, behind its i", [findAll(view.item, "ownNodeNote", 0, []).length,
                   findAll(view.item, "ownNodeNote", 0, []).filter(function (o) { return o.visible }).length, vis("ownNodeInfo") !== null], [1, 0, true])
            vis("openNodeAppButton").clicked()
            var asked = logos.requests[logos.requests.length - 1]
            expect("Open Bitcoin Node raises bitcoin.node.configure", asked.intent + " " + asked.params.network, "bitcoin.node.configure regtest")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the app is missing", vis("nodeAppNote") ? vis("nodeAppNote").text : "", "The Bitcoin Node app is not installed.")
            v.chainPicked = ""
            v.nodePlacePicked = ""
            all.clicked()
            expect("Settings sends the mode", fake.last("setTorUse"), ["setTorUse", "all"])
        },
        function (v) {
            expect("...and shows it", prop("torUse_all", "checked"), true)
            expect("all: Which Tor stays", shownAny("whichTor_builtIn"), true)
            findAll(view.item, "torUse_none", 0, []).filter(function (o) { return o.visible })[0].clicked()
        },
        function (v) {
            expect("none taken", fake.last("setTorUse"), ["setTorUse", "none"])
            expect("none: no Which Tor", shownAny("whichTor_builtIn") || shownAny("whichTor_own") || shownAny("ownTorPane")
                   || shownAny("manageTorLink") || shownAny("torBadge"), false)
            fake.torUseReply = "Close the wallet to change these settings."
            findAll(view.item, "torUse_identifying", 0, []).filter(function (o) { return o.visible })[0].clicked()
        },
        function (v) {
            expect("a refusal shows under the choice", shownAny("torUseNote") && prop("torUseNote", "message"), "Close the wallet to change these settings.")
            expect("...the mode unchanged", prop("torUse_none", "checked"), true)
            fake.torUseReply = ""
            v.closeSheets()
        },
        function (v) {
            // A short window: the Node sheet scrolls, and its bar must leave the right-aligned "i" clear.
            fake.statusJson = JSON.stringify({ state: "no_wallet", activeNetwork: "regtest" })
            scene.height = 560
            find(view.item, "networkSheet", 0).open()
        },
        function (v) {
            var sv = find(view.item, "networkSheet", 0).contentItem
            var info = findAll(view.item, "privacyInfo", 0, []).filter(function (o) { return o.visible })[0]
            expect("a short window: the Node sheet scrolls", sv.effectiveScrollBarWidth > 0, true)
            expect("...and its bar leaves the info button clear",
                   info ? Math.round(info.mapToItem(sv, info.width, 0).x) <= sv.width - sv.effectiveScrollBarWidth : "<no privacyInfo>", true)
            v.closeSheets()
            scene.height = 900
        }
    ]
    property int step: 0
    property string keptAlerts: ""
    property string keptBalances: ""
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
