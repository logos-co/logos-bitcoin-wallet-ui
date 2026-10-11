#include "bitcoin_wallet_ui_backend.h"

#include <QJsonDocument>
#include <QRegularExpression>
#include <QUrl>

#include "logos_sdk.h"
#include "qrcodegen.hpp"

namespace {
QJsonObject parse(const QString &s) { return QJsonDocument::fromJson(s.toUtf8()).object(); }
QString compact(const QJsonValue &v) {
    if (v.isArray()) return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact));
    if (v.isObject()) return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    return {};
}
QString stripOk(const QString &reply) { QJsonObject o = parse(reply); o.remove("ok"); return compact(o); }
QString errorOf(const QJsonObject &o) { return o.value("error").toString(QStringLiteral("the wallet backend did not answer")); }

constexpr int kReadPollMs = 3000;
constexpr int kJobPollMs = 750;
constexpr int kSendPollMs = 700;
constexpr int kStaleReadMs = 15000;
constexpr int kSourcesPollMs = 15000;
constexpr int kHealthPollMs = 30000;
constexpr int kFeePollMs = 30000;
constexpr int kFeeRetryMs = 6000;
constexpr int kExposurePollMs = 30000;
constexpr int kHistoryMinGapMs = 10000;
constexpr int kUnsettledHistoryMs = 15000;
constexpr int kMaxAlerts = 10;

bool liveSend(const QString &s) { return s == "preparing" || s == "awaiting_approval" || s == "committing"; }
bool readyState(const QString &s) { return s == "syncing" || s == "ready"; }
// The backend's OPEN_STATES: a wallet open, or being opened or closed, locks the source settings.
bool openState(const QString &s) {
    return s == "awaiting_open" || s == "opening" || readyState(s) || s == "closing";
}
bool due(const QElapsedTimer &t, int ms) { return !t.isValid() || t.elapsed() >= ms; }

// abandon_send is newer than some backends this view builds against; those answer that they lack it.
template <typename B>
auto callAbandonSend(B &b, const QString &request, int) -> decltype(b.abandon_send(request)) {
    return b.abandon_send(request);
}
template <typename B>
QString callAbandonSend(B &, const QString &, long) {
    return QStringLiteral(R"({"ok":false,"error":"this wallet backend cannot forget a payment yet"})");
}
}

quint64 BitcoinWalletUiBackend::begin(Read &r) {
    if (r.inFlight && r.age.isValid() && r.age.elapsed() < kStaleReadMs) {
        r.again = true;
        return 0;
    }
    r.inFlight = true;
    r.again = false;
    r.age.restart();
    return ++r.seq;
}

// True when the reply belongs to the read in flight; a reply for a read given up on is dropped.
bool BitcoinWalletUiBackend::finish(Read &r, quint64 seq) {
    if (seq != r.seq) return false;
    r.inFlight = false;
    return true;
}

void BitcoinWalletUiBackend::say(const QString &line) {
    const QString cur = lastError();
    if (cur.isEmpty()) { setLastError(line); return; }
    // A failure repeated by the poll is said once.
    if (cur.split(QLatin1Char('\n')).contains(line)) return;
    setLastError(cur + QLatin1Char('\n') + line);
}

bool BitcoinWalletUiBackend::ok(const QString &reply, const QString &context) {
    const QJsonObject o = parse(reply);
    if (o.value("ok").toBool()) return true;
    say(context.isEmpty() ? errorOf(o) : QStringLiteral("%1: %2").arg(context, errorOf(o)));
    return false;
}

QString BitcoinWalletUiBackend::walletState() const { return parse(statusJson()).value("state").toString(); }
bool BitcoinWalletUiBackend::walletReady() const { return readyState(walletState()); }
bool BitcoinWalletUiBackend::settingsLocked() const { return openState(walletState()) || hasJob("open"); }

qint64 BitcoinWalletUiBackend::walletTip() const {
    const QJsonValue t = parse(statusJson()).value("walletTip");
    return t.isDouble() ? t.toInteger() : -1;
}

bool BitcoinWalletUiBackend::hasJob(const QString &kind) const {
    for (const Job &j : m_jobs)
        if (j.kind == kind) return true;
    return false;
}

