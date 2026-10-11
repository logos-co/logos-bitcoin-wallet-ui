#!/usr/bin/env python3
# Drives the full-Basecamp e2e: the wallet, keys and signer apps over Basecamp's QML inspector, and
# the regtest chain through the wallet core's chain script. One phase per run; state in e2e/state.json.
# On Windows the chain runs on another machine: E2E_CHAIN_URL names its chainctl
# (logos-bitcoin-windows-tests' chain-host/), E2E_CHAIN_HOST the address the wallet dials.
import base64
import datetime
import json
import os
import re
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import sys
import time
import urllib.request

WINDOWS = os.name == "nt"
# The apps' texts carry "−" and "·": Windows would print them in its ANSI code page, and fail.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

WORK = os.path.abspath(os.environ.get("E2E_WORK", os.getcwd()))
E2E = os.path.join(WORK, "e2e")
PORT = int(os.environ.get("E2E_INSPECTOR_PORT", "3791"))
BUILD = os.path.join(E2E, "build")
CHAIN = os.path.join(BUILD, "chain", "bin", "regtest-chain")
BASECAMP = os.path.join(BUILD, "basecamp", "bin", "LogosBasecamp" + (".exe" if WINDOWS else ""))
CHAIN_URL = os.environ.get("E2E_CHAIN_URL", "")
CHAIN_HOST = os.environ.get("E2E_CHAIN_HOST", "127.0.0.1")
CHAIN_DIR = os.path.join(E2E, "chain")
# Off the regtest defaults, so another test chain on this machine is left alone.
CHAIN_ENV = {"CHAIN_DIR": CHAIN_DIR, "RPC_PORT": "28543", "P2P_PORT": "28544", "FORK_RPC_PORT": "28553",
             "FORK_P2P_PORT": "28554", "PEER_RPC_PORT": "28563", "PEER_P2P_PORT": "28564",
             "PRUNED_RPC_PORT": "28573", "PRUNED_P2P_PORT": "28574", "ELECTRUM_PORTS": "61701,61711",
             "ESPLORA_PORT": "61721", "ESPLORA": os.path.join(BUILD, "esplora", "bin", "electrs")}
ELECTRUM_PORTS = [61701, 61711]
# Blockstream's electrs on the main node, started by `chain.sh esplora` for the unchecked step.
ESPLORA_URL = "http://%s:%s" % (CHAIN_HOST, CHAIN_ENV["ESPLORA_PORT"])
# The chain's three nodes serve compact block filters: Kyoto's peers.
FILTER_PEERS = ["%s:%s" % (CHAIN_HOST, CHAIN_ENV[k]) for k in ("P2P_PORT", "FORK_P2P_PORT", "PEER_P2P_PORT")]
# What decides the chain, as the core's regtest.json says and the sync line names it.
AUTHORITIES = {
    "electrum": ({"electrum": ["tcp://%s:%d" % (CHAIN_HOST, p) for p in ELECTRUM_PORTS], "pollSecs": 1}, "Servers' headers"),
    "kyoto": ({"electrum": ["tcp://%s:%d" % (CHAIN_HOST, ELECTRUM_PORTS[0])], "kyoto": FILTER_PEERS, "kyotoRequired": 2,
               "checkOnly": True, "pollSecs": 1}, "Kyoto · "),
    "local": ({"local": True, "pollSecs": 1}, "Your node"),
    # Kyoto with Esplora as the only server, and a checkpoint: written by esplora_regtest().
    "kyoto-esplora": (None, "Kyoto · "),
}
APP, KEYS, SIGNER = "bitcoin_wallet_ui", "evm_keystore_ui", "evm_signer_ui"
MODULE_BUILDS = ["backend", "core", "node", "keystore", "manager"]
PLUGIN_BUILDS = ["wallet", "keys", "signer"]
APPS = ["bitcoin_wallet_ui", "evm_keystore_ui", "evm_signer_ui"]
MISSING = object()


class Fail(Exception):
    pass


class InspectorError(Exception):
    pass


