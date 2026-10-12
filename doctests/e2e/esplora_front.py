#!/usr/bin/env python3
# An Esplora front that answers no block header, so anchors below the chain's start stay unchecked:
# esplora_front.py <port> <upstream url> <pid file>. Detaches; exits in an hour.
import http.server
import os
import re
import signal
import sys
import urllib.error
import urllib.request

HEADER = re.compile(r"^/block/[0-9a-f]{64}/header$")


def handler(upstream):
    class Front(http.server.BaseHTTPRequestHandler):
        def relay(self, body=None):
            if HEADER.match(self.path.split("?")[0]):
                self.answer(404, b"this front serves no headers", "text/plain")
                return
            req = urllib.request.Request(upstream + self.path, data=body, method=self.command)
            if self.headers.get("Content-Type"):
                req.add_header("Content-Type", self.headers["Content-Type"])
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    self.answer(r.status, r.read(), r.headers.get("Content-Type", "text/plain"))
            except urllib.error.HTTPError as e:
                self.answer(e.code, e.read(), e.headers.get("Content-Type", "text/plain"))
            except OSError as e:
                self.answer(502, str(e).encode(), "text/plain")

        def answer(self, code, body, kind):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self.relay()

        def do_POST(self):
            self.relay(self.rfile.read(int(self.headers.get("Content-Length") or 0)))

        def log_message(self, *args):
            pass

    return Front


def main(port, upstream, pidfile):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler(upstream.rstrip("/")))
    if os.fork():
        os._exit(0)
    os.setsid()
    with open(pidfile, "w") as f:
        f.write(str(os.getpid()))
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    signal.alarm(3600)
    srv.serve_forever()


if __name__ == "__main__":
    main(int(sys.argv[1]), sys.argv[2], sys.argv[3])
