#!/usr/bin/env python3
"""Minimal in-container HTTP wrapper around the shell health probe."""

import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HEALTH_HOST = os.environ.get("HEALTHCHECK_HOST", "0.0.0.0")
HEALTH_PORT = int(os.environ.get("HEALTHCHECK_PORT", "8080"))
PROBE_SCRIPT = os.environ.get("HEALTHCHECK_PROBE_SCRIPT", "/home/pok/scripts/health_probe.sh")
PROBE_TIMEOUT = float(os.environ.get("HEALTHCHECK_PROBE_TIMEOUT", "10"))


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/healthz", "/healthz/"):
            self._send_response(404, "not found\n")
            return

        try:
            result = subprocess.run(
                [PROBE_SCRIPT],
                capture_output=True,
                text=True,
                timeout=PROBE_TIMEOUT,
                check=False,
            )
            body = (result.stdout or result.stderr or "").strip()
            if not body:
                body = "ok" if result.returncode == 0 else "unhealthy"
            self._send_response(200 if result.returncode == 0 else 503, f"{body}\n")
        except subprocess.TimeoutExpired:
            self._send_response(503, "unhealthy: probe timeout\n")
        except OSError as exc:
            self._send_response(503, f"unhealthy: {exc}\n")

    def log_message(self, fmt, *args):
        return

    def _send_response(self, status_code, body):
        encoded = body.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main():
    server = ThreadingHTTPServer((HEALTH_HOST, HEALTH_PORT), HealthHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