# Every line also goes to e2e/drive.log: the doctest keeps a passing step's output only in its report.
def log(msg):
    print(msg, flush=True)
    try:
        os.makedirs(E2E, exist_ok=True)
        with open(os.path.join(E2E, "drive.log"), "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except OSError:
        pass


def passed(msg):
    log("PASS " + msg)


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

def chainctl(path, body=None):
    req = urllib.request.Request(CHAIN_URL.rstrip("/") + path, data=json.dumps(body or {}).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.loads(r.read())


def chain(*args, check=True):
    if CHAIN_URL:
        r = chainctl("/run", {"args": list(args)})
        code, out, err = r.get("code", -1), r.get("stdout", ""), r.get("stderr", "") or r.get("error", "")
    else:
        p = subprocess.run([CHAIN, *args], env={**os.environ, **CHAIN_ENV}, capture_output=True, text=True)
        code, out, err = p.returncode, p.stdout, p.stderr
    if check and code != 0:
        raise Fail("chain %s: exit %d: %s%s" % (" ".join(args), code, out, err))
    return out.strip()


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


# Windows has no ps, and its os.kill(pid, 0) TERMINATES the process: processes go through kernel32.
if WINDOWS:
    import ctypes
    from ctypes import wintypes

    _K32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _K32.OpenProcess.restype = wintypes.HANDLE
    _K32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE

    class _Entry(ctypes.Structure):
        _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                    ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wintypes.DWORD),
                    ("cntThreads", wintypes.DWORD), ("th32ParentProcessID", wintypes.DWORD),
                    ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_wchar * 260)]

    def _open(pid, access=0x1000):  # PROCESS_QUERY_LIMITED_INFORMATION
        return _K32.OpenProcess(access, False, pid)

    def _created(pid):
        h = _open(pid)
        if not h:
            return None
        try:
            t = [wintypes.FILETIME() for _ in range(4)]
            if not _K32.GetProcessTimes(h, *[ctypes.byref(x) for x in t]):
                return None
            return (t[0].dwHighDateTime << 32) | t[0].dwLowDateTime
        finally:
            _K32.CloseHandle(h)

    def _processes():
        snap = _K32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
        out, e = [], _Entry()
        e.dwSize = ctypes.sizeof(_Entry)
        ok = _K32.Process32FirstW(snap, ctypes.byref(e))
        while ok:
            out.append((e.th32ProcessID, e.th32ParentProcessID))
            ok = _K32.Process32NextW(snap, ctypes.byref(e))
        _K32.CloseHandle(snap)
        return out

    def _terminate(pid):
        h = _open(pid, 0x0001)  # PROCESS_TERMINATE
        if h:
            _K32.TerminateProcess(h, 1)
            _K32.CloseHandle(h)


def alive(pid):
    if WINDOWS:
        h = _open(pid)
        if not h:
            return False
        code = wintypes.DWORD()
        _K32.GetExitCodeProcess(h, ctypes.byref(code))
        _K32.CloseHandle(h)
        return code.value == 259  # STILL_ACTIVE
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


# SIGTERM, then SIGKILL after `secs`; Windows has only TerminateProcess.
def stop_pid(pid, secs):
    if WINDOWS:
        _terminate(pid)
        return wait_gone(pid, secs)
    os.kill(pid, signal.SIGTERM)
    if not wait_gone(pid, secs):
        os.kill(pid, signal.SIGKILL)
        return wait_gone(pid, 5)
    return True


def wait_gone(pid, secs):
    end = time.time() + secs
    while time.time() < end and alive(pid):
        time.sleep(0.1)
    return not alive(pid)


def electrs_stop():
    if CHAIN_URL:
        r = chainctl("/electrs-stop")
        if r.get("code") != 0:
            raise Fail("electrs did not stop: %s" % (r.get("stderr") or r.get("error")))
        return
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
    if CHAIN_URL:
        r = chainctl("/electrs-start")
        if r.get("code") != 0:
            raise Fail("electrs did not come back: %s" % (r.get("stderr") or r.get("error")))
        return
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


def writable(path):
    for root, dirs, files in os.walk(path):
        for n in dirs + files:
            p = os.path.join(root, n)
            os.chmod(p, os.stat(p).st_mode | stat.S_IWRITE)


def copytree(src, dst):
    if WINDOWS:
        shutil.copytree(src, dst)
        writable(dst)
        return
    subprocess.run(["cp", "-RL", src, dst], check=True)
    subprocess.run(["chmod", "-R", "u+w", dst], check=True)


