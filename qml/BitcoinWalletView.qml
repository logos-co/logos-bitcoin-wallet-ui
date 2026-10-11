import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The Bitcoin wallet: "Open a wallet", decided in the keys app, then Home, Send, Receive, Activity
// and Settings. No password field. Strings this view did not author render as PlainText.
Item {
    id: root
    objectName: "bitcoinWalletRoot"
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("bitcoin_wallet_ui")
    property bool ready: false

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "bitcoin_wallet_ui") root.ready = isReady && root.backend !== null
        }
    }
    Component.onCompleted: root.ready = root.backend !== null && logos.isViewModuleReady("bitcoin_wallet_ui")

    function j(t, fb) { try { return JSON.parse(t && t.length ? t : fb) } catch (e) { return JSON.parse(fb) } }

    // ---- the wallet ----
    readonly property bool statusRead: ready && backend.statusJson !== ""
    readonly property var status: statusRead ? j(backend.statusJson, "{}") : ({})
    readonly property string walletState: status.state || ""
    readonly property bool walletOpen: walletState === "syncing" || walletState === "ready"
    readonly property bool awaitingKeys: walletState === "awaiting_open"
    readonly property bool opening: awaitingKeys || walletState === "opening" || pendingKind === "open" || pendingKind === "cancel"
    readonly property string openHandle: awaitingKeys ? (status.openHandle || "") : ""
    readonly property bool busy: ready && backend.busy === true
    readonly property string pendingKind: ready ? backend.pendingJobKind : ""
    readonly property var lastJob: ready ? j(backend.lastJobJson, "{}") : ({})
    readonly property var networks: ready ? j(backend.networksJson, "{}") : ({})
    readonly property string activeNetwork: networks.active || status.activeNetwork || ""
    readonly property string displayedNetwork: (walletOpen || opening) && status.network ? status.network : activeNetwork
    readonly property var wallets: ready ? j(backend.walletsJson, "[]") : []
    readonly property var walletsOnNetwork: wallets.filter(function (w) { return !w.network || w.network === root.activeNetwork })
    // Source settings apply when a wallet opens; while one is open, opening or closing they show but do not change.
    readonly property bool networkLocked: walletOpen || opening || walletState === "closing" || busy

    // ---- what the wallet holds ----
    readonly property bool balancesRead: ready && backend.balancesJson !== ""
    readonly property var balances: balancesRead ? j(backend.balancesJson, "{}") : ({})
    readonly property var tooSmall: balances.tooSmall || ({})
    readonly property bool historyRead: ready && backend.historyJson !== ""
    readonly property var historyData: historyRead ? j(backend.historyJson, "{}") : ({})
    readonly property var historyRows: Array.isArray(historyData.rows) ? historyData.rows : []
    readonly property int historyPage: ready ? backend.historyPage : 0
    // Home lists these from the newest page only: it holds every unsettled row.
    readonly property var homeRows: historyPage === 0 ? historyRows : []
    readonly property var pendingRows: homeRows.filter(function (r) { return r.state === "pending" })
    readonly property var unconfirmedSends: homeRows.filter(function (r) { return root.canSpeedUp(r) })
    readonly property var receive: ready && backend.receiveJson !== "" ? j(backend.receiveJson, "{}") : ({})
    readonly property var feeRates: ready && backend.feeRatesJson !== "" ? j(backend.feeRatesJson, "{}") : ({})
    readonly property bool feesKnown: isNum(feeRates.normal) && Number(feeRates.normal) > 0

    // ---- sources ----
    readonly property bool sourcesRead: ready && backend.sourcesJson !== ""
    readonly property var sourcesInfo: sourcesRead ? j(backend.sourcesJson, "{}") : ({})
    // The backend fills a network's defaults on its first pass; until then the list is not "none".
    readonly property bool sourcesConfigured: sourcesRead && sourcesInfo.configured !== false
    readonly property var sourceList: Array.isArray(sourcesInfo.sources) ? sourcesInfo.sources : []
    readonly property var health: ready ? j(backend.healthJson, "{}") : ({})
    readonly property string overall: health.overall || ""
    readonly property var exposure: ready ? j(backend.exposureJson, "{}") : ({})
    readonly property var exposureServers: Array.isArray(exposure.servers) ? exposure.servers : []
    readonly property var alerts: ready ? j(backend.alertsJson, "[]") : []
    readonly property var withoutTor: Array.isArray(sourcesInfo.withoutTor) ? sourcesInfo.withoutTor : []
    readonly property var exposes: Array.isArray(sourcesInfo.exposes) ? sourcesInfo.exposes : []
    readonly property var chainSources: root.chainSourcesOf(sourceList)
    readonly property var chainOperators: root.operatorsOf(chainSources)
    readonly property bool serversDecideChain: chainSources.length > 0 && chainSources.every(function (s) { return s.kind === "electrum" })
    readonly property string defaultProxy: "socks5h://127.0.0.1:9050"
    // A switch waiting for its confirmation, by source id; the confirmation shows in that row.
    property string historyAskedFor: ""
    property string torOffAskedFor: ""
    // What a settings call refused, shown where it was made ("proxy" or "sources").
    property string networkNote: ""
    property string networkNoteAt: ""
    onNetworkLockedChanged: { historyAskedFor = ""; torOffAskedFor = ""; networkNote = "" }

    // ---- the send on screen ----
    readonly property string sendId: ready ? backend.sendRequestId : ""
    readonly property bool sendOpen: sendId !== ""
    readonly property var send: ready ? j(backend.sendStatusJson, "{}") : ({})
    readonly property string sendState: sendOpen ? (send.state || "") : ""
    readonly property bool sendLive: sendState === "preparing" || sendState === "awaiting_approval" || sendState === "committing"
    readonly property bool sendSettled: sendOpen && !sendLive
    readonly property bool ownSend: !send.requester || send.requester === "bitcoin_wallet_ui"
    readonly property var summary: send.summary ? send.summary : null
    readonly property string approvalHandle: sendState === "awaiting_approval" ? (send.approvalHandle || "") : ""
    // The review before a request exists: what the form says, and the request it would make.
    property bool reviewDraft: false
    property var draft: null
    // The last request this view made, kept to ask again after an offer nobody acknowledged.
    property var lastRequest: null
    property string signerAskedFor: ""
    property string signerNote: ""
    property string sendNote: ""
    onSendIdChanged: {
        root.signerNote = ""
        root.sendNote = ""
        root.forgetNote = ""
        if (root.sendId !== "") {
            sendGoneTimer.stop()
            root.reviewDraft = false
            if (root.walletOpen && !reviewSheet.visible) reviewSheet.open()
        } else if (!root.reviewDraft) {
            sendGoneTimer.restart()
        }
    }
    // A new request clears the settled send first; closing at once would make the review flicker.
    Timer { id: sendGoneTimer; interval: 600; onTriggered: if (root.sendId === "" && !root.reviewDraft) reviewSheet.close() }
    onApprovalHandleChanged: if (root.approvalHandle !== "" && root.ownSend && root.approvalHandle !== root.signerAskedFor) root.askSigner()
    property string lastSendState: ""
    onSendStateChanged: {
        if (root.sendState === "sent" && root.lastSendState !== "")
            root.notify(root.send.kind === "fee_bump" ? "Fee raised" : "Sent", "It shows in Activity, and confirms once mined.")
        root.lastSendState = root.sendState
    }

    // ---- the keys app ----
    property string keysAskedFor: ""
    property string keysNote: ""
    onOpenHandleChanged: if (root.openHandle !== "" && root.openHandle !== root.keysAskedFor) root.askKeys()
    // The person picks, creates or restores a wallet there; this app never sees a password.
    function askKeys() {
        var h = root.openHandle
        if (h === "") return
        root.keysAskedFor = h
        root.keysNote = ""
        logos.request("keystore.accounts.open", ({ handle: h }), function (res) {
            if (res.ok || h !== root.openHandle) return
            root.keysNote = root.keysNoteFor(res.error)
        })
    }
    function keysNoteFor(error) {
        if (error === "unavailable") return "The keys app is not installed here. Install it, open it, and approve the request under Requests from apps."
        if (error === "cancelled") return "The keys app closed without a decision. Ask again, or cancel."
        if (error === "rejected") return "You declined in the keys app."
        if (error === "bad_request") return "The keys app no longer holds this request. Cancel, and open the wallet again."
        if (error === "timeout") return "The keys app did not answer. Ask again, or cancel."
        return "That request did not go through (" + error + ")."
    }
    // Advisory: send_status settles the send, whatever the signer app answers here.
    function askSigner() {
        var h = root.approvalHandle
        if (h === "") return
        root.signerAskedFor = h
        root.signerNote = ""
        logos.request("evm.signing.approve", ({ handle: h }), function (res) {
            if (res.ok || h !== root.approvalHandle) return
            root.signerNote = root.signerNoteFor(res.error)
        })
    }
    function signerNoteFor(error) {
        if (error === "unavailable") return "The signer app is not installed here. Open it within 60 s to approve or reject this send, or cancel it."
        if (error === "cancelled") return "The signer app closed without a decision. Open it again, or cancel the send."
        if (error === "timeout") return "The signer app did not answer. Open it again, or cancel the send."
        return "Could not reach the signer app (" + error + ")."
    }

    // ---- jobs ----
    // The job already settled when the view connected is history, not news.
    property string handledJobId: ""
    property bool jobsPrimed: false
    function primeJobs() {
        if (root.jobsPrimed || !root.ready) return
        root.handledJobId = root.j(backend.lastJobJson, "{}").jobId || ""
        root.jobsPrimed = true
    }
    onReadyChanged: root.primeJobs()
    onLastJobChanged: {
        root.primeJobs()
        if (!lastJob.jobId || lastJob.jobId === root.handledJobId) return
        root.handledJobId = lastJob.jobId
        if (lastJob.kind === "open" && lastJob.state === "done") root.notify("Wallet open", "Its balance fills in as it syncs.")
        if (lastJob.kind === "cancel") root.notify("Not opened", "The request to the keys app was withdrawn.")
    }

    // 0 Home, 1 Send, 2 Receive, 3 Activity, 4 Settings. selectTab is the driver entry point.
    property int page: 0
    function selectTab(i) { root.page = i; tabs.currentIndex = i }
    function selectNetwork(network) {
        if (root.ready && !root.networkLocked) backend.setActiveNetwork(network)
    }
    function closeSheets() {
        reviewSheet.close(); speedUpSheet.close(); forgetSheet.close(); networkSheet.close(); descriptorsSheet.close()
    }
    // Public descriptors, shown on Settings until it is left or the wallet closes.
    property var shownDescriptors: null
    property string descriptorsNote: ""
    onWalletOpenChanged: {
        root.shownDescriptors = null
        root.closeSheets()
        root.openTx = ""
        root.recipientCheck = ({})
        if (sendTo.text.trim() !== "") recipientCheckTimer.restart()
        if (root.walletOpen) root.selectTab(0)
    }
    onPageChanged: if (root.page !== 4) root.shownDescriptors = null
    function notify(title, message) { toast.show(title, message) }

    // ================= pure helpers: the state tests drive these =================
    function isNum(v) { return v !== undefined && v !== null && v !== "" && isFinite(Number(v)) }
    function group(n) {
        if (!root.isNum(n)) return "—"
        var neg = Number(n) < 0
        var s = String(Math.floor(Math.abs(Number(n)))), out = ""
        while (s.length > 3) { out = "," + s.slice(-3) + out; s = s.slice(0, -3) }
        return (neg ? "-" : "") + s + out
    }
    // Satoshis as BTC, exact (integers stay below 2^53), trailing zeros trimmed: 60000 -> "0.0006".
    function btcOf(sat) {
        if (!root.isNum(sat)) return "—"
        var n = Math.round(Number(sat)), neg = n < 0
        n = Math.abs(n)
        var frac = String(n % 100000000)
        while (frac.length < 8) frac = "0" + frac
        frac = frac.replace(/0+$/, "")
        return (neg ? "-" : "") + Math.floor(n / 100000000) + (frac ? "." + frac : "")
    }
    function satsText(sat) {
        if (!root.isNum(sat)) return "—"
        return root.group(sat) + (Number(sat) === 1 ? " sat" : " sats")
    }
    // What the user typed as a whole number of satoshis, or "" when it is no amount.
    function satFromInput(text, unit) {
        var t = (text || "").trim()
        if (unit === "sat") {
            if (!/^[0-9]{1,16}$/.test(t)) return ""
            var s = t.replace(/^0+/, "")
            return s === "" || Number(s) > 2100000000000000 ? "" : s
        }
        var m = /^([0-9]{0,8})(?:\.([0-9]{0,8}))?$/.exec(t)
        if (!m || (m[1] === "" && (m[2] === undefined || m[2] === ""))) return ""
        var frac = m[2] || ""
        while (frac.length < 8) frac = frac + "0"
        var sat = Number(m[1] || "0") * 100000000 + Number(frac)
        return sat > 0 && sat <= 2100000000000000 ? String(sat) : ""
    }
    function ageText(secs) {
        if (!root.isNum(secs) || Number(secs) < 0) return ""
        var n = Number(secs)
        if (n < 60) return "under a minute"
        var m = Math.floor(n / 60)
        if (m < 60) return m + " min"
        var h = Math.floor(m / 60)
        if (h < 48) return h + (h === 1 ? " hour" : " hours")
        var d = Math.floor(h / 24)
        return d + (d === 1 ? " day" : " days")
    }
    // A wallet_status() reply's sync state. Never "synced" with no agreeing source, nor with a
    // tip older than an hour: a peerless chain looks complete exactly when it is stale.
    function syncState(st) {
        var s = st && st.state ? st.state : ""
        if (st && st.unavailable) return "unavailable"
        if (s === "awaiting_open") return "keys"
        if (s === "opening") return "opening"
        if (s === "closing") return "closing"
        if (s === "failed") return "failed"
        if (s !== "syncing" && s !== "ready") return ""
        var a = st.authority || {}
        var peers = root.isNum(a.peers) ? Number(a.peers) : 0
        if (!root.isNum(a.height)) return peers > 0 ? "headers" : "connecting"
        if (peers <= 0) return "isolated"
        var tip = st.walletTip
        var caughtUp = root.isNum(tip) ? Number(tip) >= Number(a.height) : st.synced === true
        // Regtest's blocks come when someone mines one: its tip age says nothing.
        if (st.network === "regtest") return caughtUp ? "local" : "syncing"
        if (root.isNum(a.tipAgeSecs) && Number(a.tipAgeSecs) > 3600) return "stalled"
        return caughtUp ? "synced" : "syncing"
    }
    function syncLabel(st) {
        var a = st && st.authority ? st.authority : {}
        var age = root.ageText(a.tipAgeSecs)
        var h = root.group(a.height)
        switch (root.syncState(st)) {
        case "unavailable": return "The wallet backend is not answering"
        case "keys": return "Waiting for the keys app"
        case "opening": return "Opening the wallet…"
        case "closing": return "Closing…"
        case "failed": return "Failed" + (st.lastError ? ": " + st.lastError : "")
        case "connecting": return "Connecting to the chain's sources…"
        case "headers": return "Reading the chain's headers…"
        case "isolated": return "No source agrees · block " + h + (age ? ", tip " + age + " old" : "")
        case "stalled": return "Stalled · block " + h + ", tip " + age + " old"
        case "syncing": return "Syncing" + (root.isNum(st.syncPercent) ? " " + st.syncPercent + "%" : "")
                               + (root.isNum(st.walletTip) ? " · block " + root.group(st.walletTip) + " of " + h
                                                           : " · the chain is at block " + h)
        case "local": return "Local chain · block " + h
        case "synced": return "Synchronized · block " + h + ", tip " + age + " old"
        }
        return ""
    }
    function syncChip(st) {
        switch (root.syncState(st)) {
        case "unavailable": return "Not answering"
        case "closing": return "Closing…"
        case "failed": return "Failed"
        case "connecting": case "headers": return "Connecting…"
        case "isolated": return "No sources"
        case "stalled": return "Stalled"
        case "syncing": return "Syncing" + (root.isNum(st.syncPercent) ? " " + st.syncPercent + "%" : "")
        case "local": return "Local · " + root.group(st.authority.height)
        case "synced": return "Synced · " + root.group(st.authority.height)
        }
        return ""
    }
    function syncColor(st) {
        var s = root.syncState(st)
        if (s === "synced" || s === "local") return Theme.palette.success
        if (s === "isolated" || s === "stalled" || s === "failed" || s === "unavailable") return Theme.palette.error
        return Theme.palette.textSecondary
    }
    // What decides the chain, and how many sources agree on it.
    function authorityLine(st) {
        var a = st && st.authority ? st.authority : {}
        var n = root.isNum(a.peers) ? Number(a.peers) : 0
        if (a.kind === "electrum_headers")
            return "The chain: headers from Electrum servers, checked here · " + n + (n === 1 ? " server agrees" : " servers agree")
        if (a.kind === "kyoto") return "The chain: Bitcoin peers, through block filters · " + n + (n === 1 ? " peer" : " peers")
        if (a.kind === "local") return "The chain: your own node"
        return ""
    }

    // What a send came to: its errorCode, else its text. An unknown send given up is "forgotten".
    function sendOutcome(s) {
        var st = s && s.state ? s.state : ""
        if (st === "") return ""
        if (st === "preparing" || st === "awaiting_approval" || st === "committing") return "live"
        if (st === "sent") return "sent"
        if (st === "unknown") return s.abandoned === true ? "forgotten" : "unknown"
        var code = s.errorCode || "", text = String(s.error || "")
        if (code === "expired" || (code === "" && /^expired/.test(text))) return "expired"
        if (code === "rejected" || (code === "" && /^rejected/.test(text))) return "rejected"
        if (st === "cancelled" || code === "cancelled") return "cancelled"
        return "failed"
    }
    function sendHeadline(s) {
        switch (root.sendOutcome(s)) {
        case "live":
            if (s.cancelling) return "Cancelling…"
            if (s.state === "preparing") return "Building the transaction…"
            if (s.state === "committing") return "Approved · broadcasting…"
            return s.approval === "rendered" || s.approval === "signing" ? "The signer app is showing it"
                                                                         : "Approve it in the signer app"
        case "sent": return s.kind === "fee_bump" ? "Fee raised" : "Sent"
        case "unknown": return "The outcome is unknown: it may have left"
        case "forgotten": return "Forgotten"
        case "expired": return "Nobody approved it within 60 s"
        case "rejected": return "Rejected in the signer app"
        case "cancelled": return "Cancelled"
        }
        var code = s && s.errorCode ? s.errorCode : ""
        if (code === "insufficient_funds") return "Not enough confirmed bitcoin for this and its fee"
        if (code === "no_route") return "No source can broadcast it"
        if (code === "busy") return "The wallet was busy"
        if (code === "refused") return "A source refused the transaction"
        if (code === "no_wallet") return "The wallet closed before it was sent"
        if (code === "signer_unavailable") return "The signer could not be reached"
        if (code === "invalid") return "The request was not valid"
        if (code === "coins_changed") return "The wallet's coins changed while it waited"
        if (code === "core_lost") return "The wallet core stopped answering"
        if (code === "backend_restarted") return "The wallet backend restarted"
        return "The send failed"
    }
    // The backend's own words under the headline, unless the headline already says it all.
    function sendDetail(s) {
        var o = root.sendOutcome(s)
        if (o === "expired") return "The signer app never showed the request, so it expired. Ask again to send it once more."
        if (o === "unknown") return "Rebroadcast it, or replace it with a higher fee. Do not pay again from other coins while it could still confirm."
        if (o === "forgotten") return "Its coins are spendable again. If it still confirms, a later send from those coins fails; "
                                      + "if a later send confirms first, it replaces this one."
        if (o === "rejected" || o === "live" || o === "sent" || o === "cancelled") return ""
        var code = s.errorCode || ""
        if (code === "coins_changed") return "A coin it spent is no longer the wallet's to spend. Nothing went out: try again."
        if (code === "core_lost") return "It stopped before the send was approved, so nothing went out: try again."
        if (code === "backend_restarted") return "The wallet core no longer has this send, and nothing went out: try again."
        if (code === "busy") return "Nothing went out: try again in a moment."
        return String(s.error || "")
    }
    // A failure worth repeating as it was: the same request, a new approval.
    function canRetry(s) {
        var o = root.sendOutcome(s)
        if (o === "expired") return true
        return o === "failed" && ["coins_changed", "core_lost", "backend_restarted", "busy", "signer_unavailable"].indexOf(s.errorCode || "") >= 0
    }
    // What the backend offers for an unknown send; a backend without `offer` offers all three.
    function offers(s, what) {
        if (!s || s.state !== "unknown" || s.abandoned === true) return false
        return Array.isArray(s.offer) ? s.offer.indexOf(what) >= 0 : true
    }
    // The lane: Build, Approve in Signer, Broadcast, Sent; past the last stage once sent.
    function sendStage(s) {
        var st = s && s.state ? s.state : ""
        if (st === "preparing") return 0
        if (st === "awaiting_approval") return 1
        if (st === "committing" || st === "unknown") return 2
        if (st === "sent") return 4
        if (s && s.txid && s.broadcast) return 2
        return s && s.summary ? 1 : 0
    }
    function speedUpRate(row) {
        var fast = Number(root.feeRates.fast || 0)
        return Math.max(2, Math.ceil(fast))
    }
    function canSpeedUp(r) {
        return r && r.state === "sent" && r.intent !== "receive" && !r.replacedBy
    }

    // What each transaction was for: the wallet core decides it from the transaction itself.
    function intentLine(r) {
        var fee = root.isNum(r.feeSat) ? " · fee " + root.satsText(r.feeSat) : ""
        var amount = root.btcOf(r.amountSat) + " BTC"
        if (r.intent === "send") return "−" + amount + fee
        if (r.intent === "self") return amount + " to yourself" + fee
        if (r.intent === "combine") return (r.coins || 0) + " coins combined" + fee
        if (r.intent === "fee_bump") return "Fee raised to " + (root.isNum(r.feeSat) ? root.satsText(r.feeSat) : "—")
        if (r.intent === "receive") return "+" + amount
        return amount
    }
    function rowState(r) {
        if (r.state === "confirmed") {
            var n = Number(r.confirmations || 0)
            return n >= 6 ? "confirmed" : (n === 1 ? "1 confirmation" : n + " confirmations")
        }
        if (r.state === "waiting") return "waiting for the wallet's chain"
        if (r.state === "pending") return "pending" + (r.reportedBy ? " · reported by " + r.reportedBy : "")
        if (r.state === "sent") return "sent · not confirmed"
        if (r.state === "replaced") return "replaced"
        return r.state || ""
    }
    function rowStateColor(r) {
        if (r.state === "confirmed") return Theme.palette.success
        if (r.state === "replaced") return Theme.palette.textTertiary
        return Theme.palette.warning
    }
    function whenOf(t) { return root.isNum(t) && Number(t) > 0 ? new Date(Number(t) * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : "" }
    function shortId(s) { return s && s.length > 20 ? s.slice(0, 10) + "…" + s.slice(-8) : (s || "") }
    function familyLabel(f) {
        if (f === "bitcoin") return "Native segwit"
        if (f === "bitcoin_taproot") return "Taproot"
        return f || "—"
    }

    // Sources that define the chain, as the node module routes them: the local node, else
    // Kyoto, else every Electrum server in use. Suspect sources are not routed.
    function chainSourcesOf(list) {
        var on = list.filter(function (s) { return s.use === true && s.suspect !== true })
        var local = on.filter(function (s) { return s.kind === "local" })
        if (local.length) return local
        var kyoto = on.filter(function (s) { return s.kind === "kyoto" })
        if (kyoto.length) return kyoto
        return on.filter(function (s) { return s.kind === "electrum" })
    }
    // Operators, not hosts: hosts of one operator count once.
    function operatorsOf(list) {
        var seen = [], out = []
        list.forEach(function (s) {
            var k = String(s.operator || "").toLowerCase()
            if (k !== "" && seen.indexOf(k) < 0) { seen.push(k); out.push(s.operator) }
        })
        return out
    }
    function kindLabel(k) {
        if (k === "kyoto") return "Kyoto"
        if (k === "electrum") return "Electrum"
        if (k === "esplora") return "Esplora"
        if (k === "local") return "Your node"
        return k || ""
    }
    function isServer(s) { return s.kind === "electrum" || s.kind === "esplora" }
    function isOnion(s) { return /\.onion(:[0-9]+)?(\/|$)/i.test(String(s.url || "").replace(/^[a-z]+:\/\//i, "")) }
    function routeText(s) {
        if (s.kind === "local") return "over Logos IPC"
        if (s.lan) return "reached directly, on your network"
        if (root.isOnion(s)) return "an onion service, always through Tor"
        return s.route === "direct" ? "without Tor" : "through Tor"
    }
    // What a source sees of this computer without Tor, by what it does.
    function torOffText(s) {
        var sees = s.kind === "kyoto" ? "Its peers see this computer's IP address, the blocks the wallet downloads and the transactions it broadcasts."
                 : s.history === true ? "It sees this computer's IP address, linked to every address and transaction of this wallet."
                 : "It sees this computer's IP address, and that a Bitcoin wallet runs here."
        return sees + " Your internet provider sees that this computer uses Bitcoin."
    }
    function historyOnText(s) {
        return (s.label || s.id) + " will learn every address of this wallet and can link them to each other"
               + (s.route === "direct" && !s.lan ? ", and to this computer's IP address, since it is reached without Tor" : "")
               + ". If it fails, the next server with History on learns them too. In return it gives faster restores, "
               + "and payments while they are still pending."
    }
    function healthOf(id) {
        var list = Array.isArray(root.health.sources) ? root.health.sources : []
        for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return list[i]
        return null
    }
    // The open wallet's own view of a source: { state, history, suspect, ... }.
    function walletViewOf(id) {
        var w = root.health.wallet && Array.isArray(root.health.wallet.sources) ? root.health.wallet.sources : []
        for (var i = 0; i < w.length; i++) if (w[i] && w[i].id === id) return w[i]
        return null
    }
    function healthLine(s) {
        var w = root.walletViewOf(s.id)
        var h = root.healthOf(s.id)
        var parts = []
        if (w && w.history) parts.push("history server")
        if (w && (w.state === "stale" || w.state === "failing" || w.state === "down")) parts.push(w.state)
        if (!h) parts.push("not checked yet")
        else if (h.state === "ok") parts.push((root.isNum(h.rttMs) ? h.rttMs + " ms" : "reachable") + (root.isNum(h.tipHeight) ? " · block " + root.group(h.tipHeight) : ""))
        else if (h.state === "unreachable") parts.push("unreachable" + (h.error ? ": " + h.error : ""))
        else if (h.state === "wrong_network") parts.push("on another network")
        else if (h.state === "no_route") parts.push("no route" + (h.error ? ": " + h.error : ""))
        else if (h.state === "no_peers") parts.push(h.error ? h.error : "no peer to dial")
        else if (h.state === "not_probed") parts.push(s.kind === "kyoto" && root.isNum(h.peers) ? h.peers + " peers today" : "not probed here")
        else parts.push("not checked yet")
        return parts.join(" · ")
    }
    function overallLabel(o) {
        if (o === "ok") return "Sources OK"
        if (o === "degraded") return "Sources degraded"
        if (o === "disagreement") return "Sources disagree"
        if (o === "offline") return "Sources offline"
        return o
    }
    function overallColor(o) { return o === "ok" ? Theme.palette.success : (o === "degraded" ? Theme.palette.warning : Theme.palette.error) }
    function alertTitle(a) {
        if (a.kind === "suspect") return "A source is suspect"
        if (a.kind === "stale") return "A source is behind"
        if (a.kind === "authority_behind") return "The wallet's chain may be behind"
        if (a.kind === "anchor_mismatch") return "A source reported a payment on another chain"
        return "A source needs attention"
    }
    // A settings SLOT's reply: "" or the refusal, shown at `at`; `refused` runs on a refusal.
    function networkCall(reply, at, refused) {
        root.networkNote = ""
        logos.watch(reply,
                    function (e) {
                        root.networkNoteAt = at
                        root.networkNote = e || ""
                        if (e && refused) refused()
                    },
                    function () {
                        root.networkNoteAt = at
                        root.networkNote = "The wallet backend did not answer."
                        if (refused) refused()
                    })
    }
    function setSource(id, changes) { root.networkCall(backend.setSource(id, JSON.stringify(changes)), "sources") }

    // ---- the Send form ----
    property var recipientCheck: ({})
    readonly property string recipientText: sendTo.text.trim()
    readonly property bool recipientChecked: recipientCheck.text !== undefined && recipientCheck.text === recipientText
    readonly property bool recipientValid: recipientChecked && recipientCheck.valid === true
    property string amountUnit: "btc"
    property bool sendMax: false
    property string feeChoice: "normal"
    readonly property string amountSat: satFromInput(sendAmount.text, amountUnit)
    readonly property real chosenRate: feeChoice === "custom" ? Number(feeCustom.text) : Number(feeRates[feeChoice] || 0)
    readonly property bool rateOk: isFinite(chosenRate) && chosenRate > 0 && chosenRate <= 100000
    readonly property bool canReview: ready && walletOpen && !sendLive && sendOutcome(send) !== "unknown"
                                      && recipientValid && (sendMax || amountSat !== "") && rateOk
    function checkRecipient() {
        var t = root.recipientText
        if (t === "" || !root.ready || !root.walletOpen) return
        logos.watch(backend.addressValid(t),
                    function (v) {
                        var r = root.j(v, "{}")
                        if (r.ok !== true) r = { failed: true, reason: r.error || "" }
                        r.text = t
                        root.recipientCheck = r
                        // A payment request names its amount: it fills an empty amount field.
                        if (r.valid === true && root.isNum(r.amountSat) && Number(r.amountSat) > 0 && sendAmount.text.trim() === "" && !root.sendMax) {
                            root.amountUnit = "btc"
                            sendAmount.text = root.btcOf(r.amountSat)
                        }
                    },
                    function () { root.recipientCheck = { text: t, failed: true } })
    }
    function recipientLine(c) {
        if (!c || c.text === undefined) return ""
        if (c.failed) return "Could not check this address" + (c.reason ? ": " + c.reason : ".")
        if (c.valid !== true) return c.reason ? c.reason : "This is not a Bitcoin address on " + (root.displayedNetwork || "this network") + "."
        return ""
    }
    function typeLabel(t) {
        if (t === "p2wpkh") return "native segwit"
        if (t === "p2tr") return "taproot"
        if (t === "p2pkh") return "legacy"
        if (t === "p2sh") return "script"
        if (t === "p2wsh") return "segwit script"
        return t || ""
    }
    // The request the form makes: amounts as exact satoshis, the rate the review showed.
    function buildRequest(address, amountSatText, max, rate) {
        var r = { address: address }
        if (!max) r.amountSat = amountSatText
        var req = { recipients: [r], feeRate: rate }
        if (max) req.sendMax = true
        return req
    }
    // A rough size for a payment from one coin, so the review can say about what the fee is.
    function estimateVsize(family, recipientType, max) {
        var input = family === "bitcoin_taproot" ? 57.5 : 68
        var change = family === "bitcoin_taproot" ? 43 : 31
        var out = recipientType === "p2tr" || recipientType === "p2wsh" ? 43 : (recipientType === "p2pkh" ? 34 : (recipientType === "p2sh" ? 32 : 31))
        return Math.ceil(10.5 + input + out + (max ? 0 : change))
    }
    function review() {
        if (!root.canReview) return
        if (root.sendSettled) backend.dismissSend()
        var address = root.recipientCheck.address || root.recipientText
        root.draft = { address: address, type: root.recipientCheck.type || "", sendMax: root.sendMax,
                       amountSat: root.sendMax ? "" : root.amountSat, rate: root.chosenRate, choice: root.feeChoice,
                       request: root.buildRequest(address, root.amountSat, root.sendMax, root.chosenRate) }
        root.reviewDraft = true
        reviewSheet.open()
    }
    function approveInSigner() {
        if (!root.draft) return
        root.lastRequest = { send: root.draft.request }
        backend.requestSend(JSON.stringify(root.draft.request))
    }
    // Asks again after an offer nobody acknowledged: the same request, a new approval.
    function askAgain() {
        var r = root.lastRequest
        if (!r) return
        if (r.bump) backend.requestFeeBump(r.bump.txid, r.bump.rate)
        else backend.requestSend(JSON.stringify(r.send))
    }
    function speedUp(txid, rate) {
        root.lastRequest = { bump: { txid: txid, rate: rate } }
        backend.requestFeeBump(txid, rate)
    }
    // Done on a settled send is local: the backend refuses to cancel a final send, and a refusal
    // must not leave the form wedged behind it.
    function finishSend() {
        var s = root.sendState
        backend.dismissSend()
        reviewSheet.close()
        if (s === "sent" && root.send.kind !== "fee_bump") { sendTo.text = ""; sendAmount.text = ""; root.sendMax = false }
    }
    property string forgetTxid: ""
    // The backend's note says what forgetting does; it shows in the sheet once it has.
    property string forgetNote: ""
    function forget(txid) {
        root.sendNote = ""
        root.forgetNote = ""
        logos.watch(backend.abandonSend(txid),
                    function (v) {
                        var r = root.j(v, "{}")
                        if (r.ok !== true) { root.sendNote = r.error || "The wallet backend did not answer."; return }
                        root.forgetNote = r.note || "Its coins are spendable again."
                        root.notify("Payment forgotten", "Its coins are spendable again.")
                    },
                    function () { root.sendNote = "The wallet backend did not answer." })
    }

    // Activity's expanded row, by txid.
    property string openTx: ""

    // ================= the sources pane: Settings, and the sheet before a wallet opens =================
    Component {
        id: networkPane
        ColumnLayout {
            id: pane
            spacing: Theme.spacing.small

            // The fields clear at once, so a reply arriving later never wipes the next server typed in.
            function addSource() {
                var address = addSourceAddress.text.trim(), name = addSourceName.text.trim()
                var kind = addSourceKind.currentIndex === 1 ? "esplora" : "electrum"
                addSourceAddress.text = ""
                addSourceName.text = ""
                root.networkCall(backend.addSource(address, kind, name), "sources", function () {
                    if (addSourceAddress.text === "" && addSourceName.text === "") {
                        addSourceAddress.text = address
                        addSourceName.text = name
                    }
                })
            }

            LogosNotice {
                objectName: "networkLockedNotice"
                Layout.fillWidth: true
                shown: root.networkLocked
                message: "These settings apply when a wallet opens. Close the wallet to change them."
            }

            LogosText { text: "Network privacy"; font.pixelSize: 15 }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "Sources go through this Tor proxy, unless you set one to skip Tor. Servers on your own network "
                              + "are reached directly, since Tor cannot reach them. A source set to Tor never falls back to a direct connection." }
            RowLayout {
                Layout.fillWidth: true
                LogosTextField { id: proxyField; objectName: "proxyField"; Layout.fillWidth: true; readOnly: root.networkLocked
                                 placeholderText: root.defaultProxy; text: root.sourcesInfo.proxy || "" }
                LogosButton {
                    objectName: "saveProxyButton"; text: "Save proxy"
                    visible: !root.networkLocked
                    enabled: root.ready && proxyField.text.trim() !== "" && proxyField.text.trim() !== (root.sourcesInfo.proxy || "")
                    onClicked: root.networkCall(backend.setProxy(proxyField.text.trim()), "proxy")
                }
            }
            LogosNotice {
                Layout.fillWidth: true
                severity: LogosNotice.Error
                shown: root.networkNote !== "" && root.networkNoteAt === "proxy"
                message: shown ? root.networkNote : ""
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                LogosText { text: "Sources"; font.pixelSize: 15 }
                LogosInfoButton {
                    objectName: "operatorsInfo"
                    title: "Why a second operator matters"
                    text: "Kyoto, when it serves the chain, asks several Bitcoin peers run by different people. A second server "
                          + "operator adds four things. The cross-check compares its tip, and a header at a random height, with "
                          + "the wallet's chain, which catches a server that lags or follows another chain. If the server holding "
                          + "the wallet's history fails, the wallet moves to the next one with History on, which then learns the "
                          + "addresses too. Fee rates become the median of the sources. With Kyoto off, the chain is the one with "
                          + "the most work among the Electrum servers in use, so a server that hides blocks loses to another "
                          + "operator. A second operator does not make the history more complete: only one server is asked about "
                          + "the wallet's addresses at a time."
                }
                LogosBadge { visible: root.overall !== ""; text: root.overallLabel(root.overall); color: root.overallColor(root.overall) }
                Item { Layout.fillWidth: true }
            }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                        text: "Switch on the sources you want, one by one. Kyoto asks Bitcoin peers for blocks and learns no address. "
                              + "A server with History on learns every address of this wallet." }
            // Above the list, so it stays in place however long the list grows.
            ColumnLayout {
                objectName: "addSourcePane"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                visible: !root.networkLocked
                spacing: Theme.spacing.tiny
                LogosText { text: "Add a server of your own"; font.weight: Theme.typography.weightMedium }
                LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                            text: "An Electrum or Esplora server you run or trust: an address like 192.168.1.20:50001 or electrs.lan, "
                                  + "or https://host:port. Servers on your own network are reached directly, without Tor." }
                RowLayout {
                    Layout.fillWidth: true
                    LogosTextField { id: addSourceAddress; objectName: "addSourceAddress"; Layout.fillWidth: true
                                     placeholderText: "192.168.1.20:50001" }
                    LogosComboBox { id: addSourceKind; objectName: "addSourceKind"; model: ["Electrum", "Esplora"] }
                    LogosTextField { id: addSourceName; objectName: "addSourceName"; Layout.preferredWidth: 160
                                     placeholderText: "Name (optional)" }
                    LogosButton { objectName: "addSourceButton"; text: "Add"
                                  enabled: root.ready && addSourceAddress.text.trim() !== ""; onClicked: pane.addSource() }
                }
            }
            LogosNotice {
                objectName: "sourcesNote"
                Layout.fillWidth: true
                severity: LogosNotice.Error
                shown: root.networkNote !== "" && root.networkNoteAt === "sources"
                message: shown ? root.networkNote : ""
            }
            LogosText { objectName: "sourcesEmpty"; visible: root.sourceList.length === 0; color: Theme.palette.textSecondary
                        text: !root.sourcesRead ? "Reading the sources…"
                              : !root.sourcesConfigured ? "Setting up the sources for " + (root.sourcesInfo.network || "this network") + "…"
                              : "No sources on this network yet: add a server of your own." }
            Repeater {
                model: root.sourceList
                LogosFrame {
                    id: sourceRow
                    readonly property bool server: root.isServer(modelData)
                    readonly property bool onion: root.isOnion(modelData)
                    readonly property bool direct: modelData.route === "direct" && !modelData.lan && modelData.kind !== "local"
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.tiny
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { textFormat: Text.PlainText; text: modelData.label || modelData.id || "" }
                            // Operators matter for servers: Kyoto's peers and your node have none to compare.
                            LogosText { visible: sourceRow.server && text !== "" && text !== (modelData.label || ""); textFormat: Text.PlainText
                                        color: Theme.palette.textTertiary; text: modelData.operator || "" }
                            LogosBadge { text: root.kindLabel(modelData.kind); color: Theme.palette.textSecondary }
                            LogosBadge { objectName: "lanBadge_" + modelData.id; visible: modelData.lan === true && modelData.kind !== "local"
                                         text: "Your network"; color: Theme.palette.textSecondary }
                            LogosBadge { objectName: "withoutTorBadge_" + modelData.id; visible: sourceRow.direct && modelData.use === true
                                         text: "Without Tor"; color: Theme.palette.warning }
                            LogosBadge { objectName: "suspectBadge_" + modelData.id; visible: modelData.suspect === true
                                         text: "Suspect"; color: Theme.palette.error }
                            // Takes the free space but asks for none, so a long error elides instead of
                            // widening the row and pushing its switches out.
                            LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideMiddle; textFormat: Text.PlainText; font.pixelSize: 12
                                        color: Theme.palette.textSecondary
                                        text: modelData.use === true ? root.healthLine(modelData) : "" }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; textFormat: Text.PlainText
                                        font.pixelSize: 11; color: Theme.palette.textTertiary
                                        text: (modelData.url || "") + " · " + root.routeText(modelData)
                                              + (modelData.history === true ? " · learns your addresses" : "") }
                            // On needs no asking; History on and Tor off ask first, in this row.
                            LogosSwitch {
                                objectName: "useSwitch_" + modelData.id
                                visible: !root.networkLocked
                                text: "Use"
                                checkable: false
                                checked: modelData.use === true
                                enabled: root.ready
                                onClicked: root.setSource(modelData.id, { use: !(modelData.use === true) })
                            }
                            LogosSwitch {
                                objectName: "historySwitch_" + modelData.id
                                visible: !root.networkLocked && sourceRow.server
                                text: "History"
                                checkable: false
                                checked: modelData.history === true
                                enabled: root.ready
                                onClicked: {
                                    if (modelData.history === true) root.setSource(modelData.id, { history: false })
                                    else { root.torOffAskedFor = ""; root.historyAskedFor = modelData.id }
                                }
                            }
                            LogosSwitch {
                                objectName: "torSwitch_" + modelData.id
                                visible: !root.networkLocked && modelData.kind !== "local" && modelData.lan !== true && !sourceRow.onion
                                text: "Tor"
                                checkable: false
                                checked: modelData.tor === true
                                enabled: root.ready
                                onClicked: {
                                    if (modelData.tor !== true) root.setSource(modelData.id, { tor: true })
                                    else { root.historyAskedFor = ""; root.torOffAskedFor = modelData.id }
                                }
                            }
                            LogosButton {
                                objectName: "clearSuspect_" + modelData.id
                                visible: modelData.suspect === true
                                text: "Clear"
                                enabled: root.ready
                                onClicked: root.networkCall(backend.clearSuspect(modelData.id), "sources")
                            }
                            LogosButton {
                                objectName: "removeSource_" + modelData.id
                                visible: !root.networkLocked && sourceRow.server
                                text: "Remove"
                                enabled: root.ready
                                onClicked: root.networkCall(backend.removeSource(modelData.id), "sources")
                            }
                        }
                        LogosNotice {
                            objectName: "historyConfirm_" + modelData.id
                            Layout.fillWidth: true
                            severity: LogosNotice.Warning
                            shown: root.historyAskedFor === modelData.id && modelData.history !== true && !root.networkLocked
                            title: "Turn on History for " + (modelData.label || modelData.id) + "?"
                            message: shown ? root.historyOnText(modelData) : ""
                            actions: [
                                LogosButton { objectName: "confirmHistory_" + modelData.id; text: "Turn on History"
                                              onClicked: { root.historyAskedFor = ""; root.setSource(modelData.id, { history: true }) } },
                                LogosButton { objectName: "keepHistoryOff_" + modelData.id; text: "Keep it off"
                                              onClicked: root.historyAskedFor = "" }
                            ]
                        }
                        LogosNotice {
                            objectName: "torOffConfirm_" + modelData.id
                            Layout.fillWidth: true
                            severity: LogosNotice.Warning
                            shown: root.torOffAskedFor === modelData.id && modelData.tor === true && !root.networkLocked
                            title: "Reach " + (modelData.label || modelData.id) + " without Tor?"
                            message: shown ? root.torOffText(modelData) : ""
                            actions: [
                                LogosButton { objectName: "skipTor_" + modelData.id; text: "Reach it without Tor"
                                              onClicked: { root.torOffAskedFor = ""; root.setSource(modelData.id, { tor: false }) } },
                                LogosButton { objectName: "keepTor_" + modelData.id; text: "Keep Tor"
                                              onClicked: root.torOffAskedFor = "" }
                            ]
                        }
                    }
                }
            }
            // Below the list, so the rows do not move when they appear.
            LogosNotice {
                objectName: "noChainNotice"
                Layout.fillWidth: true
                severity: LogosNotice.Warning
                shown: root.sourcesConfigured && root.chainSources.length === 0
                message: "Nothing in use defines the chain. Switch on Kyoto, or an Electrum server."
            }
            LogosNotice {
                objectName: "oneOperatorNotice"
                Layout.fillWidth: true
                shown: root.sourcesConfigured && root.serversDecideChain && root.chainOperators.length === 1
                message: shown ? "Kyoto is off, so the Electrum servers in use decide the chain, and they are all "
                                 + root.chainOperators[0] + "'s: nothing checks them. Switch on Kyoto, or a server from another operator." : ""
            }
            LogosNotice {
                objectName: "withoutTorNotice"
                Layout.fillWidth: true
                severity: LogosNotice.Warning
                shown: root.withoutTor.length > 0
                title: "Reached without Tor"
                message: shown ? root.withoutTor.map(function (d) { return d.id }).join(", ")
                                 + (root.withoutTor.length === 1 ? " sees" : " see")
                                 + " this computer's IP address, and can link it to this wallet." : ""
            }

            ColumnLayout {
                objectName: "exposurePane"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.tiny
                LogosText { text: "Who has seen this wallet's addresses"; font.pixelSize: 15 }
                LogosText { objectName: "exposureEmpty"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                            visible: root.exposureServers.length === 0
                            text: root.walletOpen ? "No server has been asked about this wallet's addresses."
                                                  : "The record is kept with each wallet, and shows once one is open." }
                Repeater {
                    model: root.exposureServers
                    LogosText {
                        Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; font.pixelSize: 12
                        text: (modelData.url || modelData.source || "") + " (" + (modelData.operator || "") + ") · "
                              + (modelData.role || "history") + " since " + root.whenOf(modelData.since)
                              + (modelData.last ? ", last " + root.whenOf(modelData.last) : "")
                    }
                }
                LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary; font.pixelSize: 12
                            visible: root.exposes.length > 0
                            text: "With History on, " + root.exposes.map(function (e) { return e.id }).join(", ")
                                  + (root.exposes.length === 1 ? " learns" : " learn") + " every address of a wallet you open." }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10

        RowLayout {
            Layout.fillWidth: true
            LogosText { text: "Bitcoin"; font.pixelSize: 22 }
            Item { Layout.fillWidth: true }
            LogosText { objectName: "syncChip"; textFormat: Text.PlainText; font.pixelSize: 12
                        color: root.syncColor(root.status); text: root.ready ? root.syncChip(root.status) : "Connecting…" }
            // Orange marks a network whose coins are not real.
            LogosBadge {
                objectName: "networkChip"
                text: root.displayedNetwork || "—"
                color: root.displayedNetwork === "mainnet" ? Theme.palette.success : Theme.palette.accentOrange
            }
            LogosButton {
                objectName: "closeWalletButton"
                visible: root.walletOpen
                enabled: root.ready && !root.busy
                text: "Close wallet"
                onClicked: backend.closeWallet()
            }
        }

        LogosText {
            objectName: "statusLine"
            textFormat: Text.PlainText
            color: Theme.palette.textSecondary
            text: !root.ready ? "" : root.walletOpen
                  ? "Open: " + (root.status.label || root.familyLabel(root.status.family)) + " · " + (root.status.network || "")
                  : (root.opening ? "Opening a wallet on " + (root.displayedNetwork || "this network") : "No wallet open")
        }

        LogosNotice {
            objectName: "errorNotice"
            Layout.fillWidth: true
            severity: LogosNotice.Error
            closable: true
            shown: false
            message: root.ready ? backend.lastError : ""
            onMessageChanged: shown = message.length > 0
            Component.onCompleted: shown = message.length > 0
        }
        LogosNotice {
            objectName: "unavailableNotice"
            Layout.fillWidth: true
            severity: LogosNotice.Warning
            shown: root.status.unavailable === true
            title: "The wallet backend is not answering"
            message: shown ? String(root.status.error || "") : ""
        }
        LogosNotice {
            objectName: "alertBanner"
            Layout.fillWidth: true
            severity: LogosNotice.Warning
            shown: root.walletOpen && root.alerts.length > 0
            title: shown ? root.alertTitle(root.alerts[0]) : ""
            message: shown ? (root.alerts[0].source || "") + ": " + (root.alerts[0].detail || "")
                             + (root.alerts.length > 1 ? "\n" + (root.alerts.length - 1) + " earlier alert" + (root.alerts.length > 2 ? "s" : "") : "") : ""
            actions: [
                LogosButton { objectName: "alertSourcesButton"; text: "Sources"; onClicked: root.selectTab(4) },
                LogosButton { objectName: "dismissAlertsButton"; text: "Dismiss"; onClicked: backend.dismissAlerts() }
            ]
        }
        // Above the tabs: it stays until the payment is settled or forgotten.
        LogosNotice {
            objectName: "sendUnknownBanner"
            Layout.fillWidth: true
            severity: LogosNotice.Warning
            shown: root.sendOutcome(root.send) === "unknown"
            title: "A payment's outcome is unknown"
            message: "It may have left. Rebroadcast it, or speed it up with a higher fee; do not pay again from other coins while it could still confirm."
            actions: [ LogosButton { objectName: "showUnknownButton"; text: "Show"; onClicked: reviewSheet.open() } ]
        }
        LogosNotice {
            objectName: "sendWaitingBanner"
            Layout.fillWidth: true
            severity: LogosNotice.Info
            shown: root.walletOpen && root.sendOpen && root.sendOutcome(root.send) !== "unknown" && !reviewSheet.visible
            title: root.sendLive ? (root.ownSend ? "A send is waiting for the signer app" : "A send another app asked for is waiting")
                                 : "A send has settled"
            message: root.sendHeadline(root.send)
            actions: [ LogosButton { objectName: "showReviewButton"; text: "Show"; onClicked: reviewSheet.open() } ]
        }

        // ================= NO WALLET OPEN =================
        ColumnLayout {
            objectName: "openPage"
            visible: root.ready && !root.walletOpen
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                LogosText { text: "Open a wallet"; font.pixelSize: 22 }
                Item { Layout.fillWidth: true }
                LogosText { text: "Network"; color: Theme.palette.textSecondary }
                LogosComboBox {
                    objectName: "networkBox"
                    enabled: root.ready && !root.networkLocked
                    model: root.networks.networks || []
                    currentIndex: Math.max(0, (root.networks.networks || []).indexOf(root.activeNetwork))
                    onActivated: root.selectNetwork(currentText)
                }
            }

            // While the person decides in the keys app.
            LogosFrame {
                objectName: "keysWaitPanel"
                visible: root.opening
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    RowLayout {
                        LogosSpinner { Layout.preferredWidth: 20; Layout.preferredHeight: 20; running: root.opening }
                        LogosText { objectName: "keysWaitTitle"; font.pixelSize: 16; textFormat: Text.PlainText
                                    text: root.pendingKind === "cancel" ? "Withdrawing the request…"
                                          : root.walletState === "opening" ? "Opening the wallet…"
                                          : (root.awaitingKeys ? "Waiting for the keys app" : "Asking the keys app…") }
                    }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                text: "Pick a wallet in the keys app, or create or restore one there, and approve opening it for "
                                      + "this app. The keys app keeps the recovery phrase and the password; this app never asks for them." }
                    LogosText { objectName: "keysNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                textFormat: Text.PlainText; color: Theme.palette.warning; text: root.keysNote }
                    RowLayout {
                        spacing: Theme.spacing.small
                        LogosButton { objectName: "askKeysAgainButton"; text: "Ask again"; visible: root.openHandle !== ""
                                      enabled: root.ready; onClicked: root.askKeys() }
                        LogosButton { objectName: "cancelOpenButton"; text: root.pendingKind === "cancel" ? "Cancelling…" : "Cancel"
                                      enabled: root.ready && root.pendingKind !== "cancel"; onClicked: backend.closeWallet() }
                    }
                }
            }

            ColumnLayout {
                objectName: "openForm"
                visible: !root.opening
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                            text: "The keys app opens: pick a wallet there, or create or restore one. Creating and restoring "
                                  + "happen there, never here. Choose the kind of address it uses." }
                LogosRadioButton {
                    objectName: "familySegwit"
                    checkable: false
                    checked: root.family === "bitcoin"
                    text: "Native segwit: addresses start " + root.hrp + "1q, and every wallet and exchange can pay them"
                    onClicked: root.family = "bitcoin"
                }
                LogosRadioButton {
                    objectName: "familyTaproot"
                    checkable: false
                    checked: root.family === "bitcoin_taproot"
                    text: "Taproot: addresses start " + root.hrp + "1p; a little cheaper to spend, newer"
                    onClicked: root.family = "bitcoin_taproot"
                }
                RowLayout {
                    Layout.fillWidth: true
                    LogosTextField { id: walletLabel; objectName: "walletLabelField"; Layout.preferredWidth: 280
                                     placeholderText: "Name for this wallet (optional)" }
                    LogosButton {
                        objectName: "openWalletButton"
                        text: "Open a wallet"
                        variant: LogosButton.Variant.Primary
                        enabled: root.ready && !root.busy && root.statusRead && root.status.unavailable !== true
                        onClicked: root.openWallet({ family: root.family })
                    }
                    Item { Layout.fillWidth: true }
                    LogosButton { objectName: "networkSettingsButton"; text: "Sources and privacy"; enabled: root.ready; onClicked: networkSheet.open() }
                    LogosButton { objectName: "refreshButton"; text: "Refresh"; enabled: root.ready; onClicked: backend.clearAndRefresh() }
                }

                LogosText { text: "Opened before"; font.pixelSize: 15; Layout.topMargin: Theme.spacing.small
                            visible: root.walletsOnNetwork.length > 0 }
                Repeater {
                    model: root.walletsOnNetwork
                    LogosFrame {
                        Layout.fillWidth: true
                        contentItem: RowLayout {
                            spacing: Theme.spacing.small
                            LogosText { textFormat: Text.PlainText; text: modelData.label || root.familyLabel(modelData.family) }
                            LogosBadge { text: root.familyLabel(modelData.family); color: Theme.palette.textSecondary }
                            LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; textFormat: Text.PlainText
                                        color: Theme.palette.textTertiary; font.pixelSize: 12
                                        text: root.shortId(modelData.group) + (modelData.lastOpened ? " · last opened " + root.whenOf(modelData.lastOpened) : "") }
                            LogosButton {
                                objectName: "reopen_" + modelData.group
                                text: "Open"
                                enabled: root.ready && !root.busy
                                onClicked: root.openWallet({ group: modelData.group })
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
            // Holds the page at the top while the form is hidden.
            Item { visible: root.opening; Layout.fillHeight: true }
        }

        // ================= A WALLET IS OPEN =================
        LogosTabBar {
            id: tabs
            objectName: "walletTabs"
            visible: root.walletOpen
            Layout.fillWidth: true
            // Not bound to root.page: a click assigns currentIndex and would break the binding.
            onCurrentIndexChanged: root.selectTab(currentIndex)
            LogosTabButton { text: "Home" }
            LogosTabButton { text: "Send" }
            LogosTabButton { text: "Receive" }
            LogosTabButton { text: "Activity" }
            LogosTabButton { text: "Settings" }
        }

        StackLayout {
            visible: root.walletOpen
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.page

            // Home
            ScrollView {
                id: homeScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: homeScroll.availableWidth
                    spacing: Theme.spacing.medium

                    LogosStatCard {
                        objectName: "confirmedCard"
                        Layout.fillWidth: true
                        label: "Confirmed balance"
                        value: root.balancesRead ? root.btcOf(root.balances.confirmed) + " BTC" : "— BTC"
                        caption: !root.balancesRead ? "Read once the wallet has synced"
                                 : "Confirmed on the wallet's own chain. Send spends only this."
                        valueFontSizeMode: Text.HorizontalFit
                        labelTrailing: [
                            LogosInfoButton {
                                title: "Confirmed"
                                text: "Payments in blocks of the chain the wallet checked itself. What a server reports and the "
                                      + "wallet has not checked shows apart, below, and is not spent."
                            }
                        ]
                    }

                    BalanceRow {
                        objectName: "waitingRow"
                        visible: root.balancesRead && Number(root.balances.waiting || 0) > 0
                        title: "Waiting for the wallet's chain"
                        amount: root.btcOf(root.balances.waiting) + " BTC"
                        note: "A server reports these payments confirmed, in blocks the wallet's chain has not reached. "
                              + "They count once it does."
                    }
                    BalanceRow {
                        objectName: "pendingRow"
                        visible: root.balancesRead && Number(root.balances.pending || 0) > 0
                        title: "Pending"
                        amount: root.btcOf(root.balances.pending) + " BTC"
                        note: "In a server's mempool, not in a block yet, and nothing here can check it."
                              + root.pendingRows.map(function (r) {
                                    return "\n+" + root.btcOf(r.amountSat) + " BTC" + (r.reportedBy ? ", reported by " + r.reportedBy : "")
                                }).join("")
                    }
                    BalanceRow {
                        objectName: "sentRow"
                        visible: root.unconfirmedSends.length > 0 || (root.balancesRead && Number(root.balances.sent || 0) > 0)
                        title: "Sent, not confirmed yet"
                        amount: root.balancesRead && Number(root.balances.sent || 0) > 0 ? root.btcOf(root.balances.sent) + " BTC returning" : ""
                        note: "Your own transactions, broadcast. Their coins stay reserved until they confirm; any change "
                              + "comes back then. Speed up replaces one with a higher fee."
                        extra: Repeater {
                            model: root.unconfirmedSends
                            RowLayout {
                                spacing: Theme.spacing.small
                                LogosText { objectName: "unconfirmedSend_" + modelData.txid; textFormat: Text.PlainText; font.pixelSize: 12
                                            text: root.intentLine(modelData) }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11; color: Theme.palette.textTertiary
                                            text: root.shortId(modelData.txid) }
                                LogosButton { objectName: "homeSpeedUp_" + modelData.txid; text: "Speed up"
                                              enabled: root.ready && !root.sendLive
                                              onClicked: speedUpSheet.ask(modelData) }
                            }
                        }
                    }
                    BalanceRow {
                        objectName: "immatureRow"
                        visible: root.balancesRead && Number(root.balances.immature || 0) > 0
                        title: "Mined, not spendable yet"
                        amount: root.btcOf(root.balances.immature) + " BTC"
                        note: "Newly mined coins become spendable after 100 confirmations."
                    }
                    BalanceRow {
                        objectName: "tooSmallRow"
                        visible: root.balancesRead && Number(root.tooSmall.count || 0) > 0
                        title: "Too small to spend"
                        amount: (root.tooSmall.count || 0) + (Number(root.tooSmall.count) === 1 ? " coin, " : " coins, ")
                                + root.btcOf(root.tooSmall.sat) + " BTC"
                        note: "Each is worth less than it costs to spend at today's fee rate"
                              + (root.feesKnown ? " (" + root.feeRates.normal + " sat/vB)" : "")
                              + ". They stay in your balance, and sends leave them out until fees come down."
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.tiny
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { objectName: "syncLine"; textFormat: Text.PlainText; color: root.syncColor(root.status)
                                        text: root.syncLabel(root.status) }
                            Item { Layout.fillWidth: true }
                            LogosBadge { objectName: "healthBadge"; visible: root.overall !== ""
                                         text: root.overallLabel(root.overall); color: root.overallColor(root.overall) }
                        }
                        LogosProgressBar {
                            objectName: "syncProgress"
                            Layout.fillWidth: true
                            visible: root.syncState(root.status) === "syncing"
                            indeterminate: !root.isNum(root.status.syncPercent)
                            value: root.isNum(root.status.syncPercent) ? Number(root.status.syncPercent) / 100 : 0
                        }
                        LogosText { objectName: "authorityLine"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                    text: root.authorityLine(root.status) }
                        LogosText { visible: !!root.status.historyServer; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                    text: "History from " + (root.status.historyServer || "") }
                        LogosText { visible: !!root.status.lastError; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.warning
                                    text: "Last sync error: " + (root.status.lastError || "") }
                    }
                }
            }

            // Send
            ScrollView {
                id: sendScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: sendScroll.availableWidth
                    spacing: Theme.spacing.small

                    LogosText {
                        objectName: "sendAvailable"
                        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        text: "Send spends confirmed coins only" + (root.balancesRead ? ": " + root.btcOf(root.balances.confirmed) + " BTC." : ".")
                    }
                    LogosText { text: "Recipient"; color: Theme.palette.textSecondary }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosTextField {
                            id: sendTo
                            objectName: "sendRecipientField"
                            Layout.fillWidth: true
                            enabled: !root.sendLive
                            placeholderText: "A Bitcoin address, or a bitcoin: payment request"
                            onTextChanged: recipientCheckTimer.restart()
                        }
                        // Checked once typing pauses, not on every keystroke.
                        Timer { id: recipientCheckTimer; interval: 300; onTriggered: root.checkRecipient() }
                        LogosBadge {
                            objectName: "recipientBadge"
                            visible: root.recipientChecked && !root.recipientCheck.failed
                            text: root.recipientValid ? root.typeLabel(root.recipientCheck.type) || "address" : "not valid"
                            color: root.recipientValid ? Theme.palette.success : Theme.palette.error
                        }
                    }
                    LogosText { objectName: "recipientNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                textFormat: Text.PlainText; color: Theme.palette.error
                                text: root.recipientChecked ? root.recipientLine(root.recipientCheck) : "" }
                    LogosText { visible: root.recipientValid && root.isNum(root.recipientCheck.amountSat)
                                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                text: "The payment request asks for " + root.btcOf(root.recipientCheck.amountSat) + " BTC." }

                    LogosText { text: "Amount"; color: Theme.palette.textSecondary }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosTextField {
                            id: sendAmount
                            objectName: "sendAmountField"
                            Layout.fillWidth: true
                            enabled: !root.sendLive && !root.sendMax
                            placeholderText: root.amountUnit === "sat" ? "0" : "0.0"
                            validator: RegularExpressionValidator {
                                regularExpression: root.amountUnit === "sat" ? /^[0-9]{0,16}$/ : /^[0-9]{0,8}\.?[0-9]{0,8}$/
                            }
                        }
                        LogosComboBox {
                            id: unitBox
                            objectName: "amountUnitBox"
                            model: ["BTC", "sats"]
                            currentIndex: root.amountUnit === "sat" ? 1 : 0
                            enabled: !root.sendLive && !root.sendMax
                            onActivated: {
                                var sat = root.amountSat
                                root.amountUnit = currentIndex === 1 ? "sat" : "btc"
                                // The amount keeps its value across units: exact, no rounding.
                                sendAmount.text = sat === "" ? "" : (root.amountUnit === "sat" ? sat : root.btcOf(sat))
                            }
                        }
                        LogosSwitch {
                            objectName: "sendMaxSwitch"
                            text: "Send max"
                            checkable: false
                            checked: root.sendMax
                            enabled: !root.sendLive
                            onClicked: root.sendMax = !root.sendMax
                        }
                    }
                    LogosText {
                        objectName: "amountNote"
                        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        color: Theme.palette.textTertiary
                        text: root.sendMax ? "Everything spendable goes, less the fee: coins too small to spend stay behind."
                              : root.amountSat === "" ? (sendAmount.text.trim() === "" ? "" : "Enter an amount above zero, with at most 8 decimals in BTC.")
                              : (root.amountUnit === "sat" ? "= " + root.btcOf(root.amountSat) + " BTC" : "= " + root.satsText(root.amountSat))
                    }

                    LogosText { text: "Fee"; color: Theme.palette.textSecondary }
                    LogosText { visible: !root.feesKnown; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                                text: "No fee estimate from the sources yet: give a rate of your own." }
                    RowLayout {
                        spacing: Theme.spacing.medium
                        LogosRadioButton { objectName: "feeFast"; visible: root.feesKnown; checkable: false; checked: root.feeChoice === "fast"
                                           text: "Fast · " + root.feeRates.fast + " sat/vB"; onClicked: root.feeChoice = "fast" }
                        LogosRadioButton { objectName: "feeNormal"; visible: root.feesKnown; checkable: false; checked: root.feeChoice === "normal"
                                           text: "Normal · " + root.feeRates.normal + " sat/vB"; onClicked: root.feeChoice = "normal" }
                        LogosRadioButton { objectName: "feeSlow"; visible: root.feesKnown; checkable: false; checked: root.feeChoice === "slow"
                                           text: "Slow · " + root.feeRates.slow + " sat/vB"; onClicked: root.feeChoice = "slow" }
                        LogosRadioButton { objectName: "feeCustomChoice"; checkable: false; checked: root.feeChoice === "custom" || !root.feesKnown
                                           text: "Custom"; onClicked: root.feeChoice = "custom" }
                        LogosTextField {
                            id: feeCustom
                            objectName: "feeCustomField"
                            visible: root.feeChoice === "custom" || !root.feesKnown
                            Layout.preferredWidth: 110
                            placeholderText: "sat/vB"
                            validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,6}(\.[0-9]{0,2})?$/ }
                        }
                    }
                    // Without an estimate only a rate of one's own can go.
                    Binding { target: root; property: "feeChoice"; value: "custom"; when: root.walletOpen && !root.feesKnown }

                    LogosNotice {
                        objectName: "sendErrorNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Error
                        shown: message.length > 0 && !reviewSheet.visible
                        message: root.ready ? backend.sendError : ""
                    }
                    LogosText { visible: root.sendOutcome(root.send) === "unknown"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.warning
                                text: "A payment's outcome is unknown. Settle it first: rebroadcast it, speed it up, or forget it." }
                    LogosButton {
                        objectName: "reviewButton"
                        text: "Review"
                        variant: LogosButton.Variant.Primary
                        enabled: root.canReview
                        onClicked: root.review()
                    }
                }
            }

            // Receive
            ScrollView {
                id: receiveScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: receiveScroll.availableWidth
                    spacing: Theme.spacing.small
                    LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                text: "A new address for each payment you ask for: every one pays into this wallet, and using each "
                                      + "once keeps your payments apart on-chain." }
                    QrMatrix { objectName: "receiveQr"; qr: root.ready ? root.parseQr(backend.receiveQrJson) : null }
                    LogosCopyableText {
                        objectName: "receiveAddress"
                        Layout.fillWidth: true
                        text: root.receive.address || "—"
                        copyText: root.receive.address || ""
                        showCopyButton: !!root.receive.address
                        onCopied: root.notify("Address copied", "")
                    }
                    LogosText { visible: root.isNum(root.receive.index); color: Theme.palette.textTertiary; font.pixelSize: 12
                                textFormat: Text.PlainText; text: "Receive address #" + root.receive.index }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosText { text: "Ask for an amount (BTC, optional)"; color: Theme.palette.textSecondary }
                        LogosTextField {
                            id: receiveAmount
                            objectName: "receiveAmountField"
                            Layout.preferredWidth: 160
                            placeholderText: "0.0"
                            validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,8}\.?[0-9]{0,8}$/ }
                            onTextChanged: receiveAmountTimer.restart()
                        }
                        Timer { id: receiveAmountTimer; interval: 400; onTriggered: if (root.ready) backend.setReceiveAmount(receiveAmount.text.trim()) }
                        Item { Layout.fillWidth: true }
                    }
                    LogosCopyableText {
                        objectName: "receiveUri"
                        Layout.fillWidth: true
                        visible: !!root.receive.uri
                        text: root.receive.uri || ""
                        copyText: root.receive.uri || ""
                        onCopied: root.notify("Payment request copied", "")
                    }
                    LogosButton {
                        objectName: "newAddressButton"
                        text: "New address"
                        enabled: root.ready && root.walletOpen
                        onClicked: backend.newAddress()
                    }
                }
            }

            // Activity: one page of history, newest first; a row expands into its detail.
            ColumnLayout {
                spacing: Theme.spacing.small
                RowLayout {
                    Layout.fillWidth: true
                    LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                text: root.historyRead ? "Page " + (root.historyPage + 1) : "" }
                    Item { Layout.fillWidth: true }
                    LogosButton { objectName: "historyNewerButton"; text: "Newer"; enabled: root.historyPage > 0
                                  onClicked: backend.showHistoryPage(root.historyPage - 1) }
                    LogosButton { objectName: "historyOlderButton"; text: "Older"
                                  enabled: root.historyRows.length > 0 && root.historyRows.length >= (root.historyData.pageSize || 50)
                                  onClicked: backend.showHistoryPage(root.historyPage + 1) }
                    LogosButton { text: "Refresh"; enabled: root.ready; onClicked: backend.refreshHistory() }
                }
                LogosText { objectName: "historyEmpty"; visible: root.historyRead && root.historyRows.length === 0
                            color: Theme.palette.textSecondary
                            text: root.historyPage === 0 ? "No transactions yet." : "No older transactions." }
                LogosText { visible: !root.historyRead; text: "—" }
                ListView {
                    objectName: "historyList"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.historyRows
                    delegate: Rectangle {
                        id: txRow
                        width: ListView.view.width
                        implicitHeight: txCol.implicitHeight + 12
                        radius: 4
                        readonly property bool open: root.openTx === modelData.txid
                        color: open ? Theme.palette.surface : "transparent"
                        ColumnLayout {
                            id: txCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 6
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.small
                                LogosText { objectName: "historyIntent_" + modelData.txid; textFormat: Text.PlainText
                                            text: root.intentLine(modelData) }
                                LogosText { objectName: "historyState_" + modelData.txid; textFormat: Text.PlainText
                                            color: root.rowStateColor(modelData); text: root.rowState(modelData) }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 11
                                            text: root.whenOf(modelData.time) }
                                Item { Layout.fillWidth: true }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 10
                                            text: root.shortId(modelData.txid) }
                                LogosButton { objectName: "speedUp_" + modelData.txid; visible: root.canSpeedUp(modelData)
                                              text: "Speed up"; enabled: root.ready && !root.sendLive
                                              onClicked: speedUpSheet.ask(modelData) }
                                LogosButton { objectName: "details_" + modelData.txid; text: txRow.open ? "Hide" : "Details"
                                              onClicked: root.openTx = (root.openTx === modelData.txid ? "" : modelData.txid) }
                            }
                            GridLayout {
                                visible: txRow.open
                                columns: 2; columnSpacing: 14; rowSpacing: 3
                                Layout.fillWidth: true
                                LogosText { text: "Status"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: root.isNum(modelData.height) ? root.rowState(modelData) + " · block " + root.group(modelData.height)
                                                                                : root.rowState(modelData) }
                                LogosText { visible: modelData.intent !== "combine"; text: "Amount"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: modelData.intent !== "combine"; textFormat: Text.PlainText; font.pixelSize: 11
                                            text: root.btcOf(modelData.amountSat) + " BTC (" + root.satsText(modelData.amountSat) + ")" }
                                LogosText { text: "Fee"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: root.isNum(modelData.feeSat) ? root.satsText(modelData.feeSat) : "—" }
                                LogosText { visible: (modelData.counterparties || []).length > 0; color: Theme.palette.textTertiary; font.pixelSize: 11
                                            text: modelData.intent === "self" ? "To your addresses" : "Paid to" }
                                LogosText { objectName: "historyPaid_" + modelData.txid
                                            visible: (modelData.counterparties || []).length > 0; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                                            text: (modelData.counterparties || []).join("\n") }
                                LogosText { visible: !!modelData.replaces; text: "Replaces"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: !!modelData.replaces; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; text: modelData.replaces || "" }
                                LogosText { visible: !!modelData.replacedBy; text: "Replaced by"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: !!modelData.replacedBy; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; text: modelData.replacedBy || "" }
                                LogosText { visible: !!modelData.reportedBy; text: "Reported by"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: !!modelData.reportedBy; textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.reportedBy || "" }
                                LogosText { text: "Transaction ID"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosCopyableText { objectName: "historyTxid_" + modelData.txid; Layout.fillWidth: true
                                                    text: modelData.txid; copyText: modelData.txid
                                                    onCopied: root.notify("Transaction ID copied", "") }
                            }
                        }
                    }
                }
            }

            // Settings
            ScrollView {
                id: settingsScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: Theme.spacing.small

                    LogosText { text: "Wallet"; font.pixelSize: 16 }
                    GridLayout {
                        columns: 2; columnSpacing: 14; rowSpacing: 3
                        Layout.fillWidth: true
                        LogosText { text: "Name"; color: Theme.palette.textSecondary }
                        LogosText { textFormat: Text.PlainText; text: root.status.label || "—" }
                        LogosText { text: "Addresses"; color: Theme.palette.textSecondary }
                        LogosText { objectName: "walletFamily"; textFormat: Text.PlainText; text: root.familyLabel(root.status.family) }
                        LogosText { text: "Network"; color: Theme.palette.textSecondary }
                        LogosText { textFormat: Text.PlainText; text: (root.status.network || "—") + " · close the wallet to switch networks" }
                        LogosText { text: "Wallet id"; color: Theme.palette.textSecondary }
                        LogosText { textFormat: Text.PlainText; text: root.shortId(root.status.group) || "—" }
                        LogosText { text: "Scans from"; color: Theme.palette.textSecondary }
                        LogosText { textFormat: Text.PlainText
                                    text: root.isNum(root.status.birthday) ? "block " + root.group(root.status.birthday) : "—" }
                    }
                    LogosNotice {
                        objectName: "needsBirthdayNotice"
                        Layout.fillWidth: true
                        shown: root.status.needsBirthday === true
                        message: "The keys app did not say when this wallet was first used, so it scans from the block where its "
                                 + "kind of address began. Nothing is missed, but the first sync takes longer."
                    }
                    RowLayout {
                        spacing: Theme.spacing.small
                        LogosButton { objectName: "showDescriptorsButton"; text: "Show descriptors…"; enabled: root.ready
                                      onClicked: descriptorsSheet.open() }
                        LogosButton { objectName: "settingsCloseWalletButton"; text: "Close wallet"; enabled: root.ready && !root.busy
                                      onClicked: backend.closeWallet() }
                    }
                    LogosText { objectName: "descriptorsNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                textFormat: Text.PlainText; color: Theme.palette.error; text: root.descriptorsNote }
                    LogosFrame {
                        objectName: "descriptorPanel"
                        visible: root.shownDescriptors !== null
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.small
                            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.warning
                                        text: "Anyone with these descriptors sees every address and payment of this wallet, past and future. They cannot spend." }
                            LogosText { text: "Receive"; color: Theme.palette.textSecondary; font.pixelSize: 12 }
                            LogosSelectableText { objectName: "descriptorExternal"; Layout.fillWidth: true
                                                  wrapMode: TextEdit.WrapAnywhere; text: root.shownDescriptors ? (root.shownDescriptors.external || "") : "" }
                            LogosText { text: "Change"; color: Theme.palette.textSecondary; font.pixelSize: 12 }
                            LogosSelectableText { Layout.fillWidth: true; wrapMode: TextEdit.WrapAnywhere
                                                  text: root.shownDescriptors ? (root.shownDescriptors.internal || "") : "" }
                            RowLayout {
                                LogosButton { objectName: "hideDescriptorsButton"; text: "Hide"; onClicked: root.shownDescriptors = null }
                            }
                        }
                    }

                    LogosText { text: "Sources"; font.pixelSize: 16; Layout.topMargin: Theme.spacing.medium }
                    Loader {
                        Layout.fillWidth: true
                        active: root.walletOpen
                        sourceComponent: networkPane
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ── one balance row on Home: what it is, how much, and what it means ──
    component BalanceRow: LogosFrame {
        id: row
        property string title: ""
        property string amount: ""
        property string note: ""
        property alias extra: extraHolder.data
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Theme.spacing.tiny
            RowLayout {
                Layout.fillWidth: true
                LogosText { text: row.title; font.weight: Theme.typography.weightMedium }
                Item { Layout.fillWidth: true }
                LogosText { objectName: row.objectName + "Amount"; textFormat: Text.PlainText; text: row.amount }
            }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; font.pixelSize: 12
                        color: Theme.palette.textSecondary; text: row.note }
            ColumnLayout { id: extraHolder; Layout.fillWidth: true; spacing: Theme.spacing.tiny }
        }
    }

    // ── QR codes: rectangles from a qrcodegen matrix (the sandbox refuses data: URIs and Canvas) ──
    function parseQr(s) { try { return s ? JSON.parse(s) : null } catch (e) { return null } }
    // A contrast target, not a themed surface: the two literal colours stay literal.
    component QrMatrix: Rectangle {
        id: qrBox
        property var qr: null
        readonly property int quiet: 4
        readonly property int cell: qr ? Math.max(1, Math.floor(264 / (qr.size + quiet * 2))) : 0
        function runs(q) {
            const out = []
            for (let y = 0; y < q.size; y++) {
                let x = 0
                while (x < q.size) {
                    if (q.bits.charAt(y * q.size + x) !== "1") { x++; continue }
                    const start = x
                    while (x < q.size && q.bits.charAt(y * q.size + x) === "1") x++
                    out.push([start, y, x - start])
                }
            }
            return out
        }
        visible: !!qr
        color: "#ffffff"
        Layout.preferredWidth: qr ? cell * (qr.size + quiet * 2) : 0
        Layout.preferredHeight: Layout.preferredWidth
        Repeater {
            model: qrBox.qr ? qrBox.runs(qrBox.qr) : []
            Rectangle {
                required property var modelData
                x: (modelData[0] + qrBox.quiet) * qrBox.cell
                y: (modelData[1] + qrBox.quiet) * qrBox.cell
                width: modelData[2] * qrBox.cell
                height: qrBox.cell
                color: "#000000"
            }
        }
    }

    property string family: "bitcoin"
    // Bech32's human-readable part on the network shown.
    readonly property string hrp: displayedNetwork === "mainnet" ? "bc" : (displayedNetwork === "regtest" ? "bcrt" : "tb")
    function openWallet(params) {
        var label = walletLabel.text.trim()
        if (label !== "" && !params.group) params.label = label
        root.keysNote = ""
        backend.openWallet(JSON.stringify(params))
    }

    LogosToast {
        id: toast
        objectName: "toast"
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.large
        width: Math.min(parent.width - 40, 480)
        severity: LogosNotice.Success
    }

    // ── sheets: outside the layout, so a closed one reserves no space. Titles stay literal. ──

    // The review: first what the form says, then, once requested, what the wallet built while the
    // signer app shows its own description. Only an explicit choice closes it.
    LogosDialog {
        id: reviewSheet
        objectName: "reviewSheet"
        title: root.reviewDraft ? "Review send" : (root.send.kind === "fee_bump" ? "Speed up" : "Send")
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 680)
        closePolicy: Popup.NoAutoClose
        contentItem: ScrollView {
            id: reviewScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(reviewCol.implicitHeight, Math.max(200, root.height - 240))
            ColumnLayout {
                id: reviewCol
                width: reviewScroll.availableWidth
                spacing: Theme.spacing.small

                // ---- before the request ----
                ColumnLayout {
                    objectName: "reviewDraftPane"
                    visible: root.reviewDraft && !!root.draft
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    GridLayout {
                        columns: 2; columnSpacing: 14; rowSpacing: 4
                        Layout.fillWidth: true
                        LogosText { text: "To"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "draftAddress"; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                    text: root.draft ? root.draft.address + (root.draft.type ? " (" + root.typeLabel(root.draft.type) + ")" : "") : "" }
                        LogosText { text: "Amount"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "draftAmount"; textFormat: Text.PlainText; font.weight: Font.Bold
                                    text: !root.draft ? "" : root.draft.sendMax ? "Everything spendable, less the fee"
                                          : root.btcOf(root.draft.amountSat) + " BTC (" + root.satsText(root.draft.amountSat) + ")" }
                        LogosText { text: "Fee"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "draftFee"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                    text: !root.draft ? "" : root.draft.rate + " sat/vB, about "
                                          + root.satsText(Math.ceil(root.draft.rate * root.estimateVsize(root.status.family, root.draft.type, root.draft.sendMax)))
                                          + " for a payment from one coin" }
                        LogosText { text: "Change"; color: Theme.palette.textTertiary }
                        LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                    text: root.draft && root.draft.sendMax ? "none" : "what the spent coins hold beyond this returns to this wallet" }
                    }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                text: "Approve in Signer builds the transaction from confirmed coins, shows its exact fee, change and any "
                                      + "warning here, and asks the signer app. You approve or reject it there, on its own description; "
                                      + "it must be acknowledged within 60 s." }
                }

                // ---- once requested ----
                LogosStageLane {
                    objectName: "sendStageLane"
                    visible: !root.reviewDraft && root.sendOpen
                    Layout.fillWidth: true
                    currentIndex: root.sendStage(root.send)
                    busy: root.sendLive
                    failed: ["failed", "cancelled", "unknown"].indexOf(root.sendState) >= 0
                    stages: [
                        LogosStage { label: "Build"; busyLabel: "Building…" },
                        LogosStage { label: "Approve in Signer"; busyLabel: "Waiting for the signer…" },
                        LogosStage { label: "Broadcast"; busyLabel: "Broadcasting…" },
                        LogosStage { label: "Sent" }
                    ]
                }
                LogosText {
                    objectName: "sendHeadline"
                    visible: !root.reviewDraft && root.sendOpen
                    Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    font.pixelSize: 16
                    color: ["failed", "cancelled"].indexOf(root.sendState) >= 0 ? Theme.palette.error
                           : root.sendOutcome(root.send) === "unknown" ? Theme.palette.warning : Theme.palette.text
                    text: root.sendHeadline(root.send)
                }
                LogosText { objectName: "sendDetail"; visible: !root.reviewDraft && text !== ""
                            && !(root.forgetNote !== "" && root.sendOutcome(root.send) === "forgotten"); Layout.fillWidth: true
                            wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Theme.palette.textSecondary
                            text: root.sendOpen ? root.sendDetail(root.send) : "" }
                LogosText { visible: !root.reviewDraft && root.sendOpen && !root.ownSend; Layout.fillWidth: true; wrapMode: Text.Wrap
                            textFormat: Text.PlainText; color: Theme.palette.warning
                            text: "Requested by " + (root.send.requester || "") + ". Approve or reject it in the signer app." }
                LogosText { objectName: "signerNote"; visible: !root.reviewDraft && text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                            textFormat: Text.PlainText; color: Theme.palette.warning
                            text: root.sendState === "awaiting_approval" ? root.signerNote : "" }

                ColumnLayout {
                    objectName: "summaryPane"
                    visible: !root.reviewDraft && !!root.summary
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    Repeater {
                        model: root.summary ? (root.summary.recipients || []) : []
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                        font.pixelSize: 12; text: modelData.address || "" }
                            LogosText { objectName: "summaryRecipientAmount"; textFormat: Text.PlainText; font.weight: Font.Bold
                                        text: root.btcOf(modelData.amountSat) + " BTC" }
                        }
                    }
                    GridLayout {
                        columns: 2; columnSpacing: 14; rowSpacing: 3
                        Layout.fillWidth: true
                        LogosText { text: "Fee"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "summaryFee"; textFormat: Text.PlainText
                                    text: root.summary ? root.satsText(root.summary.feeSat)
                                                         + (root.isNum(root.summary.feeRate) ? " · " + root.summary.feeRate + " sat/vB" : "")
                                                         + (root.isNum(root.summary.vsize) ? " · " + root.summary.vsize + " vB" : "") : "" }
                        LogosText { text: "Change"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "summaryChange"; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                    text: !root.summary ? "" : (root.summary.change || []).length === 0 ? "none"
                                          : (root.summary.change || []).map(function (c) { return root.btcOf(c.amountSat) + " BTC to " + c.address }).join("\n") }
                        LogosText { text: "Spends"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText
                                    text: root.summary ? (root.summary.inputs || 0) + ((root.summary.inputs || 0) === 1 ? " coin, " : " coins, ")
                                                         + root.btcOf(root.summary.inputSat) + " BTC" : "" }
                        LogosText { text: "Leaves the wallet"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "summaryTotal"; textFormat: Text.PlainText
                                    text: root.summary ? root.btcOf(root.summary.totalSat) + " BTC, fee included" : "" }
                        LogosText { visible: !!root.summary && !!root.summary.replaces; text: "Replaces"; color: Theme.palette.textTertiary }
                        LogosText { visible: !!root.summary && !!root.summary.replaces; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                                    textFormat: Text.PlainText; text: root.summary ? (root.summary.replaces || "") : "" }
                    }
                    Repeater {
                        model: root.summary && Array.isArray(root.summary.warnings) ? root.summary.warnings : []
                        LogosNotice {
                            objectName: modelData.kind === "change_too_small" ? "changeTooSmallNotice" : "summaryWarning"
                            Layout.fillWidth: true
                            severity: LogosNotice.Warning
                            title: modelData.kind === "change_too_small" ? "The change is too small to spend" : "Warning"
                            message: modelData.kind === "change_too_small"
                                     ? "Its " + root.satsText(modelData.amountSat) + " would cost about " + root.satsText(modelData.costToSpendSat)
                                       + " to spend at this fee rate. Reject it in the signer app and change the amount to avoid it."
                                     : String(modelData.message || modelData.kind || "")
                        }
                    }
                }
                ColumnLayout {
                    visible: !root.reviewDraft && !!root.send.txid && (root.sendState === "sent" || root.sendState === "unknown" || root.sendState === "committing")
                    Layout.fillWidth: true
                    spacing: 2
                    LogosText { text: "Transaction ID"; color: Theme.palette.textTertiary; font.pixelSize: 12 }
                    LogosCopyableText { objectName: "sendTxid"; Layout.fillWidth: true; text: root.send.txid || ""; copyText: root.send.txid || ""
                                        onCopied: root.notify("Transaction ID copied", "") }
                    LogosText { visible: !!root.send.via; textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 11
                                text: "Broadcast through " + (root.send.via || "") + (root.send.broadcast === "seen" ? ", and seen by the network" : "") }
                }
                LogosText { objectName: "forgetNote"; visible: text !== "" && root.sendOutcome(root.send) === "forgotten"
                            Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                            color: Theme.palette.textSecondary; text: root.forgetNote }
                LogosText { objectName: "sendNote"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                            textFormat: Text.PlainText; color: Theme.palette.error; text: root.sendNote }
                LogosNotice {
                    objectName: "reviewError"
                    Layout.fillWidth: true
                    severity: LogosNotice.Error
                    shown: message.length > 0
                    message: root.ready ? backend.sendError : ""
                }
            }
        }
        leftActions: [
            LogosButton { objectName: "backButton"; text: "Back"; visible: root.reviewDraft
                          onClicked: { root.reviewDraft = false; reviewSheet.close() } },
            LogosButton { objectName: "cancelSendButton"; text: "Cancel send"
                          visible: !root.reviewDraft && (root.sendState === "preparing" || root.sendState === "awaiting_approval") && !root.send.cancelling
                          onClicked: backend.cancelSend() },
            LogosButton { objectName: "hideReviewButton"; text: "Hide"; visible: !root.reviewDraft && (root.sendLive || root.sendOutcome(root.send) === "unknown")
                          onClicked: reviewSheet.close() }
        ]
        rightActions: [
            LogosButton { objectName: "approveInSignerButton"; text: "Approve in Signer"; variant: LogosButton.Variant.Primary
                          visible: root.reviewDraft; enabled: root.ready && root.walletOpen && !root.sendLive
                          onClicked: root.approveInSigner() },
            LogosButton { objectName: "askSignerButton"; text: root.ownSend ? "Open the signer again" : "Open the signer app"
                          visible: !root.reviewDraft && root.sendState === "awaiting_approval" && !root.send.cancelling
                          onClicked: root.askSigner() },
            LogosButton { objectName: "askAgainButton"; variant: LogosButton.Variant.Primary
                          text: root.sendOutcome(root.send) === "expired" ? "Ask again" : "Try again"
                          visible: !root.reviewDraft && root.canRetry(root.send) && root.ownSend && !!root.lastRequest
                          onClicked: root.askAgain() },
            LogosButton { objectName: "forgetPaymentButton"; text: "Forget this payment…"
                          visible: !root.reviewDraft && root.offers(root.send, "abandon_send") && !!root.send.txid
                          onClicked: { root.forgetTxid = root.send.txid; forgetSheet.open() } },
            LogosButton { objectName: "speedUpUnknownButton"; text: "Speed up…"
                          visible: !root.reviewDraft && root.offers(root.send, "request_fee_bump") && !!root.send.txid
                          onClicked: speedUpSheet.ask({ txid: root.send.txid, feeSat: root.summary ? root.summary.feeSat : "" }) },
            LogosButton { objectName: "rebroadcastButton"; text: "Rebroadcast"; variant: LogosButton.Variant.Primary
                          visible: !root.reviewDraft && root.offers(root.send, "rebroadcast")
                          onClicked: { backend.rebroadcast(); root.notify("Broadcast again", "It shows as sent once a source has seen it.") } },
            LogosButton { objectName: "doneSendButton"; text: "Done"; visible: !root.reviewDraft && root.sendSettled
                          onClicked: root.finishSend() }
        ]
    }

    // Speed up: replace an unconfirmed send with a higher fee (RBF), approved like any send.
    LogosDialog {
        id: speedUpSheet
        objectName: "speedUpSheet"
        title: "Speed up"
        property var row: null
        function ask(r) {
            speedUpSheet.row = r
            speedUpRate.text = String(root.speedUpRate(r))
            speedUpSheet.open()
        }
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        text: speedUpSheet.row ? "Replaces " + root.shortId(speedUpSheet.row.txid)
                                                 + (root.isNum(speedUpSheet.row.feeSat) ? ", whose fee is " + root.satsText(speedUpSheet.row.feeSat) : "")
                                                 + ", with the same payment at a higher fee rate. Whichever confirms first counts; the other never can." : "" }
            RowLayout {
                LogosText { text: "New fee rate"; color: Theme.palette.textSecondary }
                LogosTextField { id: speedUpRate; objectName: "speedUpRateField"; Layout.preferredWidth: 110; placeholderText: "sat/vB"
                                 validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,6}(\.[0-9]{0,2})?$/ } }
                LogosText { visible: root.feesKnown; color: Theme.palette.textTertiary; textFormat: Text.PlainText
                            text: "fast is " + root.feeRates.fast + " sat/vB now" }
            }
        }
        leftActions: [ LogosButton { text: "Cancel"; onClicked: speedUpSheet.close() } ]
        rightActions: [
            LogosButton { objectName: "confirmSpeedUpButton"; text: "Approve in Signer"; variant: LogosButton.Variant.Primary
                          enabled: root.ready && !root.sendLive && !!speedUpSheet.row && Number(speedUpRate.text) > 0
                          onClicked: { root.speedUp(speedUpSheet.row.txid, Number(speedUpRate.text)); speedUpSheet.close() } }
        ]
    }

    LogosWarningDialog {
        id: forgetSheet
        objectName: "forgetSheet"
        title: "Forget this payment?"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        message: "Its coins become spendable again. If the payment did go out, a later send from those coins may fail, "
                 + "or be replaced by this one when it confirms."
        leftActions: [ LogosButton { objectName: "keepWaitingButton"; text: "Keep waiting"; onClicked: forgetSheet.close() } ]
        rightActions: [
            LogosButton { objectName: "confirmForgetButton"; text: "Forget it"
                          onClicked: { forgetSheet.close(); root.forget(root.forgetTxid) } }
        ]
    }

    LogosWarningDialog {
        id: descriptorsSheet
        objectName: "descriptorsSheet"
        title: "Show descriptors?"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        message: "They describe every address of this wallet. Anyone who has them can see all its payments, past and future, "
                 + "and link them to you. They cannot spend. Check that nobody can see your screen."
        leftActions: [ LogosButton { text: "Cancel"; onClicked: descriptorsSheet.close() } ]
        rightActions: [
            LogosButton {
                objectName: "confirmDescriptorsButton"; text: "Show"
                onClicked: {
                    descriptorsSheet.close()
                    root.descriptorsNote = ""
                    logos.watch(backend.descriptors(),
                                function (v) {
                                    var r = root.j(v, "{}")
                                    // Lands only if the user is still on Settings with this wallet open.
                                    if (r.ok === true && root.walletOpen && root.page === 4) root.shownDescriptors = r
                                    else if (r.ok !== true) root.descriptorsNote = r.error || "The wallet backend did not answer."
                                },
                                function () { root.descriptorsNote = "The wallet backend did not answer." })
                }
            }
        ]
    }

    LogosDialog {
        id: networkSheet
        objectName: "networkSheet"
        title: "Sources and privacy"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 760)
        onOpened: if (root.ready) backend.refreshSources()
        contentItem: ScrollView {
            id: networkSheetScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(networkSheetLoader.implicitHeight, Math.max(200, root.height - 200))
            Loader {
                id: networkSheetLoader
                width: networkSheetScroll.availableWidth
                active: networkSheet.visible
                sourceComponent: networkPane
            }
        }
        rightActions: [ LogosButton { objectName: "networkSheetDone"; text: "Done"; onClicked: networkSheet.close() } ]
    }
}