void BitcoinWalletUiBackend::clearAndRefresh() {
    setLastError({});
    refresh();
}

void BitcoinWalletUiBackend::onContextReady() {
    QObject::connect(&m_readPoll, &QTimer::timeout, [this] { poll(); });
    QObject::connect(&m_jobPoll, &QTimer::timeout, [this] { pollJobs(); });
    QObject::connect(&m_sendPoll, &QTimer::timeout, [this] { pollSend(); });
    // Subscribe, then reconcile. An event callback runs on the IPC read stack, so it only queues.
    auto &b = modules().bitcoin_wallet_backend;
    b.onWallet_state_changed([this](QString) { QTimer::singleShot(0, this, [this] { loadStatus(); }); });
    b.onSync_progress([this](QString) { QTimer::singleShot(0, this, [this] { loadStatus(); }); });
    b.onBalance_changed([this](QString payload) {
        QTimer::singleShot(0, this, [this, payload] {
            applyBalances(payload, m_epoch);
            readHistory(true);
        });
    });
    b.onJob_finished([this](QString id, QString) {
        QTimer::singleShot(0, this, [this, id] {
            for (const Job &j : m_jobs)
                if (j.id == id) { pollJobs(); return; }
        });
    });
    b.onSend_status_changed([this](QString id, QString state) {
        QTimer::singleShot(0, this, [this, id, state] {
            if (id == sendRequestId()) { pollSend(); return; }
            // A send asked for elsewhere, or before a reload, shows here unless one is on screen.
            const QString cur = parse(sendStatusJson()).value("state").toString();
            if ((sendRequestId().isEmpty() || !liveSend(cur)) && cur != "unknown"
                && (state == "preparing" || state == "awaiting_approval"))
                adoptSend(id);
        });
    });
    b.onSource_alert([this](QString payload) {
        QTimer::singleShot(0, this, [this, payload] {
            addAlert(payload);
            loadSources();
            loadHealth();
        });
    });
    m_readPoll.start(kReadPollMs);
    refresh();
    recoverSend();
}

// Does not clear lastError: it runs right after a failed job, and from events.
void BitcoinWalletUiBackend::refresh() {
    loadRegistry();
    loadStatus();
    loadSources();
    loadHealth();
    if (walletReady()) {
        loadBalances();
        readHistory(true);
        loadFeeRates();
        loadExposure();
    }
}

void BitcoinWalletUiBackend::poll() {
    loadStatus();
    if (walletReady()) {
        loadBalances();
        if (due(m_feeAge, feeRatesJson().isEmpty() ? kFeeRetryMs : kFeePollMs)) loadFeeRates();
        if (due(m_exposureAge, kExposurePollMs)) loadExposure();
        syncHistory();
    }
    // Until the backend has filled the network's defaults, the list is read again on every tick.
    const bool configured = parse(sourcesJson()).value("configured").toBool(true);
    if (due(m_sourcesAge, configured ? kSourcesPollMs : kReadPollMs)) loadSources();
    if (due(m_healthAge, kHealthPollMs)) loadHealth();
    // A rebroadcast, or the history after a restart, can still turn an unknown outcome into sent.
    const QJsonObject send = parse(sendStatusJson());
    if (!m_sendPoll.isActive() && send.value("state").toString() == "unknown" && !send.value("abandoned").toBool()) pollSend();
}

// ---- status ----------------------------------------------------------------------------------

void BitcoinWalletUiBackend::loadStatus() {
    const quint64 seq = begin(m_statusRead);
    if (!seq) return;
    modules().bitcoin_wallet_backend.wallet_statusAsync([this, seq](QString r) {
        QTimer::singleShot(0, this, [this, seq, r] {
            if (!finish(m_statusRead, seq)) return;
            applyStatus(r);
            if (m_statusRead.again) loadStatus();
        });
    });
}