def rmtree(path):
    if WINDOWS:
        writable(path)
        shutil.rmtree(path)
        return
    subprocess.run(["chmod", "-R", "u+w", path], check=False)
    subprocess.run(["rm", "-rf", path], check=True)


def authority():
    return state().get("authority", "electrum")


# The local node's run adds bitcoind_module and its app to the same Basecamp.
def builds():
    local = authority() == "local"
    return MODULE_BUILDS + (["bitcoind"] if local else []), PLUGIN_BUILDS + (["bitcoindui"] if local else [])


def layout(user, mode=None):
    if mode:
        if mode not in AUTHORITIES:
            raise Fail("authority is one of %s" % ", ".join(AUTHORITIES))
        save(authority=mode)
    ud = userdir(user)
    if os.path.exists(os.path.join(E2E, user)):
        rmtree(os.path.join(E2E, user))
    os.makedirs(os.path.join(ud, "modules"))
    os.makedirs(os.path.join(ud, "plugins"))
    os.makedirs(home(user))
    module_builds, plugin_builds = builds()
    for b in module_builds:
        for m in sorted(os.listdir(os.path.join(BUILD, b, "modules"))):
            copytree(os.path.join(BUILD, b, "modules", m), os.path.join(ud, "modules", m))
    for b in plugin_builds:
        for m in sorted(os.listdir(os.path.join(BUILD, b, "plugins"))):
            copytree(os.path.join(BUILD, b, "plugins", m), os.path.join(ud, "plugins", m))
    # regtest.json turns regtest on for the backend and the node module, and gives the core its servers.
    core = esplora_regtest() if authority() == "kyoto-esplora" else AUTHORITIES[authority()][0]
    cfg = {"bitcoin_wallet_backend": {}, "bitcoin_node_module": {}, "bitcoin_wallet_core_module": core}
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
    passed("laid out %s for %s: %d modules and %d apps, portable, with regtest.json for the wallet's modules"
           % (user, authority(), len(os.listdir(os.path.join(ud, "modules"))), len(os.listdir(os.path.join(ud, "plugins")))))


# Esplora alone serves history, and a checkpoint sits just above the first two payments: for a wallet
# whose birthday is above it, Esplora reports them below the chain's start, where nothing checks them.
def esplora_regtest():
    if CHAIN_URL:
        raise Fail("the chain host runs no Esplora: this step runs on Linux and macOS")
    base = int(state()["coinbase_height"]) + 1
    header = rpc("getblockheader", [rpc("getblockhash", [base]), False])
    log(chain("esplora"))
    save(unchecked_base=base)
    return {"esplora": [ESPLORA_URL], "kyoto": FILTER_PEERS, "kyotoRequired": 2, "pollSecs": 1,
            "checkpoint": {"height": base, "header": header}}


def descendants(pid):
    kids = {}
    if WINDOWS:
        for child, parent in _processes():
            kids.setdefault(parent, []).append(child)
    else:
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], capture_output=True, text=True).stdout
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                kids.setdefault(int(parts[1]), []).append(int(parts[0]))
    found, todo = [], [pid]
    while todo:
        parent = todo.pop()
        for k in kids.get(parent, []):
            # Windows reuses PIDs and keeps a dead parent's: a child is never older than its parent.
            if WINDOWS and not (_created(k) or 0) >= (_created(parent) or 0) > 0:
                continue
            found.append(k)
            todo.append(k)
    return found


def command_of(pid):
    if WINDOWS:
        h = _open(pid)
        if not h:
            return ""
        buf, size = ctypes.create_unicode_buffer(1024), wintypes.DWORD(1024)
        ok = _K32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
        _K32.CloseHandle(h)
        return buf.value if ok else ""
    return subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()


