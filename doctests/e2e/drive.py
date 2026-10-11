#!/usr/bin/env python3
# Drives the full-Basecamp e2e: the wallet, keys and signer apps over Basecamp's QML inspector, and
# the regtest chain through the wallet core's chain script. One phase per run; state in e2e/state.json.
import base64
import datetime
import json
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import time

WORK = os.path.abspath(os.environ.get("E2E_WORK", os.getcwd()))
E2E = os.path.join(WORK, "e2e")
PORT = int(os.environ.get("E2E_INSPECTOR_PORT", "3791"))
BUILD = os.path.join(E2E, "build")
CHAIN = os.path.join(BUILD, "chain", "bin", "regtest-chain")
BASECAMP = os.path.join(BUILD, "basecamp", "bin", "LogosBasecamp")
CHAIN_DIR = os.path.join(E2E, "chain")
# Off the regtest defaults, so another test chain on this machine is left alone.
CHAIN_ENV = {"CHAIN_DIR": CHAIN_DIR, "RPC_PORT": "28543", "P2P_PORT": "28544", "FORK_RPC_PORT": "28553",
             "FORK_P2P_PORT": "28554", "ELECTRUM_PORTS": "61701,61711"}
ELECTRUM_PORTS = [61701, 61711]
APP, KEYS, SIGNER = "bitcoin_wallet_ui", "evm_keystore_ui", "evm_signer_ui"
MODULE_BUILDS = ["backend", "core", "node", "keystore", "manager"]
PLUGIN_BUILDS = ["wallet", "keys", "signer"]
MISSING = object()


class Fail(Exception):
    pass


class InspectorError(Exception):
    pass


def log(msg):
    print(msg, flush=True)


def passed(msg):
    print("PASS " + msg, flush=True)


def expect(cond, msg):
    if not cond:
        raise Fail(msg)
    passed(msg)


# ---- state and the test's own secrets ----

def state():
    try:
        with open(os.path.join(E2E, "state.json")) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(**kv):
    s = state()
    s.update(kv)
    os.makedirs(E2E, exist_ok=True)
    tmp = os.path.join(E2E, "state.json.tmp")
    with open(tmp, "w") as f:
        json.dump(s, f, indent=1, sort_keys=True)
    os.replace(tmp, os.path.join(E2E, "state.json"))


SECRETS = os.path.join(E2E, "secrets")