void BitcoinWalletUiBackend::applyStatus(const QString &reply) {
    const QJsonObject before = parse(statusJson());
    QJsonObject o = parse(reply);
    if (!o.value("ok").toBool()) {
        // Not answering is said where the status shows; the last answer stays, marked.
        QJsonObject kept = before.isEmpty() ? QJsonObject{{"state", "unavailable"}} : before;
        kept.insert("unavailable", true);
        kept.insert("error", errorOf(o));
        setStatusJson(compact(kept));
        return;
    }
    o.remove("ok");
    setStatusJson(compact(o));
    const QString was = before.value("state").toString(), now = o.value("state").toString();
    if (readyState(was) && !readyState(now)) {
        ++m_epoch;
        clearWalletReads();
    } else if (!readyState(was) && readyState(now)) {
        ++m_epoch;
        walletBecameReady();
    }
    const auto network = [](const QJsonObject &s) {
        const QString n = s.value("network").toString();
        return openState(s.value("state").toString()) && !n.isEmpty() ? n : s.value("activeNetwork").toString();
    };
    // The lock and the network the sources describe follow the wallet.
    if (openState(was) != openState(now) || network(before) != network(o)) {
        loadSources();
        loadHealth();
        loadRegistry();
    }
}

void BitcoinWalletUiBackend::walletBecameReady() {
    loadBalances();
    readHistory(false);
    loadFeeRates();
    loadExposure();
    // Receive starts with a fresh address; the core hands back an unused one past the gap limit.
    newAddress();
}

// Nothing of a closed wallet may stay on screen for the next one.
void BitcoinWalletUiBackend::clearWalletReads() {
    setBalancesJson({});
    setHistoryJson({});
    setHistoryPage(0);
    m_historyTip = -1;
    m_historyUnsettled = false;
    m_historyAge.invalidate();
    setReceive({}, -1, {});
    setFeeRatesJson({});
    m_feeAge.invalidate();
    setExposureJson({});
    m_exposureAge.invalidate();
    setAlertsJson(QStringLiteral("[]"));
}

void BitcoinWalletUiBackend::loadRegistry() {
    auto &b = modules().bitcoin_wallet_backend;
    b.list_networksAsync([this](QString r) {
        QTimer::singleShot(0, this, [this, r] {
            if (parse(r).value("ok").toBool()) setNetworksJson(stripOk(r));
        });
    });
    const quint64 seq = begin(m_walletsRead);
    if (!seq) return;
    b.list_walletsAsync([this, seq](QString r) {
        QTimer::singleShot(0, this, [this, seq, r] {
            if (!finish(m_walletsRead, seq)) return;
            const QJsonObject o = parse(r);
            if (o.value("ok").toBool()) setWalletsJson(compact(o.value("wallets").toArray()));
            if (m_walletsRead.again) loadRegistry();
        });
    });
}

// ---- balances, history, fees -------------------------------------------------------------------

void BitcoinWalletUiBackend::loadBalances() {
    const quint64 seq = begin(m_balanceRead);
    if (!seq) return;
    const quint64 epoch = m_epoch;
    modules().bitcoin_wallet_backend.balancesAsync([this, seq, epoch](QString r) {
        QTimer::singleShot(0, this, [this, seq, epoch, r] {
            if (finish(m_balanceRead, seq)) applyBalances(r, epoch);
        });
    });
}

// A busy read is "not read", never zero: the last read stays on screen.
void BitcoinWalletUiBackend::applyBalances(const QString &reply, quint64 epoch) {
    if (epoch != m_epoch || !walletReady()) return;
    const QJsonObject o = parse(reply);
    if (!o.value("ok").toBool() || o.value("busy").toBool()) return;
    setBalancesJson(stripOk(reply));
}

void BitcoinWalletUiBackend::refreshHistory() { readHistory(false); }

void BitcoinWalletUiBackend::showHistoryPage(int page) {
    setHistoryPage(page < 0 ? 0 : page);
    setHistoryJson({});
    readHistory(false);
}