def launch(user):
    if listening(PORT):
        raise Fail("port %d is held by another process; the driver would talk to it" % PORT)
    env = dict(os.environ, HOME=home(user), USERPROFILE=home(user), LOGOS_NO_SCHEME_REGISTER="1",
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QML_INSPECTOR_PORT=str(PORT),
               QT_FORCE_STDERR_LOGGING="1")
    logf = open(os.path.join(E2E, "basecamp-%s.log" % user), "ab")
    detach = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if WINDOWS else {"start_new_session": True}
    p = subprocess.Popen([BASECAMP, "--user-dir", userdir(user)], env=env, cwd=WORK, stdin=subprocess.DEVNULL,
                         stdout=logf, stderr=subprocess.STDOUT, **detach)
    with open(os.path.join(E2E, "basecamp.pid"), "w") as f:
        # On Windows the creation time too: a later run must not stop a process that took the PID.
        f.write("%d %s %s" % (p.pid, user, _created(p.pid) if WINDOWS else ""))
    ins = Inspector()
    ins.connect(timeout=180)
    apps = [APP, KEYS, SIGNER] + (["bitcoind_ui"] if authority() == "local" else [])
    for m in apps:
        ins.wait("sidebar.app." + m, "visible", True, 120)
    names = {m: ins.get("sidebar.app." + m, "text") for m in apps}
    passed("Basecamp is up for %s (pid %d) with the apps %s" % (user, p.pid, ", ".join(map(str, names.values()))))


def stop_basecamp():
    f = os.path.join(E2E, "basecamp.pid")
    if not os.path.exists(f):
        log("no Basecamp of this run is running")
        return
    fields = open(f).read().split()
    pid = int(fields[0])
    if WINDOWS and len(fields) > 2 and str(_created(pid)) != fields[2]:
        log("pid %d is no longer this run's Basecamp" % pid)
        os.remove(f)
        return
    bundle = os.path.normcase(os.path.dirname(os.path.realpath(BASECAMP)))
    work = os.path.normcase(WORK)
    tree = [k for k in descendants(pid) if bundle in os.path.normcase(command_of(k)) or work in os.path.normcase(command_of(k))]
    if alive(pid):
        stop_pid(pid, 30)
    if WINDOWS:
        for k in tree:
            if alive(k):
                stop_pid(k, 10)
    else:
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
    want = "Local chain · block {:,} · {}".format(h, AUTHORITIES[authority()][1])
    line = ins.wait("syncLine", "text", lambda t: (t or "").startswith(want), timeout, "the app reads the chain at block %d (%s)" % (h, want))
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
    servers = {"electrum": 2, "kyoto": 1, "local": 0}[authority()]
    lines = ["electrum-%d %s" % (i, ins.wait("walletSourceState_electrum-%d" % i, "text", lambda t: t.startswith("ok"), 30))
             for i in range(servers)]
    for i in range(servers):
        expect(ins.get("suspectBadge_electrum-%d" % i, "visible") is not True, "electrum-%d is not suspect %s" % (i, when))
    badge = ins.wait("healthBadge", "text", "Sources OK", 30) if servers else str(ins.get("healthBadge", "text"))
    ins.shot("sources-" + when.replace(" ", "-"))
    wallet_tab(ins, 3)
    passed("%s: %s%s" % (when, badge, "".join("; " + l for l in lines)))


def payee(label):
    return rpc("getnewaddress", [label, "bech32"], "miner")


def history_count(ins):
    return int(ins.get("historyList", "count"))


# ---- phases ----

