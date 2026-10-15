#pragma once

#include <functional>

#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_bitcoin_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Bitcoin wallet's C++ half: every bitcoin_wallet_backend call is made here; the QML renders.
// Reads are asynchronous, one of a kind at a time; user actions answer at once.
class BitcoinWalletUiBackend : public BitcoinWalletUiSimpleSource,
                               public LogosUiPluginContext
{
public:
    void refresh() override;
    void clearAndRefresh() override;

    void setActiveNetwork(QString network) override;
    void openWallet(QString paramsJson) override;
    void closeWallet() override;
    void selectAccount(QString accountId) override;
    void setBirthday(QString paramsJson) override;
    void setGapLimit(QString paramsJson) override;

    void requestSend(QString requestJson) override;
    void requestFeeBump(QString txid, double feeRate) override;
    void cancelSend() override;
    void dismissSend() override;
    void rebroadcast() override;
    QString abandonSend(QString txid) override;

    void newAddress() override;
    void setReceiveAmount(QString amountBtc) override;
    QString addressValid(QString text) override;
    void refreshHistory() override;
    void showHistoryPage(int page) override;
    void dismissAlerts() override;

    QString setSource(QString sourceId, QString changesJson) override;
    QString useDirectSource(QString sourceId) override;
    QString addSource(QString address, QString kind, QString name) override;
    QString addRpcSource(QString address, QString rpcUser, QString rpcPass, QString name) override;
    QString useRpcSource(QString sourceId) override;
    QString removeSource(QString sourceId) override;
    QString setProxy(QString proxy) override;
    QString setOwnPeers(QString peersJson) override;
    QString clearSuspect(QString sourceId) override;
    void refreshSources() override;
    void probeSource(QString sourceId) override;
    QString descriptors() override;

protected:
    void onContextReady() override;

private:
    QString addServer(QString address, QString kind, QString name, const QJsonObject &credentials);
    // A reply lost for kStaleReadMs no longer holds up the next read of its kind.
    struct Read {
        bool inFlight = false;
        bool again = false;
        quint64 seq = 0;
        QElapsedTimer age;
    };
    struct Job {
        QString id;
        QString kind;
    };

    quint64 begin(Read &r);
    static bool finish(Read &r, quint64 seq);
    void say(const QString &line);
    bool ok(const QString &reply, const QString &context);
    QString walletState() const;
    bool walletReady() const;
    bool settingsLocked() const;
    qint64 walletTip() const;
    bool hasJob(const QString &kind) const;

    void poll();
    void loadStatus();
    void applyStatus(const QString &reply);
    void walletBecameReady();
    void clearWalletReads();
    void loadRegistry();
    void loadAccounts();
    void loadBalances();
    void applyBalances(const QString &reply, quint64 epoch);
    void readHistory(bool quiet);
    void syncHistory();
    void loadFeeRates();
    void loadSources();
    void loadPeerList();
    QString sourcesNetwork() const;
    void retryQueuedOpen();
    void loadHealth();
    void loadExposure();
    void addAlert(const QString &payload);
    void setReceive(const QString &address, qint64 index, const QString &amount);
    void showCurrentAddress();
    QString qrModulesJson(const QString &text) const;

    void track(const QString &reply, const QString &kind);
    void pollJobs();

    bool clearSettledSend();
    void startSend(const QString &reply);
    void adoptSend(const QString &id);
    void recoverSend();
    void pollSend();
    void applySendStatus(const QString &id, const QString &reply);

    QString settingsReply(const QString &reply);
    QString editSources(const std::function<QString(QJsonArray &)> &edit);

    QTimer m_readPoll;
    QTimer m_jobPoll;
    QTimer m_sendPoll;
    Read m_accountsRead;
    QElapsedTimer m_accountsAge;
    Read m_statusRead, m_walletsRead, m_balanceRead, m_historyRead, m_feeRead;
    Read m_sourcesRead, m_healthRead, m_exposureRead, m_sendRead;
    QElapsedTimer m_feeAge, m_sourcesAge, m_healthAge, m_exposureAge, m_historyAge, m_readySince;
    QList<Job> m_jobs;
    // The person withdrew an open still waiting in the keys app: its failure is no error.
    bool m_openCancelled = false;
    // An open answered busy (a switch or a close settling), and how often it was asked.
    QString m_openQueued;
    int m_openTries = 0;
    // Bumped whenever the open wallet changes, so a reply about the previous one is dropped.
    quint64 m_epoch = 0;
    // The wallet tip the history on screen was read at; -1 is "none read".
    qint64 m_historyTip = -1;
    bool m_historyUnsettled = false;
    QString m_receiveAddress;
    qint64 m_receiveIndex = -1;
    QString m_receiveAmount;
    // { unused, gapLimit } when New address met the gap limit; empty otherwise.
    QJsonObject m_receiveGap;
};