// `quiet` is a re-read nobody asked for: it stays off the error line.
void BitcoinWalletUiBackend::readHistory(bool quiet) {
    if (!walletReady()) return;
    const quint64 seq = begin(m_historyRead);
    if (!seq) return;
    const quint64 epoch = m_epoch;
    const int page = historyPage();
    const qint64 tip = walletTip();
    modules().bitcoin_wallet_backend.historyAsync(page, [this, seq, epoch, page, tip, quiet](QString r) {
        QTimer::singleShot(0, this, [this, seq, epoch, page, tip, quiet, r] {
            if (!finish(m_historyRead, seq)) return;
            const bool again = m_historyRead.again;
            if (epoch == m_epoch && page == historyPage()) {
                QJsonObject o = parse(r);
                if (!o.value("ok").toBool()) {
                    if (!quiet) say(QStringLiteral("history: ") + errorOf(o));
                } else if (!o.value("busy").toBool()) {
                    o.remove("ok");
                    setHistoryJson(compact(o));
                    m_historyUnsettled = false;
                    for (const QJsonValue &row : o.value("rows").toArray()) {
                        const QString s = row.toObject().value("state").toString();
                        if (s == "pending" || s == "waiting" || s == "sent") { m_historyUnsettled = true; break; }
                    }
                    m_historyAge.restart();
                    m_historyTip = tip;
                }
            }
            if (again) readHistory(true);
        });
    });
}

// Re-read on a new wallet tip (at most every 10 s), and every 15 s while a row is unsettled:
// a payment can confirm, or a send be replaced, without the user doing anything.
void BitcoinWalletUiBackend::syncHistory() {
    const qint64 age = m_historyAge.isValid() ? m_historyAge.elapsed() : -1;
    const qint64 tip = walletTip();
    const bool tipDue = tip >= 0 && tip != m_historyTip && (age < 0 || age >= kHistoryMinGapMs);
    const bool unsettledDue = m_historyUnsettled && age >= kUnsettledHistoryMs;
    if (age < 0 || tipDue || unsettledDue) readHistory(true);
}

void BitcoinWalletUiBackend::loadFeeRates() {
    const quint64 seq = begin(m_feeRead);
    if (!seq) return;
    m_feeAge.restart();
    const quint64 epoch = m_epoch;
    modules().bitcoin_wallet_backend.fee_ratesAsync([this, seq, epoch](QString r) {
        QTimer::singleShot(0, this, [this, seq, epoch, r] {
            if (!finish(m_feeRead, seq) || epoch != m_epoch) return;
            // No estimate yet answers an error: the Send form then offers a rate of its own.
            if (parse(r).value("ok").toBool()) setFeeRatesJson(stripOk(r));
        });
    });
}

// ---- sources -----------------------------------------------------------------------------------

void BitcoinWalletUiBackend::refreshSources() {
    loadSources();
    loadHealth();
    if (walletReady()) loadExposure();
}

void BitcoinWalletUiBackend::loadSources() {
    const quint64 seq = begin(m_sourcesRead);
    if (!seq) return;
    m_sourcesAge.restart();
    modules().bitcoin_wallet_backend.sourcesAsync([this, seq](QString r) {
        QTimer::singleShot(0, this, [this, seq, r] {
            if (!finish(m_sourcesRead, seq)) return;
            if (parse(r).value("ok").toBool()) setSourcesJson(stripOk(r));
            if (m_sourcesRead.again) loadSources();
        });
    });
}

// Quiet: the health reply describes its own failures.
void BitcoinWalletUiBackend::loadHealth() {
    const quint64 seq = begin(m_healthRead);
    if (!seq) return;
    m_healthAge.restart();
    modules().bitcoin_wallet_backend.source_healthAsync([this, seq](QString r) {
        QTimer::singleShot(0, this, [this, seq, r] {
            if (!finish(m_healthRead, seq)) return;
            if (parse(r).value("ok").toBool()) setHealthJson(stripOk(r));
            if (m_healthRead.again) loadHealth();
        });
    });
}

void BitcoinWalletUiBackend::loadExposure() {
    const quint64 seq = begin(m_exposureRead);
    if (!seq) return;
    m_exposureAge.restart();
    const quint64 epoch = m_epoch;
    modules().bitcoin_wallet_backend.exposureAsync([this, seq, epoch](QString r) {
        QTimer::singleShot(0, this, [this, seq, epoch, r] {
            if (!finish(m_exposureRead, seq) || epoch != m_epoch) return;
            if (parse(r).value("ok").toBool()) setExposureJson(stripOk(r));
        });
    });
}

void BitcoinWalletUiBackend::addAlert(const QString &payload) {
    const QJsonObject a = parse(payload);
    if (a.isEmpty()) return;
    QJsonArray list = QJsonDocument::fromJson(alertsJson().toUtf8()).array();
    list.prepend(a);
    while (list.size() > kMaxAlerts) list.removeLast();
    setAlertsJson(compact(list));
}