def phase_prepare_chain():
    if CHAIN_URL:
        r = chainctl("/fresh")
        if r.get("code") != 0:
            raise Fail("chainctl /fresh: %s %s" % (r.get("stdout"), r.get("stderr") or r.get("error")))
        out = r.get("stdout", "").strip()
        want = "electrum: " + ",".join("tcp://%s:%d" % (CHAIN_HOST, p) for p in ELECTRUM_PORTS)
        if chain("electrum") != want:
            raise Fail("the chain host serves %r, not drive.py's %r: run it with drive.py's ports" % (chain("electrum"), want))
    else:
        chain("stop", check=False)
        subprocess.run(["rm", "-rf", CHAIN_DIR], check=True)
        out = chain("prepare")
    log(out)
    expect(height() >= 101, "a fresh regtest chain at block %d: three nodes serving block filters (main, fork, follower) "
                            "and two electrs on %s" % (height(), ELECTRUM_PORTS))


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
    if authority() == "kyoto":
        # Kyoto's peers serve blocks and filters, no mempool: the payment shows once it is in a block.
        time.sleep(3)
        expect(ins.get("pendingRow", "visible") is not True, "Kyoto has no mempool view: nothing pending before the block")
    else:
        ins.wait("pendingRow", "visible", True, 60, "an unconfirmed payment shows as pending")
        expect(ins.get("pendingRowAmount", "text") == "1 BTC", "pending: 1 BTC, not in the confirmed balance")
        ins.shot("receive-pending")
    receive_height = mine(1)
    ins.wait("confirmedCard", "value", "1 BTC", 60, "mined: 1 BTC confirmed")
    ins.wait("pendingRow", "visible", False, 30)
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", txid, "1 confirmation")
    expect(row_text(ins, "historyIntent", txid) == "+1 BTC", "Activity lists +1 BTC, 1 confirmation")
    # A block mined to a fresh address: immature until 100 confirmations.
    wallet_tab(ins, 2)
    ins.press("newAddressButton")
    addr2 = ins.wait("receiveAddress", "text", lambda t: t.startswith("bcrt1q") and t != addr, 30)
    coinbase_height = mine(1, addr2)
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
    if ins.get("alertBanner", "visible") is True:
        log("NOTE after 100 blocks at once, alertBanner: %s — %s" % (ins.get("alertBanner", "title"), ins.get("alertBanner", "message")))
    save(receive_txid=txid, coinbase_txid=coinbase, balance_sat=total, receive_height=receive_height, coinbase_height=coinbase_height)
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
    ins.press("details_" + txid)
    paid = ins.wait("historyPaid_" + txid, "text", lambda t: to in (t or ""), 20, "Details list the address paid")
    passed("Details list the address paid (%s) and the txid" % paid.strip())
    save(send1_txid=txid, send1_to=to)
    log("PHASE send-expire OK")


def phase_send():
    ins = Inspector()
    show_app(ins, APP)
    wait_synced(ins)
    to = payee("payee-1")
    fill_send(ins, to, "0.1", 2)
    approve_in_app(ins)
    chooser(ins, SIGNER)
    lines = signer_shows(ins, ["Send 0.10000000 BTC to " + to])
    log("signer: " + " | ".join(l.strip() for l in lines))
    signer_approve(ins, secret("password"))
    back_to_wallet(ins, SIGNER)
    wait_send(ins, "Sent", 120)
    txid = re.search(r"[0-9a-f]{64}", ins.wait("sendTxid", "text", lambda t: bool(re.search(r"[0-9a-f]{64}", t or "")), 30)).group(0)
    passed("the app says: " + str(ins.get("sendVia", "text")))
    ins.press("doneSendButton")
    end = time.time() + 40
    while txid not in rpc("getrawmempool"):
        if time.time() > end:
            raise Fail("the send never reached the chain's main node: %s" % txid)
        time.sleep(0.5)
    passed("the send reached the main node's mempool: %s" % txid)
    mine(1)
    wallet_tab(ins, 3)
    wait_row(ins, "historyState", txid, "1 confirmation", 90)
    passed("Activity shows the send confirmed: %s" % row_text(ins, "historyIntent", txid))
    save(send1_txid=txid, send1_to=to)
    log("PHASE send OK")


# A combo box as a person uses it: opened by a click, its item clicked; a signal by hand otherwise.
def select_combo(ins, name, value, index):
    oid, _ = ins.wait_obj(name, lambda p: p.get("visible") is True and p.get("enabled") is not False, 30, name)
    ins.rpc("click", objectId=oid)
    end = time.time() + 8
    while time.time() < end:
        # The open popup's entry: its text, drawn inside the item delegate that takes the click.
        for m in ins.rpc("findByProperty", property="text", value=value).get("matches", []):
            try:
                p = ins.props(m["id"])
            except InspectorError:
                continue
            if p.get("visible") is True and m["id"] != oid:
                ins.rpc("click", objectId=m["id"])
                return "clicked"
        time.sleep(0.3)
    ins.rpc("evaluate", objectId=oid, expression="activated(%d)" % index)
    return "activated"


