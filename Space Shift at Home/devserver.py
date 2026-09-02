#!/usr/bin/env python3
"""Local dev server for Space Shift at Home (the browser-based web port).

Serves the repo root (so relative fetches to ../Synesthesia/... resolve)
with Cache-Control: no-store on every response. Plain `python3 -m
http.server` lets browsers cache the JS modules across reloads with no way
to bust it short of a hard-refresh, which silently serves stale code while
iterating - this avoids that entirely.

Usage: python3 "Space Shift at Home/devserver.py" [port]   (default port 8000)
"""
import http.server
import os
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(repo_root)
    http.server.test(HandlerClass=NoCacheHandler, port=port)