void BitcoinWalletUiBackend::dismissAlerts() { setAlertsJson(QStringLiteral("[]")); }

namespace {
const QString kLocked = QStringLiteral("Close the wallet to change these settings.");
}

// Applies a reply that answers as get_sources, and returns its refusal, if any.
QString BitcoinWalletUiBackend::settingsReply(const QString &reply) {
    const QJsonObject o = parse(reply);
    loadHealth();
    if (!o.value("ok").toBool()) {
        loadSources();
        return errorOf(o);
    }
    if (o.contains("sources")) setSourcesJson(stripOk(reply));
    else loadSources();
    return {};
}

QString BitcoinWalletUiBackend::setSource(QString sourceId, QString changesJson) {
    if (settingsLocked()) return kLocked;
    return settingsReply(modules().bitcoin_wallet_backend.set_source(sourceId, changesJson));
}

QString BitcoinWalletUiBackend::setProxy(QString proxy) {
    if (settingsLocked()) return kLocked;
    return settingsReply(modules().bitcoin_wallet_backend.set_proxy(proxy.trimmed()));
}

QString BitcoinWalletUiBackend::clearSuspect(QString sourceId) {
    const QJsonObject o = parse(modules().bitcoin_wallet_backend.clear_suspect(sourceId));
    loadSources();
    loadHealth();
    if (o.value("ok").toBool()) return {};
    for (const char *part : {"node", "wallet"}) {
        const QString e = o.value(QLatin1String(part)).toObject().value("error").toString();
        if (!e.isEmpty()) return e;
    }
    return errorOf(o);
}

// The list as set_sources takes it, `edit` applied; the node module validates the result.
QString BitcoinWalletUiBackend::editSources(const std::function<QString(QJsonArray &)> &edit) {
    if (settingsLocked()) return kLocked;
    const QJsonObject current = parse(modules().bitcoin_wallet_backend.sources());
    if (!current.value("ok").toBool()) return errorOf(current);
    QJsonArray list;
    for (const QJsonValue &v : current.value("sources").toArray()) {
        const QJsonObject s = v.toObject();
        QJsonObject in;
        for (const char *key : {"id", "kind", "url", "operator", "label", "use", "history", "tor"})
            in.insert(QLatin1String(key), s.value(QLatin1String(key)));
        list.append(in);
    }
    if (const QString refused = edit(list); !refused.isEmpty()) return refused;
    return settingsReply(modules().bitcoin_wallet_backend.set_sources(compact(list)));
}

QString BitcoinWalletUiBackend::addSource(QString address, QString kind, QString name) {
    address = address.trimmed();
    name = name.trimmed();
    kind = kind.trimmed().toLower();
    if (kind != QLatin1String("electrum") && kind != QLatin1String("esplora"))
        return QStringLiteral("Choose an Electrum or an Esplora server.");
    // The host only names the entry: the node module parses and normalizes the address itself.
    const QString host = QUrl(address.contains(QLatin1String("://")) ? address : QStringLiteral("tcp://") + address).host();
    if (host.isEmpty()) return QStringLiteral("Enter a server address, such as 192.168.1.20:50001 or electrs.lan.");
    if (name.size() > 128) return QStringLiteral("A name is at most 128 characters.");
    return editSources([&](QJsonArray &list) {
        QString base = host;
        base.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]")), QStringLiteral("-"));
        base.truncate(56);
        const auto taken = [&](const QString &id) {
            for (const QJsonValue &v : list)
                if (v.toObject().value("id").toString() == id) return true;
            return false;
        };
        QString id = base;
        for (int n = 2; taken(id); ++n) id = base + QLatin1Char('-') + QString::number(n);
        QJsonObject s{{"id", id}, {"kind", kind}, {"url", address}, {"use", true}, {"history", false}, {"tor", true}};
        if (!name.isEmpty()) s.insert("label", name);
        list.append(s);
        return QString();
    });
}

QString BitcoinWalletUiBackend::removeSource(QString sourceId) {
    return editSources([&](QJsonArray &list) {
        for (qsizetype i = 0; i < list.size(); ++i) {
            if (list[i].toObject().value("id").toString() != sourceId) continue;
            list.removeAt(i);
            return QString();
        }
        return QStringLiteral("%1 is not in the list.").arg(sourceId);
    });
}