def phase_node_start():
    ins = Inspector()
    show_app(ins, "bitcoind_ui")
    ins.wait("bitcoindRoot", "ready", True, 120, "the node app's backend connects")
    ins.wait("stateBadge", "text", "stopped", 60)
    how = select_combo(ins, "networkCombo", "regtest", 3)
    ins.wait("bitcoindRoot", "net", "regtest", 20, "the node app switches to regtest")
    passed("the node app is on regtest (%s)" % how)
    ins.wait("settingsForm", "visible", True, 30, "regtest's settings are read")
    # The chain's main node as a peer of its own: the local node follows that chain.
    ins.set_text("addNodesField", FILTER_PEERS[0])
    ins.press("saveButton")
    ins.wait("addNodesField", "text", FILTER_PEERS[0], 20)
    ins.press("startButton")
    ins.wait("stateBadge", "text", "running", 180, "the local node runs")
    h = height()
    ins.wait("bitcoindRoot", "blocks", lambda b: b is not None and float(b) >= h, 180, "the local node syncs to block %d" % h)
    ins.wait("bitcoindRoot", "synced", True, 60, "the node app calls it synced")
    ins.shot("node-running")
    passed("bitcoind_module runs regtest from the node app, at block %d with %s" % (h, ins.get("peersText", "text")))
    log("PHASE node-start OK")


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
    ins.shot("speed-up-replaced")
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
    ins.shot("rejected")
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
    wait_row(ins, "historyState", txid, "1 confirmation", 90)
    old_tip = rpc("getbestblockhash")
    balance = confirmed_value(ins)
    sources_ok(ins, "before the reorg")
    # While the chain's clock runs ahead of its host's, the fork re-mines the invalidated block byte
    # for byte and bitcoind refuses it: wait until the node's clock passes the tip.
    tip_time, t0 = rpc("getblockheader", [old_tip])["time"], time.time()
    while time.time() < t0 + 90:
        t = rpc("getblocktemplate", [{"rules": ["segwit"]}])
        if t["curtime"] > max(t["mintime"], tip_time):
            break
        time.sleep(1)
    if time.time() - t0 > 1:
        log("NOTE waited %d s for the node's clock to pass the tip's" % (time.time() - t0))
    # Only what the reorg raises counts: an earlier alert is noted and dismissed first.
    for banner in ("alertBanner", "authoritySuspectBanner"):
        if ins.get(banner, "visible") is True:
            log("NOTE before the reorg, %s: %s — %s" % (banner, ins.get(banner, "title"), ins.get(banner, "message")))
            ins.press("dismissAlertsButton" if banner == "alertBanner" else "dismissAuthorityAlertButton")
            ins.wait(banner, "visible", False, 10)
    out = chain("reorg", "1")
    log(out)
    new_block = rpc("getblockhash", [h])
    expect(new_block != old_tip and height() == h + 1, "the node took a fork that replaced block %d" % h)
    expect(txid in rpc("getblock", [new_block])["tx"], "the replacing block holds the same payment")
    tip_line = "Local chain · block {:,}".format(h + 1)
    seen, end, alert = [], time.time() + 60, False
    while time.time() < end:
        st = row_text(ins, "historyState", txid, timeout=5)
        line = ins.get("syncLine", "text")
        moved = ins.get("historyReanchored_" + txid, "visible") is True
        if not seen or seen[-1] != (st, line, moved):
            seen.append((st, line, moved))
        alert = alert or ins.get("alertBanner", "visible") is True or ins.get("authoritySuspectBanner", "visible") is True
        if st == "2 confirmations" and str(line).startswith(tip_line) and moved and time.time() > end - 40:
            break
        time.sleep(0.5)
    log("re-anchoring as the app showed it: " + " -> ".join("%s / %s%s" % (a, b, " / re-anchored" if c else "") for a, b, c in seen))
    expect(seen[-1][0] == "2 confirmations" and str(seen[-1][1]).startswith(tip_line),
           "the payment confirms again in the new block: 2 confirmations at block %d" % (h + 1))
    note = ins.wait("historyReanchored_" + txid, "text", "re-anchored at height {:,}".format(h), 30, "Activity says it moved")
    passed("Activity: " + note)
    ins.press("details_" + txid)
    block = ins.wait("historyBlock_" + txid, "text", lambda t: new_block in (t or ""), 20, "the details name the new block")
    passed("details: " + block)
    ins.shot("reorg-reanchored")
    expect(not alert, "no alert during the reorg: neither a source's nor Kyoto's")
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


