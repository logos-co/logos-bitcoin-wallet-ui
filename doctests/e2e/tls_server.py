#!/usr/bin/env python3
# A TLS listener with a self-signed certificate, for the node module's probe to read and the app to
# pin: tls_server.py <dir with cert.pem and key.pem> <port>. Detaches, writes <dir>/server.pid, exits in 30 min.
import os
import signal
import socket
import ssl
import sys


def main(folder, port):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.path.join(folder, "cert.pem"), os.path.join(folder, "key.pem"))
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(8)
    if os.fork():
        os._exit(0)
    os.setsid()
    with open(os.path.join(folder, "server.pid"), "w") as f:
        f.write(str(os.getpid()))
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    signal.alarm(1800)
    while True:
        conn, _ = srv.accept()
        try:
            conn.settimeout(10)
            tls = ctx.wrap_socket(conn, server_side=True)
            # Any Electrum request gets an error: the probe is after the certificate.
            if tls.recv(4096):
                tls.sendall(b'{"jsonrpc":"2.0","id":0,"error":{"code":-32601,"message":"test server"}}\n')
        except (OSError, ssl.SSLError):
            pass
        finally:
            conn.close()


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