// Returned for display only: not a PROP, so no other replica receives it.
QString BitcoinWalletUiBackend::descriptors() { return modules().bitcoin_wallet_backend.descriptors(); }

// ---- receiving ---------------------------------------------------------------------------------

void BitcoinWalletUiBackend::newAddress() {
    if (!walletReady()) return;
    const QString r = modules().bitcoin_wallet_backend.receive_address();
    if (!ok(r, QStringLiteral("receive address"))) return;
    const QJsonObject o = parse(r);
    setReceive(o.value("address").toString(), o.value("index").toInteger(-1), m_receiveAmount);
}

void BitcoinWalletUiBackend::setReceiveAmount(QString amountBtc) {
    amountBtc = amountBtc.trimmed();
    static const QRegularExpression amount(QStringLiteral("^(?:\\d{1,8}(?:\\.\\d{0,8})?|\\.\\d{1,8})$"));
    if (!amount.match(amountBtc).hasMatch() || amountBtc.toDouble() <= 0) amountBtc.clear();
    setReceive(m_receiveAddress, m_receiveIndex, amountBtc);
}

void BitcoinWalletUiBackend::setReceive(const QString &address, qint64 index, const QString &amount) {
    m_receiveAddress = address;
    m_receiveIndex = index;
    m_receiveAmount = amount;
    if (address.isEmpty()) {
        setReceiveJson({});
        setReceiveQrJson({});
        return;
    }
    const QString uri = amount.isEmpty() ? QStringLiteral("bitcoin:") + address
                                         : QStringLiteral("bitcoin:%1?amount=%2").arg(address, amount);
    // BIP21 in capitals when it can be: a bech32 address then fits the QR's compact alphanumeric mode.
    static const QRegularExpression bech32(QStringLiteral("^(bc|tb|bcrt)1"), QRegularExpression::CaseInsensitiveOption);
    const QString qrText = amount.isEmpty() && bech32.match(address).hasMatch() ? uri.toUpper() : uri;
    setReceiveJson(compact(QJsonObject{{"address", address}, {"index", index}, {"uri", uri}, {"amount", amount}}));
    setReceiveQrJson(qrModulesJson(qrText));
}

// A module matrix, not an image: the ui_qml sandbox blocks data: URIs. nayuki's qrcodegen (MIT).
QString BitcoinWalletUiBackend::qrModulesJson(const QString &text) const {
    using qrcodegen::QrCode;
    const QrCode qr = QrCode::encodeText(text.toUtf8().constData(), QrCode::Ecc::MEDIUM);
    const int n = qr.getSize();
    QString bits;
    bits.reserve(n * n);
    for (int y = 0; y < n; ++y)
        for (int x = 0; x < n; ++x) bits += qr.getModule(x, y) ? QLatin1Char('1') : QLatin1Char('0');
    return compact(QJsonObject{{"size", n}, {"bits", bits}});
}

// { ok, valid, address, type, amountSat?, reason? } on the wallet's network.
QString BitcoinWalletUiBackend::addressValid(QString text) {
    return modules().bitcoin_wallet_backend.address_valid(text.trimmed());
}

// ---- wallets -----------------------------------------------------------------------------------

void BitcoinWalletUiBackend::setActiveNetwork(QString network) {
    setLastError({});
    if (!ok(modules().bitcoin_wallet_backend.set_active_network(network), QStringLiteral("network"))) return;
    loadRegistry();
    loadStatus();
    loadSources();
    loadHealth();
}

// open and close answer a job id and settle later.
void BitcoinWalletUiBackend::track(const QString &reply, const QString &kind) {
    if (!ok(reply, kind)) return;
    const QString id = parse(reply).value("jobId").toString();
    if (id.isEmpty()) { say(kind + QStringLiteral(": no job id returned")); return; }
    m_jobs.append({id, kind});
    setPendingJobKind(kind);
    setBusy(true);
    m_jobPoll.start(kJobPollMs);
    loadStatus();
}

