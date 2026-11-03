#!/usr/bin/env python3
# An Electrum front that serves no header range below a checkpoint, so anchors below the chain's start
# stay unchecked: electrum_front.py <port> <upstream host:port> <checkpoint> <pid file>. Detaches; exits
# in an hour. Line-based JSON-RPC, rewritten as the core's own test proxy does (tests/restore.rs).
import json
import os
import signal
import socket
import sys
import threading


def close(*socks):
    for s in socks:
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        s.close()


def serve(client, upstream, below):
    try:
        up = socket.create_connection(upstream, timeout=30)
        up.settimeout(None)
    except OSError:
        close(client)
        return
    asked, lock = {}, threading.Lock()

    def requests():
        try:
            for line in client.makefile("rb"):
                try:
                    v = json.loads(line)
                    if isinstance(v, dict) and v.get("id") is not None:
                        with lock:
                            asked[v["id"]] = (v.get("method"), v.get("params") or [])
                except ValueError:
                    pass
                up.sendall(line if line.endswith(b"\n") else line + b"\n")
        except OSError:
            pass
        close(up)

    threading.Thread(target=requests, daemon=True).start()
    try:
        for line in up.makefile("rb"):
            try:
                v = json.loads(line)
            except ValueError:
                v = None
            if isinstance(v, dict) and v.get("id") is not None:
                with lock:
                    method, params = asked.pop(v["id"], (None, []))
                start = params[0] if isinstance(params, list) and params else None
                if method == "blockchain.block.headers" and isinstance(start, int) and start < below:
                    v.pop("result", None)
                    v["error"] = {"code": 1, "message": "no headers below the checkpoint"}
                    line = (json.dumps(v) + "\n").encode()
            client.sendall(line)
    except OSError:
        pass
    close(client, up)


def main(port, upstream, below, pidfile):
    host, _, p = upstream.rpartition(":")
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(16)
    if os.fork():
        os._exit(0)
    os.setsid()
    with open(pidfile, "w") as f:
        f.write(str(os.getpid()))
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    signal.alarm(3600)
    while True:
        client, _ = srv.accept()
        threading.Thread(target=serve, args=(client, (host, int(p)), below), daemon=True).start()


if __name__ == "__main__":
    main(int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4])