def secret_write(name, value):
    os.makedirs(SECRETS, mode=0o700, exist_ok=True)
    fd = os.open(os.path.join(SECRETS, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(value)


def secret(name):
    with open(os.path.join(SECRETS, name)) as f:
        return f.read()


# ---- the chain ----

def chain(*args, check=True):
    r = subprocess.run([CHAIN, *args], env={**os.environ, **CHAIN_ENV}, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise Fail("chain %s: exit %d: %s%s" % (" ".join(args), r.returncode, r.stdout, r.stderr))
    return r.stdout.strip()


def rpc(method, params=None, wallet=""):
    out = chain("rpc", method, json.dumps(params or []), wallet)
    r = json.loads(out) if out else {}
    if r.get("error"):
        raise Fail("rpc %s: %s" % (method, r["error"]))
    return r.get("result")


def height():
    return int(rpc("getblockcount"))


def mine(n, address=None):
    chain("mine", str(n), *([address] if address else []))
    return height()


def wrapper_binary(name):
    with open(os.path.realpath(CHAIN)) as f:
        m = re.search(r"(/nix/store/[^'\"\s]*/bin/%s)\b" % name, f.read())
    if not m:
        raise Fail("no %s in %s" % (name, CHAIN))
    return m.group(1)


def listening(port):
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def wait_gone(pid, secs):
    end = time.time() + secs
    while time.time() < end and alive(pid):
        time.sleep(0.1)
    return not alive(pid)


def electrs_stop():
    for i in (0, 1):
        f = os.path.join(CHAIN_DIR, "electrs%d.pid" % i)
        if not os.path.exists(f):
            continue
        pid = int(open(f).read().strip())
        if alive(pid):
            os.kill(pid, signal.SIGTERM)
            if not wait_gone(pid, 30):
                os.kill(pid, signal.SIGKILL)
        os.remove(f)
    for p in ELECTRUM_PORTS:
        if listening(p):
            raise Fail("electrs still listening on %d" % p)


# The flags of chain.sh's start_electrs, which the script only runs together with bitcoind.
def electrs_start():
    electrs, data = wrapper_binary("electrs"), os.path.join(CHAIN_DIR, "bitcoind")
    for i, port in enumerate(ELECTRUM_PORTS):
        logf = open(os.path.join(CHAIN_DIR, "electrs%d.log" % i), "ab")
        p = subprocess.Popen(
            [electrs, "--skip-default-conf-files", "--network", "regtest", "--db-dir",
             os.path.join(CHAIN_DIR, "electrs%d" % i), "--daemon-dir", data, "--cookie-file",
             os.path.join(data, "regtest", ".cookie"), "--daemon-rpc-addr", "127.0.0.1:" + CHAIN_ENV["RPC_PORT"],
             "--daemon-p2p-addr", "127.0.0.1:" + CHAIN_ENV["P2P_PORT"], "--electrum-rpc-addr",
             "127.0.0.1:%d" % port, "--monitoring-addr", "127.0.0.1:%d" % (port + 1), "--wait-duration-secs", "1"],
            stdin=subprocess.DEVNULL, stdout=logf, stderr=subprocess.STDOUT, start_new_session=True)
        with open(os.path.join(CHAIN_DIR, "electrs%d.pid" % i), "w") as f:
            f.write(str(p.pid))
    end = time.time() + 60
    while not all(listening(p) for p in ELECTRUM_PORTS):
        if time.time() > end:
            raise Fail("electrs did not come back")
        time.sleep(0.2)


# ---- the inspector ----

class Inspector:
    def __init__(self, port=PORT):
        self.port, self.sock, self.buf = port, None, b""

    def connect(self, timeout=60):
        end = time.time() + timeout
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=5)
                self.sock.settimeout(90)
                return
            except OSError:
                if time.time() > end:
                    raise Fail("no QML inspector on port %d" % self.port)
                time.sleep(1)

    def rpc(self, command, **params):
        if self.sock is None:
            self.connect()
        self.sock.sendall((json.dumps({"command": command, "params": params}) + "\n").encode())
        while b"\n" not in self.buf:
            chunk = self.sock.recv(1 << 20)
            if not chunk:
                raise Fail("the inspector closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        r = json.loads(line)
        if "error" in r:
            raise InspectorError(r["error"])
        return r

    def ids(self, name):
        return [m["id"] for m in self.rpc("findByProperty", property="objectName", value=name).get("matches", [])]

    def props(self, oid):
        return {p["name"]: p.get("value") for p in self.rpc("getProperties", objectId=oid).get("properties", [])}

    # The visible match when there are several, such as a tile in two sidebar lists.
    def obj(self, name):
        best = None
        for oid in self.ids(name):
            try:
                p = self.props(oid)
            except InspectorError:
                continue
            if best is None or (p.get("visible") is True and best[1].get("visible") is not True):
                best = (oid, p)
        return best

    def get(self, name, prop):
        o = self.obj(name)
        return MISSING if o is None else o[1].get(prop, MISSING)

    def all_texts(self, name):
        out = []
        for oid in self.ids(name):
            try:
                p = self.props(oid)
            except InspectorError:
                continue
            if p.get("visible") is not False:
                out.append(str(p.get("text", "")))
        return out

    def wait_obj(self, name, pred, timeout, what=None):
        end, last = time.time() + timeout, None
        while True:
            o = self.obj(name)
            if o is not None:
                last = o[1]
                if pred(o[1]):
                    return o
            if time.time() > end:
                brief = {k: last[k] for k in ("visible", "enabled", "text", "checked", "opened", "value") if last and k in last}
                raise Fail("%s: not reached in %ss (last %s)" % (what or name, timeout, brief if last else "not found"))
            time.sleep(0.4)

    def wait(self, name, prop, want, timeout=30, what=None):
        test = want if callable(want) else (lambda v: v == want)
        o = self.wait_obj(name, lambda p: prop in p and test(p[prop]), timeout,
                          what or "%s.%s %s" % (name, prop, "condition" if callable(want) else "== %r" % (want,)))
        return o[1][prop]

    def press(self, name, timeout=30):
        oid, _ = self.wait_obj(name, lambda p: p.get("visible") is True and p.get("enabled") is not False,
                               timeout, "%s visible and enabled" % name)
        try:
            self.rpc("callMethod", objectId=oid, method="clicked", args=[])
        except InspectorError:
            self.rpc("click", objectId=oid)

    # A radio or check box: emitting clicked() would not change checked, which is what its handlers watch.
    def check(self, name, timeout=30):
        oid, _ = self.wait_obj(name, lambda p: p.get("visible") is True and p.get("enabled") is not False,
                               timeout, "%s visible and enabled" % name)
        if self.rpc("setProperty", objectId=oid, property="checked", value=True).get("value") is not True:
            raise Fail("%s did not take checked" % name)

    def set_text(self, name, text, timeout=30):
        oid, _ = self.wait_obj(name, lambda p: p.get("visible") is True and p.get("enabled") is not False,
                               timeout, "%s visible and enabled" % name)
        r = self.rpc("setProperty", objectId=oid, property="text", value=text)
        if r.get("value") != text:
            raise Fail("%s took %r, not the text set" % (name, r.get("value")))

    def call(self, name, method, *args):
        o = self.obj(name)
        if o is None:
            raise Fail("no %s to call %s on" % (name, method))
        return self.rpc("callMethod", objectId=o[0], method=method, args=list(args))

    def has_text(self, text):
        for m in self.rpc("findByProperty", property="text", value=text).get("matches", []):
            try:
                if self.props(m["id"]).get("visible") is not False:
                    return True
            except InspectorError:
                pass
        return False

    def wait_text(self, text, timeout=30):
        end = time.time() + timeout
        while not self.has_text(text):
            if time.time() > end:
                raise Fail("the text %r did not show in %ss" % (text, timeout))
            time.sleep(0.4)

    def shot(self, name):
        try:
            r = self.rpc("screenshot")
        except (InspectorError, Fail):
            return
        if r.get("image"):
            os.makedirs(os.path.join(E2E, "shots"), exist_ok=True)
            with open(os.path.join(E2E, "shots", name + ".png"), "wb") as f:
                f.write(base64.b64decode(r["image"]))


# ---- Basecamp ----

def userdir(user):
    return os.path.join(E2E, user, "userdir")


def home(user):
    return os.path.join(E2E, user, "home")


def copytree(src, dst):
    subprocess.run(["cp", "-RL", src, dst], check=True)
    subprocess.run(["chmod", "-R", "u+w", dst], check=True)


def layout(user):
    ud = userdir(user)
    if os.path.exists(os.path.join(E2E, user)):
        subprocess.run(["chmod", "-R", "u+w", os.path.join(E2E, user)], check=False)
        subprocess.run(["rm", "-rf", os.path.join(E2E, user)], check=True)
    os.makedirs(os.path.join(ud, "modules"))
    os.makedirs(os.path.join(ud, "plugins"))
    os.makedirs(home(user))
    for b in MODULE_BUILDS:
        for m in sorted(os.listdir(os.path.join(BUILD, b, "modules"))):
            copytree(os.path.join(BUILD, b, "modules", m), os.path.join(ud, "modules", m))
    for b in PLUGIN_BUILDS:
        for m in sorted(os.listdir(os.path.join(BUILD, b, "plugins"))):
            copytree(os.path.join(BUILD, b, "plugins", m), os.path.join(ud, "plugins", m))
    # regtest.json turns regtest on for the backend and the node module, and gives the core its servers.
    cfg = {"bitcoin_wallet_backend": {}, "bitcoin_node_module": {},
           "bitcoin_wallet_core_module": {"electrum": ["tcp://127.0.0.1:%d" % p for p in ELECTRUM_PORTS], "pollSecs": 1}}
    for module, body in cfg.items():
        d = os.path.join(ud, "module_data", module, "e2e")
        os.makedirs(d)
        with open(os.path.join(d, "regtest.json"), "w") as f:
            json.dump(body, f)
    for kind in ("modules", "plugins"):
        for m in sorted(os.listdir(os.path.join(ud, kind))):
            variant = open(os.path.join(ud, kind, m, "variant")).read().strip()
            if variant.endswith("-dev"):
                raise Fail("%s is the dev variant %s; Basecamp loads portable ones" % (m, variant))
            log("%s/%s %s" % (kind, m, variant))
    passed("laid out %s: five modules and three apps, portable, with regtest.json for the wallet's modules" % user)


def descendants(pid):
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], capture_output=True, text=True).stdout
    kids = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            kids.setdefault(int(parts[1]), []).append(int(parts[0]))
    found, todo = [], [pid]
    while todo:
        for k in kids.get(todo.pop(), []):
            found.append(k)
            todo.append(k)
    return found


def command_of(pid):
    return subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()


def launch(user):
    if listening(PORT):
        raise Fail("port %d is held by another process; the driver would talk to it" % PORT)
    env = dict(os.environ, HOME=home(user), USERPROFILE=home(user), LOGOS_NO_SCHEME_REGISTER="1",
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QML_INSPECTOR_PORT=str(PORT),
               QT_FORCE_STDERR_LOGGING="1")
    logf = open(os.path.join(E2E, "basecamp-%s.log" % user), "ab")
    p = subprocess.Popen([BASECAMP, "--user-dir", userdir(user)], env=env, cwd=WORK, stdin=subprocess.DEVNULL,
                         stdout=logf, stderr=subprocess.STDOUT, start_new_session=True)
    with open(os.path.join(E2E, "basecamp.pid"), "w") as f:
        f.write("%d %s" % (p.pid, user))
    ins = Inspector()
    ins.connect(timeout=180)
    for m in (APP, KEYS, SIGNER):
        ins.wait("sidebar.app." + m, "visible", True, 120)
    names = {m: ins.get("sidebar.app." + m, "text") for m in (APP, KEYS, SIGNER)}
    passed("Basecamp is up for %s (pid %d) with the apps %s" % (user, p.pid, ", ".join(map(str, names.values()))))


def stop_basecamp():
    f = os.path.join(E2E, "basecamp.pid")
    if not os.path.exists(f):
        log("no Basecamp of this run is running")
        return
    pid = int(open(f).read().split()[0])
    bundle = os.path.dirname(os.path.realpath(BASECAMP))
    tree = [k for k in descendants(pid) if bundle in command_of(k) or WORK in command_of(k)]
    if alive(pid):
        os.kill(pid, signal.SIGTERM)
        if not wait_gone(pid, 30):
            os.kill(pid, signal.SIGKILL)
            wait_gone(pid, 5)
    for k in tree:
        if alive(k):
            os.kill(k, signal.SIGTERM)
    for k in tree:
        if not wait_gone(k, 10):
            os.kill(k, signal.SIGKILL)
    os.remove(f)
    end = time.time() + 30
    while listening(PORT) and time.time() < end:
        time.sleep(0.5)
    passed("Basecamp stopped (pid %d and %d child processes)" % (pid, len(tree)))


# ---- the apps ----

ROOT = "bitcoinWalletRoot"


def show_app(ins, module):
    ins.press("sidebar.app." + module)


def wallet_tab(ins, i):
    ins.call(ROOT, "selectTab", i)


def chooser(ins, provider, accept=True):
    ins.wait("intentProvider_" + provider, "visible", True, 60, "the shell offers " + provider)
    title = ins.get("intentChooserDialog", "title")
    ins.press("intentChooserConfirm" if accept else "intentChooserCancel")
    ins.wait("intentChooserDialog", "visible", False, 20)
    return title


def amount_text(sat):
    whole, frac = divmod(int(sat), 100000000)
    f = ("%08d" % frac).rstrip("0")
    return "%d%s" % (whole, "." + f if f else "")


def wait_synced(ins, timeout=120):
    h = height()
    want = "Local chain · block {:,}".format(h)
    ins.wait("syncLine", "text", want, timeout, "the app reads the chain at block %d" % h)
    return h


def confirmed_value(ins):
    return ins.get("confirmedCard", "value")


# The confirmed balance once two reads 4 s apart agree: the app polls its backend every 3 s.
def settled_balance(ins, timeout=60):
    end, last = time.time() + timeout, confirmed_value(ins)
    while time.time() < end:
        time.sleep(4)
        now = confirmed_value(ins)
        if now == last:
            return now
        last = now
    raise Fail("the balance kept moving: %s" % last)


def row_text(ins, kind, txid, timeout=10):
    name = "%s_%s" % (kind, txid)
    end = time.time() + timeout
    while True:
        o = ins.obj(name)
        if o is not None:
            return o[1].get("text")
        # A row below the fold has no delegate yet: scroll the list as a person would.
        lst = ins.obj("historyList")
        if lst is not None:
            p = lst[1]
            y = float(p.get("contentY") or 0) + max(float(p.get("height") or 200) * 0.7, 100)
            top = float(p.get("contentHeight") or 0) - float(p.get("height") or 0)
            ins.rpc("setProperty", objectId=lst[0], property="contentY", value=0 if y > top + 1 else y)
        if time.time() > end:
            raise Fail("no Activity row for %s" % txid)
        time.sleep(0.3)


def wait_row(ins, kind, txid, want, timeout=60):
    end, last = time.time() + timeout, None
    test = want if callable(want) else (lambda v: v == want)
    while True:
        try:
            last = row_text(ins, kind, txid, timeout=3)
            if test(last):
                return last
        except Fail:
            pass
        if time.time() > end:
            raise Fail("Activity %s for %s: last %r" % (kind, txid[:12], last))
        time.sleep(0.5)


def fill_send(ins, address, btc, fee_rate):
    wallet_tab(ins, 1)
    ins.set_text("sendRecipientField", address)
    ins.wait("recipientBadge", "text", lambda t: t not in ("", "not valid"), 20, "the recipient is checked as valid")
    ins.set_text("sendAmountField", btc)
    if fee_rate is None and ins.get("feeNormal", "visible") is True:
        ins.press("feeNormal")
    else:
        ins.press("feeCustomChoice")
        ins.set_text("feeCustomField", str(fee_rate or 2))
    ins.press("reviewButton")
    ins.wait("reviewSheet", "opened", True, 20)


def approve_in_app(ins):
    before = ins.get(ROOT, "sendId")
    ins.press("approveInSignerButton")
    ins.wait(ROOT, "sendId", lambda v: bool(v) and v != before, 30, "the backend takes the request")
    return ins.wait(ROOT, "approvalHandle", lambda v: bool(v), 90, "the core asks the signer manager for approval")


def signer_shows(ins, expect_lines=()):
    ins.wait("signerApproveButton", "visible", True, 120, "the signer app shows the request")
    lines = ins.all_texts("renderLine")
    for e in expect_lines:
        if not any(e in l for l in lines):
            raise Fail("the signer's lines lack %r: %s" % (e, lines))
    return lines


def signer_approve(ins, password):
    ins.set_text("vaultPasswordField", password)
    ins.wait_obj("signerApproveButton", lambda p: p.get("text") == "Approve" and p.get("enabled") is True, 20,
                 "Approve arms after the dwell")
    ins.press("signerApproveButton")
    ins.wait_text("Approved — 1 item signed", 60)


# The shell brings the person back to the app that asked once the provider answers; else they go back.
def back_to_wallet(ins, provider):
    try:
        ins.wait("sidebar.app." + APP, "checked", True, 20, "the shell returns to the wallet app")
        passed("the shell brought the person back from %s to the wallet app" % provider)
    except Fail:
        log("NOTE the shell stayed on %s; the person goes back by the wallet's tile" % provider)
        show_app(ins, APP)
    ins.wait(ROOT, "ready", True, 30)


def wait_send(ins, outcome_headline, timeout=120):
    return ins.wait("sendHeadline", "text", outcome_headline, timeout, "the send settles as %r" % outcome_headline)


# The badge and both servers as the open wallet sees them: nothing suspect, both answering.
def sources_ok(ins, when):
    wallet_tab(ins, 4)
    lines = [ins.wait("walletSourceState_electrum-%d" % i, "text", lambda t: t.startswith("ok"), 30) for i in (0, 1)]
    badge = ins.wait("healthBadge", "text", "Sources OK", 30)
    wallet_tab(ins, 3)
    passed("%s: %s; electrum-0 %s; electrum-1 %s" % (when, badge, lines[0], lines[1]))


def payee(label):
    return rpc("getnewaddress", [label, "bech32"], "miner")


def history_count(ins):
    return int(ins.get("historyList", "count"))


# ---- phases ----

def phase_prepare_chain():
    chain("stop", check=False)
    subprocess.run(["rm", "-rf", CHAIN_DIR], check=True)
    out = chain("prepare")
    log(out)
    expect(height() >= 101, "a fresh regtest chain at block %d, two electrs on %s, and the fork node" % (height(), ELECTRUM_PORTS))


def phase_secrets():
    secret_write("password", secrets.token_urlsafe(18))
    secret_write("password-restore", secrets.token_urlsafe(18))
    passed("two test passwords generated into %s (0600), never a real one" % SECRETS)


def phase_open_create():
    ins = Inspector()
    show_app(ins, APP)
    ins.wait(ROOT, "ready", True, 120, "the wallet app's backend connects")
    ins.wait("statusLine", "text", "No wallet open", 120)
    ins.call(ROOT, "selectNetwork", "regtest")
    ins.wait("networkChip", "text", "regtest", 30)
    ins.press("familySegwit")
    ins.set_text("walletLabelField", "E2E regtest")
    ins.press("openWalletButton")
    ins.wait("keysWaitTitle", "visible", True, 60, "the app waits for the keys app")
    title = chooser(ins, KEYS)
    passed("the shell asks first (%r), and the person opens the keys app" % title)
    ins.wait("accessSheet", "opened", True, 120, "the keys app shows the request")
    lines = ins.all_texts("accessLine")
    log("keys app: " + " | ".join(lines))
    ins.press("accessAddWallet")
    ins.wait("bitcoinImportSheet", "opened", True, 20)
    expect(ins.get("btcFamilySegwit", "checked") is True and ins.get("btcChainTest", "checked") is True,
           "the request fixes a native segwit wallet on the test chains")
    ins.press("btcGenerateButton")
    phrase = ins.wait("btcPhraseText", "text", lambda t: len(t.split()) == 12, 30, "a 12-word phrase is generated")
    secret_write("phrase", phrase)
    w = phrase.split()
    ins.set_text("btcConfirmField", "%s %s %s" % (w[0], w[4], w[11]))
    ins.set_text("btcWalletPasswordField", secret("password"))
    ins.set_text("btcWalletNameField", "E2E regtest")
    expect(ins.get("btcKeepPhrase", "checked") is False, "the phrase is not kept in the keystore; the test writes it down")
    ins.press("btcConfirm")
    ins.wait("bitcoinImportSheet", "visible", False, 30)
    ins.wait("accessWallet_0", "checked", True, 20, "back in the request, the new wallet is picked")
    ins.set_text("accessPasswordField", secret("password"))
    ins.shot("open-keys-approve")
    ins.press("accessApproveButton")
    ins.wait("accessSheet", "visible", False, 30)
    passed("created and opened in the keys app with the generated password")
    back_to_wallet(ins, KEYS)
    ins.wait(ROOT, "walletState", lambda v: v in ("syncing", "ready"), 90, "the wallet opens")
    h = wait_synced(ins)
    ins.shot("open-synced")
    save(user="userA", open_height=h)
    log("PHASE open-create OK")


def phase_receive():
    ins = Inspector()
    show_app(ins, APP)
    wallet_tab(ins, 2)
    addr = ins.wait("receiveAddress", "text", lambda t: t.startswith("bcrt1q"), 30)
    txid = chain("fund", addr, "1.0")
    wallet_tab(ins, 0)
    ins.wait("pendingRow", "visible", True, 60, "an unconfirmed payment shows as pending")
    expect(ins.get("pendingRowAmount", "text") == "1 BTC", "pending: 1 BTC, not in the confirmed balance")
    ins.shot("receive-pending")
    mine(1)
    ins.wait("confirmedCard", "value", "1 BTC", 60, "mined: 1 BTC confirmed")
    ins.wait("pendingRow", "visible", False, 30)
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", txid, "1 confirmation")
    expect(row_text(ins, "historyIntent", txid) == "+1 BTC", "Activity lists +1 BTC, 1 confirmation")
    # A block mined to a fresh address: immature until 100 confirmations.
    wallet_tab(ins, 2)
    ins.press("newAddressButton")
    addr2 = ins.wait("receiveAddress", "text", lambda t: t.startswith("bcrt1q") and t != addr, 30)
    mine(1, addr2)
    coinbase = rpc("getblock", [rpc("getbestblockhash")])["tx"][0]
    reward = int(round(rpc("getrawtransaction", [coinbase, True])["vout"][0]["value"] * 1e8))
    wallet_tab(ins, 0)
    ins.wait("immatureRow", "visible", True, 60, "a block mined to the wallet shows as not spendable yet")
    expect(ins.get("immatureRowAmount", "text") == amount_text(reward) + " BTC", "immature: %s BTC" % amount_text(reward))
    mine(100)
    total = 100000000 + reward
    ins.wait("confirmedCard", "value", amount_text(total) + " BTC", 90, "100 blocks later it counts")
    ins.wait("immatureRow", "visible", False, 30)
    wait_synced(ins)
    save(receive_txid=txid, coinbase_txid=coinbase, balance_sat=total)
    log("PHASE receive OK")


def phase_send_expire():
    ins = Inspector()
    show_app(ins, APP)
    to = payee("payee-1")
    fill_send(ins, to, "0.1", 2)
    first = approve_in_app(ins)
    t0 = time.time()
    title = chooser(ins, SIGNER, accept=False)
    passed("the shell asks to open the signer app (%r); the person declines" % title)
    note = ins.wait("signerNote", "text", lambda t: t.startswith("The signer app was not opened"), 30, "the app says so")
    passed("the wallet app says: " + note)
    wait_send(ins, "Nobody approved it within 60 s", 120)
    waited = time.time() - t0
    expect(waited >= 50, "expired after %.0f s, since nobody showed it" % waited)
    ins.shot("send-expired")
    ins.press("askAgainButton")
    ins.wait(ROOT, "approvalHandle", lambda v: bool(v) and v != first, 60, "asked again: a new approval")
    chooser(ins, SIGNER)
    lines = signer_shows(ins, ["Send 0.10000000 BTC to " + to])
    log("signer: " + " | ".join(l.strip() for l in lines))
    signer_approve(ins, secret("password"))
    back_to_wallet(ins, SIGNER)
    wait_send(ins, "Sent", 90)
    txid = ins.wait("sendTxid", "text", lambda t: bool(re.search(r"[0-9a-f]{64}", t or "")), 30)
    txid = re.search(r"[0-9a-f]{64}", txid).group(0)
    ins.press("doneSendButton")
    expect(txid in rpc("getrawmempool"), "the send is in the node's mempool: %s" % txid)
    mine(1)
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", txid, "1 confirmation", 60)
    passed("Activity shows the send confirmed: %s" % row_text(ins, "historyIntent", txid))
    save(send1_txid=txid, send1_to=to)
    log("PHASE send-expire OK")


def phase_speed_up():
    ins = Inspector()
    show_app(ins, APP)
    to = payee("payee-2")
    fill_send(ins, to, "0.05", 1)
    approve_in_app(ins)
    chooser(ins, SIGNER)
    signer_shows(ins, ["Send 0.05000000 BTC to " + to])
    signer_approve(ins, secret("password"))
    back_to_wallet(ins, SIGNER)
    wait_send(ins, "Sent", 90)
    old = re.search(r"[0-9a-f]{64}", ins.get("sendTxid", "text")).group(0)
    ins.press("doneSendButton")
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", old, "sent · not confirmed", 60)
    row_text(ins, "speedUp", old)
    ins.press("speedUp_" + old)
    ins.wait("speedUpSheet", "opened", True, 20)
    ins.set_text("speedUpRateField", "6")
    ins.press("confirmSpeedUpButton")
    ins.wait(ROOT, "approvalHandle", lambda v: bool(v), 90, "the fee bump asks for approval")
    chooser(ins, SIGNER)
    signer_shows(ins, ["Send 0.05000000 BTC to " + to])
    signer_approve(ins, secret("password"))
    back_to_wallet(ins, SIGNER)
    wait_send(ins, "Fee raised", 90)
    new = re.search(r"[0-9a-f]{64}", ins.get("sendTxid", "text")).group(0)
    ins.press("doneSendButton")
    pool = rpc("getrawmempool")
    expect(new in pool and old not in pool, "the replacement is in the mempool and the original is not")
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", old, "replaced", 60)
    mine(1)
    wait_row(ins, "historyState", new, "1 confirmation", 60)
    passed("the bump confirmed (%s); the original reads replaced" % row_text(ins, "historyIntent", new))
    save(bump_old_txid=old, bump_new_txid=new)
    log("PHASE speed-up OK")


def phase_reject():
    ins = Inspector()
    show_app(ins, APP)
    wait_synced(ins)
    before = settled_balance(ins)
    to = payee("payee-3")
    fill_send(ins, to, "0.02", 2)
    approve_in_app(ins)
    chooser(ins, SIGNER)
    signer_shows(ins, ["Send 0.02000000 BTC to " + to])
    ins.press("signerRejectButton")
    back_to_wallet(ins, SIGNER)
    wait_send(ins, "Rejected in the signer app", 60)
    ins.press("doneSendButton")
    ins.wait("confirmedCard", "value", before, 30, "nothing left the wallet: still %s" % before)
    expect(not any(to in json.dumps(rpc("getrawtransaction", [t, True])) for t in rpc("getrawmempool")),
           "nothing reached the node; still %s" % before)
    log("PHASE reject OK")


def phase_reorg():
    ins = Inspector()
    show_app(ins, APP)
    wallet_tab(ins, 2)
    ins.press("newAddressButton")
    addr = ins.wait("receiveAddress", "text", lambda t: t.startswith("bcrt1q"), 30)
    txid = chain("fund", addr, "0.3")
    h = mine(1)
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", txid, "1 confirmation", 60)
    old_tip = rpc("getbestblockhash")
    balance = confirmed_value(ins)
    sources_ok(ins, "before the reorg")
    out = chain("reorg", "1")
    log(out)
    expect(rpc("getblockhash", [h]) != old_tip and height() == h + 1, "the node took a fork that replaced block %d" % h)
    expect(txid in rpc("getblock", [rpc("getblockhash", [h])])["tx"], "the replacing block holds the same payment")
    seen, end = [], time.time() + 45
    alert = False
    while time.time() < end:
        st = row_text(ins, "historyState", txid, timeout=5)
        line = ins.get("syncLine", "text")
        if not seen or seen[-1] != (st, line):
            seen.append((st, line))
        alert = alert or ins.get("alertBanner", "visible") is True
        if st == "2 confirmations" and line == "Local chain · block {:,}".format(h + 1) and time.time() > end - 30:
            break
        time.sleep(0.5)
    log("re-anchoring as the app showed it: " + " -> ".join("%s / %s" % s for s in seen))
    expect(seen[-1] == ("2 confirmations", "Local chain · block {:,}".format(h + 1)),
           "the payment re-anchored in the new block: 2 confirmations at block %d" % (h + 1))
    expect(not alert, "no source alert during the reorg")
    expect(confirmed_value(ins) == balance, "the balance is unchanged: %s" % balance)
    sources_ok(ins, "after the reorg")
    save(reorg_txid=txid, reorg_height=h)
    log("PHASE reorg OK")


def snapshot(ins):
    s = state()
    wallet_tab(ins, 3)
    rows = {}
    for key in ("receive_txid", "coinbase_txid", "send1_txid", "bump_new_txid", "reorg_txid"):
        t = s.get(key)
        if t:
            rows[t] = {"state": row_text(ins, "historyState", t, 20), "intent": row_text(ins, "historyIntent", t, 20)}
    return {"confirmed": confirmed_value(ins), "rows": rows, "count": history_count(ins)}


def phase_close():
    ins = Inspector()
    show_app(ins, APP)
    wait_synced(ins)
    snap = snapshot(ins)
    log("before closing: " + json.dumps(snap))
    save(snapshot=snap)
    wallet_tab(ins, 4)
    ins.press("settingsCloseWalletButton")
    ins.wait("statusLine", "text", "No wallet open", 60, "the wallet closes")
    log("PHASE close OK")


def phase_restore():
    ins = Inspector()
    show_app(ins, APP)
    ins.wait(ROOT, "ready", True, 120)
    ins.wait("statusLine", "text", "No wallet open", 120)
    ins.call(ROOT, "selectNetwork", "regtest")
    ins.wait("networkChip", "text", "regtest", 30)
    ins.press("familySegwit")
    ins.press("openWalletButton")
    chooser(ins, KEYS)
    ins.wait("accessSheet", "opened", True, 120)
    ins.press("accessAddWallet")
    ins.wait("bitcoinImportSheet", "opened", True, 20)
    ins.check("btcSourceType")
    ins.set_text("btcPhraseField", secret("phrase"))
    birthday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
    ins.set_text("btcBirthdayField", birthday)
    ins.set_text("btcWalletPasswordField", secret("password-restore"))
    ins.set_text("btcWalletNameField", "E2E restored")
    ins.press("btcConfirm")
    ins.wait("bitcoinImportSheet", "visible", False, 30)
    ins.wait("accessWallet_0", "checked", True, 20)
    ins.set_text("accessPasswordField", secret("password-restore"))
    ins.press("accessApproveButton")
    ins.wait("accessSheet", "visible", False, 30)
    passed("restored in the keys app from the written-down phrase, birthday %s" % birthday)
    back_to_wallet(ins, KEYS)
    ins.wait(ROOT, "walletState", lambda v: v in ("syncing", "ready"), 90)
    wait_synced(ins, 180)
    want = state()["snapshot"]
    ins.wait("confirmedCard", "value", want["confirmed"], 120, "the restored balance matches: %s" % want["confirmed"])
    passed("the restored balance matches: %s" % want["confirmed"])
    got = snapshot(ins)
    log("restored: " + json.dumps(got))
    # A replaced send never reached a block, so only the first user dir can list it.
    log("Activity rows: %d in user A, %d restored" % (want["count"], got["count"]))
    for t, row in want["rows"].items():
        g = got["rows"].get(t)
        expect(g is not None and g["state"] == row["state"], "%s… %s in both" % (t[:12], row["state"]))
    save(restored=got)
    log("PHASE restore OK")


def unknown_send(ins, label, amount):
    to = payee(label)
    fill_send(ins, to, amount, 2)
    approve_in_app(ins)
    chooser(ins, SIGNER)
    signer_shows(ins, ["Send %s BTC to %s" % ("%.8f" % float(amount), to)])
    electrs_stop()
    passed("both electrs stopped before the approval")
    signer_approve(ins, secret("password-restore"))
    back_to_wallet(ins, SIGNER)
    wait_send(ins, "The outcome is unknown: it may have left", 120)
    txid = re.search(r"[0-9a-f]{64}", ins.get("sendTxid", "text")).group(0)
    ins.shot("unknown-" + label)
    return txid


def phase_unknown_rebroadcast():
    ins = Inspector()
    show_app(ins, APP)
    txid = unknown_send(ins, "payee-4", "0.04")
    expect(txid not in rpc("getrawmempool"), "it never reached the node")
    electrs_start()
    passed("electrs is back")
    ins.press("rebroadcastButton", 60)
    wait_send(ins, "Sent", 120)
    expect(txid in rpc("getrawmempool"), "rebroadcast: in the node's mempool now")
    ins.press("doneSendButton")
    mine(1)
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", txid, "1 confirmation", 90)
    save(unknown1_txid=txid)
    log("PHASE unknown-rebroadcast OK")


def phase_unknown_forget():
    ins = Inspector()
    show_app(ins, APP)
    wait_synced(ins)
    before = confirmed_value(ins)
    txid = unknown_send(ins, "payee-5", "0.03")
    ins.press("forgetPaymentButton", 60)
    ins.wait("forgetSheet", "opened", True, 20)
    ins.press("confirmForgetButton")
    wait_send(ins, "Forgotten", 60)
    note = ins.wait("forgetNote", "text", lambda t: bool(t), 30)
    passed("forgotten, with the backend's note: %s" % note)
    electrs_start()
    passed("electrs is back")
    ins.press("doneSendButton")
    mine(1)
    wait_synced(ins)
    expect(txid not in rpc("getrawmempool"), "the forgotten payment never left")
    ins.wait("confirmedCard", "value", before, 60, "its coins are spendable again: %s" % before)
    save(unknown2_txid=txid)
    log("PHASE unknown-forget OK")


def phase_cleanup():
    try:
        stop_basecamp()
    except Exception as e:
        log("stopping Basecamp: %s" % e)
    chain("stop", check=False)
    log("chain stopped")


PHASES = {
    "prepare-chain": phase_prepare_chain, "secrets": phase_secrets, "open-create": phase_open_create,
    "receive": phase_receive, "send-expire": phase_send_expire, "speed-up": phase_speed_up,
    "reject": phase_reject, "reorg": phase_reorg, "close": phase_close, "restore": phase_restore,
    "unknown-rebroadcast": phase_unknown_rebroadcast, "unknown-forget": phase_unknown_forget,
    "stop": stop_basecamp, "cleanup": phase_cleanup,
}


def main(argv):
    if len(argv) >= 2 and argv[0] in ("layout", "launch"):
        fn, args = {"layout": layout, "launch": launch}[argv[0]], argv[1:]
    elif len(argv) == 1 and argv[0] in PHASES:
        fn, args = PHASES[argv[0]], []
    else:
        sys.exit("usage: drive.py layout|launch <user> | " + " | ".join(PHASES))
    try:
        fn(*args)
    except (Fail, InspectorError) as e:
        print("FAIL %s: %s" % (argv[0], e), flush=True)
        try:
            Inspector().shot("fail-" + argv[0])
        except Exception:
            pass
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