def yesterday():
    return (datetime.date.today() - datetime.timedelta(days=1)).isoformat()


# The open's request in the keys app: the written-down phrase restored, a day given or left empty.
def restore_in_keys(ins, name, birthday=None):
    chooser(ins, KEYS)
    ins.wait("accessSheet", "opened", True, 120)
    ins.press("accessAddWallet")
    ins.wait("bitcoinImportSheet", "opened", True, 20)
    ins.check("btcSourceType")
    ins.set_text("btcPhraseField", secret("phrase"))
    if birthday:
        ins.set_text("btcBirthdayField", birthday)
    ins.set_text("btcWalletPasswordField", secret("password-restore"))
    ins.set_text("btcWalletNameField", name)
    ins.press("btcConfirm")
    ins.wait("bitcoinImportSheet", "visible", False, 30)
    ins.wait("accessWallet_0", "checked", True, 20)
    ins.set_text("accessPasswordField", secret("password-restore"))
    ins.press("accessApproveButton")
    ins.wait("accessSheet", "visible", False, 30)
    back_to_wallet(ins, KEYS)
    ins.wait(ROOT, "walletState", lambda v: v in ("syncing", "ready"), 90)


# The first user dir's balance and rows, read again in this one.
def matches_snapshot(ins, what):
    want = state()["snapshot"]
    ins.wait("confirmedCard", "value", want["confirmed"], 180, "%s: the balance matches, %s" % (what, want["confirmed"]))
    passed("the %s balance matches: %s" % (what, want["confirmed"]))
    got = snapshot(ins)
    log("%s: %s" % (what, json.dumps(got)))
    # A replaced send never reached a block, so only the first user dir can list it.
    log("Activity rows: %d in user A, %d %s" % (want["count"], got["count"], what))
    for t, row in want["rows"].items():
        g = got["rows"].get(t)
        expect(g is not None and g["state"] == row["state"], "%s… %s in both" % (t[:12], row["state"]))
    return got


def open_for_restore(ins):
    ins.wait(ROOT, "ready", True, 120)
    ins.wait("statusLine", "text", "No wallet open", 120)
    ins.call(ROOT, "selectNetwork", "regtest")
    ins.wait("networkChip", "text", "regtest", 30)
    ins.press("familySegwit")


def phase_restore():
    ins = Inspector()
    show_app(ins, APP)
    open_for_restore(ins)
    ins.press("openWalletButton")
    birthday = yesterday()
    restore_in_keys(ins, "E2E restored", birthday)
    passed("restored in the keys app from the written-down phrase, birthday %s" % birthday)
    wait_synced(ins, 180)
    got = matches_snapshot(ins, "restored")
    ins.shot("restored")
    save(restored=got)
    log("PHASE restore OK")


# No day in the keys app: the wallet asks for its birthday, and one is set in the wallet app.
def phase_restore_birthday():
    ins = Inspector()
    show_app(ins, APP)
    open_for_restore(ins)
    ins.press("openWalletButton")
    restore_in_keys(ins, "E2E restored, no day")
    passed("restored in the keys app with no day given")
    ins.wait("needsBirthdayHomeNotice", "visible", True, 120, "restored without a birthday: Home asks for one")
    passed("Home asks: %s" % ins.get("needsBirthdayHomeNotice", "title"))
    ins.shot("needs-birthday")
    ins.press("setBirthdayButton")
    ins.wait("birthdaySheet", "opened", True, 20)
    day = yesterday()
    ins.set_text("birthdayDateField", day)
    ins.press("confirmBirthdayButton")
    ins.wait("birthdaySheet", "visible", False, 60, "the wallet takes the birthday %s" % day)
    ins.wait("needsBirthdayHomeNotice", "visible", False, 30, "nobody asks for a birthday any more")
    ins.wait("rescanPane", "visible", False, 300, "the rescan from it ends")
    passed("birthday %s set in the wallet app, scanned again from it" % day)
    wait_synced(ins, 180)
    got = matches_snapshot(ins, "restored")
    ins.shot("restored-birthday")
    save(restored_birthday=got)
    log("PHASE restore-birthday OK")