void BitcoinWalletUiBackend::pollJobs() {
    QJsonObject settled;
    for (const Job &job : QList<Job>(m_jobs)) {
        const QString r = modules().bitcoin_wallet_backend.job_status(job.id);
        if (r.isEmpty()) continue;  // the call itself failed; ask again on the next tick
        const QJsonObject st = parse(r);
        // A job the backend does not know (it restarted) will never settle.
        const QString state = st.value("ok").toBool() ? st.value("state").toString() : QStringLiteral("failed");
        if (state != "done" && state != "failed" && state != "cancelled") continue;
        m_jobs.removeIf([&](const Job &j) { return j.id == job.id; });
        const QString error = st.value("error").toString();
        const bool withdrawn = job.kind == "open" && m_openCancelled && state != "done";
        if (state != "done" && !withdrawn) say(job.kind + QStringLiteral(": ") + (error.isEmpty() ? state : error));
        settled = QJsonObject{{"jobId", job.id}, {"kind", job.kind}, {"state", state}, {"error", error},
                              {"withdrawn", withdrawn}};
    }
    if (m_jobs.isEmpty()) {
        m_jobPoll.stop();
        setBusy(false);
        setPendingJobKind({});
        m_openCancelled = false;
    } else {
        setPendingJobKind(m_jobs.last().kind);
    }
    if (settled.isEmpty()) return;
    loadStatus();
    loadRegistry();
    setLastJobJson(compact(settled));
}

void BitcoinWalletUiBackend::openWallet(QString paramsJson) {
    setLastError({});
    if (hasJob("open") || hasJob("close") || hasJob("cancel")) { say(QStringLiteral("open: a wallet is opening or closing")); return; }
    m_openCancelled = false;
    track(modules().bitcoin_wallet_backend.open_wallet(paramsJson), QStringLiteral("open"));
}

// While the person still decides in the keys app, closing withdraws the open.
void BitcoinWalletUiBackend::closeWallet() {
    setLastError({});
    if (hasJob("close") || hasJob("cancel")) { say(QStringLiteral("close: already closing")); return; }
    const QString s = walletState();
    const bool withdraw = hasJob("open") || s == "awaiting_open" || s == "opening";
    if (withdraw) m_openCancelled = true;
    track(modules().bitcoin_wallet_backend.close_wallet(), withdraw ? QStringLiteral("cancel") : QStringLiteral("close"));
}

// ---- sends -------------------------------------------------------------------------------------

// A settled send on screen gives way to a new one; a live one does not.
bool BitcoinWalletUiBackend::clearSettledSend() {
    if (sendRequestId().isEmpty()) return true;
    if (liveSend(parse(sendStatusJson()).value("state").toString())) {
        setSendError(QStringLiteral("A send is already open: approve or reject it in the signer app, or cancel it."));
        return false;
    }
    dismissSend();
    return true;
}

void BitcoinWalletUiBackend::requestSend(QString requestJson) {
    setSendError({});
    if (!clearSettledSend()) return;
    startSend(modules().bitcoin_wallet_backend.request_send(requestJson));
}

void BitcoinWalletUiBackend::requestFeeBump(QString txid, double feeRate) {
    setSendError({});
    if (!clearSettledSend()) return;
    const QJsonObject r{{"txid", txid.trimmed()}, {"feeRate", feeRate}};
    startSend(modules().bitcoin_wallet_backend.request_fee_bump(compact(r)));
}

void BitcoinWalletUiBackend::startSend(const QString &reply) {
    const QJsonObject o = parse(reply);
    const QString id = o.value("requestId").toString();
    if (!o.value("ok").toBool() || id.isEmpty()) {
        setSendError(errorOf(o));
        return;
    }
    adoptSend(id);
}

void BitcoinWalletUiBackend::adoptSend(const QString &id) {
    m_sendPoll.stop();
    setSendError({});
    setSendRequestId(id);
    setSendStatusJson(compact(QJsonObject{{"requestId", id}, {"state", "preparing"}}));
    m_sendPoll.start(kSendPollMs);
    pollSend();
}