# Esplora reports the first two payments below the chain's start (esplora_regtest): unchecked, apart
# from the balance, until an earlier birthday, set from the banner, lets Kyoto check them.
def phase_unchecked():
    s = state()
    base = int(s["unchecked_base"])
    ins = Inspector()
    show_app(ins, APP)
    open_for_restore(ins)
    # The app takes no block height, and a regtest day names none: open_wallet's own birthday, above the checkpoint.
    root = ins.obj(ROOT)
    ins.rpc("evaluate", objectId=root[0], expression='openWallet({ family: "bitcoin", birthday: %d })' % (base + 1))
    restore_in_keys(ins, "E2E unchecked")
    passed("restored with a birthday at block %d, above the checkpoint at %d" % (base + 1, base))
    wait_synced(ins, 180)
    wallet_tab(ins, 4)
    ins.wait("walletChainBase", "text", "block {:,}".format(base), 30, "the chain's start in Settings")
    passed("the wallet's chain starts at the checkpoint, block %d" % base)
    wallet_tab(ins, 0)
    want = amount_text(int(s["balance_sat"])) + " BTC"
    ins.wait("uncheckedRowAmount", "text", want, 120, "the unchecked amount on Home")
    passed("Home: %s reported, not checked, apart from the balance (confirmed %s)" % (want, confirmed_value(ins)))
    ins.wait("uncheckedBanner", "visible", True, 60, "the unchecked_anchor alert has a banner of its own")
    passed("the banner: %s — %s" % (ins.get("uncheckedBanner", "title"), ins.get("uncheckedBanner", "message")))
    ins.shot("unchecked-home")
    wallet_tab(ins, 3)
    for key in ("receive_txid", "coinbase_txid"):
        wait_row(ins, "historyState", s[key], "Reported by esplora-0, not checked", 60)
        passed("%s… reads Reported by esplora-0, not checked" % s[key][:12])
    ins.shot("unchecked-activity")
    wallet_tab(ins, 0)
    ins.press("uncheckedBirthdayButton")
    ins.wait("birthdaySheet", "opened", True, 20)
    ins.check("birthdayUnknown")
    ins.press("confirmBirthdayButton")
    ins.wait("birthdaySheet", "visible", False, 60, "an earlier birthday, set from the banner")
    ins.wait("uncheckedRow", "visible", False, 300, "the chain starts lower, and Kyoto checks them")
    ins.wait("uncheckedBanner", "visible", False, 30, "the banner goes once nothing is unchecked")
    passed("an earlier birthday from the banner: nothing unchecked any more")
    wallet_tab(ins, 4)
    ins.wait("walletChainBase", "text", "block 0", 60, "the chain's start in Settings")
    passed("the chain starts at genesis now")
    wallet_tab(ins, 0)
    wait_synced(ins, 180)
    got = matches_snapshot(ins, "checked")
    ins.shot("unchecked-checked")
    save(unchecked=got)
    log("PHASE unchecked OK")


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
    passed("the app says: " + ins.wait("sendVia", "text", lambda t: t.startswith("Last tried: electrum-"), 20))
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
    "node-start": phase_node_start, "send": phase_send,
    "receive": phase_receive, "send-expire": phase_send_expire, "speed-up": phase_speed_up,
    "reject": phase_reject, "reorg": phase_reorg, "close": phase_close, "restore": phase_restore,
    "restore-birthday": phase_restore_birthday, "unchecked": phase_unchecked,
    "unknown-rebroadcast": phase_unknown_rebroadcast, "unknown-forget": phase_unknown_forget,
    "stop": stop_basecamp, "cleanup": phase_cleanup,
}


def main(argv):
    if len(argv) >= 2 and argv[0] in ("layout", "launch"):
        fn, args = {"layout": layout, "launch": launch}[argv[0]], argv[1:]
    elif len(argv) == 1 and argv[0] in PHASES:
        fn, args = PHASES[argv[0]], []
    else:
        sys.exit("usage: drive.py layout <user> [%s] | launch <user> | %s" % ("|".join(AUTHORITIES), " | ".join(PHASES)))
    log("== %s %s" % (time.strftime("%H:%M:%S"), " ".join(argv)))
    try:
        fn(*args)
    except (Fail, InspectorError) as e:
        log("FAIL %s: %s" % (argv[0], e))
        try:
            Inspector().shot("fail-" + argv[0])
        except Exception:
            pass
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