// After a reload, or a backend restart, pick an open send back up rather than leave it unseen;
// failing that, the newest payment whose outcome is unknown and not yet abandoned.
void BitcoinWalletUiBackend::recoverSend() {
    modules().bitcoin_wallet_backend.list_sendsAsync([this](QString r) {
        QTimer::singleShot(0, this, [this, r] {
            if (!sendRequestId().isEmpty()) return;
            QString unknown;
            for (const QJsonValue &v : parse(r).value("sends").toArray()) {
                const QJsonObject s = v.toObject();
                const QString state = s.value("state").toString();
                if (liveSend(state)) { adoptSend(s.value("requestId").toString()); return; }
                if (state == "unknown" && unknown.isEmpty()) unknown = s.value("requestId").toString();
            }
            if (unknown.isEmpty()) return;
            modules().bitcoin_wallet_backend.send_statusAsync(unknown, [this, unknown](QString st) {
                QTimer::singleShot(0, this, [this, unknown, st] {
                    const QJsonObject o = parse(st);
                    if (sendRequestId().isEmpty() && o.value("state").toString() == "unknown" && !o.value("abandoned").toBool())
                        adoptSend(unknown);
                });
            });
        });
    });
}

void BitcoinWalletUiBackend::pollSend() {
    const QString id = sendRequestId();
    if (id.isEmpty()) { m_sendPoll.stop(); return; }
    const quint64 seq = begin(m_sendRead);
    if (!seq) return;
    modules().bitcoin_wallet_backend.send_statusAsync(id, [this, seq, id](QString r) {
        QTimer::singleShot(0, this, [this, seq, id, r] {
            if (!finish(m_sendRead, seq) || id != sendRequestId()) return;
            applySendStatus(id, r);
        });
    });
}

void BitcoinWalletUiBackend::applySendStatus(const QString &id, const QString &reply) {
    QJsonObject o = parse(reply);
    if (reply.isEmpty()) return;  // the call itself failed; the poll asks again
    if (!o.value("ok").toBool()) {
        // The backend lost the send. Once it was going out, nobody can say whether it left.
        m_sendPoll.stop();
        const QString was = parse(sendStatusJson()).value("state").toString();
        if (liveSend(was))
            setSendStatusJson(compact(QJsonObject{{"requestId", id}, {"state", was == "committing" ? "unknown" : "failed"},
                                                  {"error", errorOf(o)}}));
        return;
    }
    o.remove("ok");
    setSendStatusJson(compact(o));
    const QString state = o.value("state").toString();
    if (liveSend(state)) {
        if (!m_sendPoll.isActive()) m_sendPoll.start(kSendPollMs);
        return;
    }
    m_sendPoll.stop();
    // An unknown outcome may have moved money too: Activity is where the answer shows.
    if (state == "sent" || state == "unknown") {
        loadBalances();
        readHistory(true);
    }
}

// The backend withdraws the approval request; the send settles once the core confirms.
void BitcoinWalletUiBackend::cancelSend() {
    const QString id = sendRequestId();
    if (id.isEmpty()) return;
    const QJsonObject o = parse(modules().bitcoin_wallet_backend.cancel_send(id));
    if (!o.value("ok").toBool()) setSendError(errorOf(o));
    pollSend();
}

// Local only: the backend keeps its record either way.
void BitcoinWalletUiBackend::dismissSend() {
    m_sendPoll.stop();
    setSendRequestId({});
    setSendStatusJson(QStringLiteral("{}"));
    setSendError({});
}

// Broadcasts the same transaction again; it turns sent once a source has seen it.
void BitcoinWalletUiBackend::rebroadcast() {
    const QString id = sendRequestId();
    if (id.isEmpty()) return;
    setSendError({});
    const QJsonObject o = parse(modules().bitcoin_wallet_backend.rebroadcast(id));
    if (!o.value("ok").toBool()) setSendError(errorOf(o));
    pollSend();
}

// The core frees the coins; the send stays unknown, marked abandoned, so it is read again.
QString BitcoinWalletUiBackend::abandonSend(QString txid) {
    const QString request = compact(QJsonObject{{"txid", txid.trimmed()}});
    const QString reply = callAbandonSend(modules().bitcoin_wallet_backend, request, 0);
    const QJsonObject o = parse(reply);
    if (!o.value("ok").toBool()) return compact(QJsonObject{{"ok", false}, {"error", errorOf(o)}});
    pollSend();
    loadBalances();
    readHistory(true);
    return reply;
}
