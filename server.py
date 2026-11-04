"""Local test server: serves public/ and exposes psa_bridge over HTTP, standing in for the QML user interface.

Usage: .venv/bin/python server.py (port 3000, or set PORT).
"""
import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import psa_bridge

ROOT = Path(__file__).resolve().parent
STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
}

# POST /api/vehicles/<vin>/<command> with an optional JSON body {"on": true|false}.
COMMANDS = {
    "wakeup": lambda vin, on: psa_bridge.wakeup(vin),
    "preconditioning": psa_bridge.preconditioning,
    "charge": psa_bridge.charge_now,
    "lights": lambda vin, on: psa_bridge.lights(vin),
    "lock": psa_bridge.lock_door,
}

logger = logging.getLogger("server")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def _handle(self, method: str) -> None:
        url = urlsplit(self.path)
        try:
            self._route(method, url.path, url.query)
        except Exception as error:  # noqa: BLE001 - every failure goes back to the page as text
            logger.exception("%s %s failed", method, url.path)
            self._send(500, "text/plain; charset=utf-8", str(error).encode())

    def _route(self, method: str, path: str, query: str) -> None:
        match (method, path):
            case ("GET", _) if path in STATIC_FILES:
                file, content_type = STATIC_FILES[path]
                self._send(200, content_type, (ROOT / "public" / file).read_bytes())
            case ("GET", "/api/session"):
                self._send_json(psa_bridge.get_session())
            case ("POST", "/api/login/start"):
                self._send_json({"url": psa_bridge.start_login()})
            case ("GET", "/callback"):
                psa_bridge.finish_login(parse_qs(query).get("code", [""])[0])
                self.send_response(302)
                self.send_header("Location", "/")
                self.end_headers()
            case ("POST", "/api/logout"):
                psa_bridge.logout()
                self._send_json({"connected": False})
            case ("GET", "/api/vehicles"):
                self._send_json(psa_bridge.get_vehicles())
            case ("GET", _) if path.startswith("/api/vehicles/") and path.endswith("/status"):
                self._send_json(psa_bridge.get_status(path.split("/")[3]))
            case ("GET", _) if path.startswith("/api/psa/"):
                self._send_json(psa_bridge.api_get(path.removeprefix("/api/psa") + (f"?{query}" if query else "")))
            case ("POST", "/api/remote/sms"):
                psa_bridge.request_sms()
                self._send_json({"sent": True})
            case ("POST", "/api/remote/activate"):
                body = self._read_json()
                psa_bridge.activate_remote(str(body.get("smsCode", "")), str(body.get("pin", "")))
                self._send_json({"activated": True})
            case ("GET", "/api/remote/messages"):
                self._send_json(psa_bridge.get_remote_messages(int(parse_qs(query).get("since", ["0"])[0])))
            case ("POST", _) if path.startswith("/api/vehicles/") and path.count("/") == 4:
                vin, command = path.split("/")[3:]
                COMMANDS[command](vin, bool(self._read_json().get("on", True)))
                self._send_json({"sent": command})
            case _:
                self._send(404, "text/plain; charset=utf-8", f"Unknown route: {method} {path}".encode())

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length)) if length > 0 else {}

    def _send(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, value) -> None:
        self._send(200, "application/json; charset=utf-8", json.dumps(value, default=str).encode())


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    # Logs every outgoing call to PSA (method, path and status).
    logging.getLogger("urllib3.connectionpool").setLevel(logging.DEBUG)
    psa_bridge.init(str(ROOT / "data"))
    port = int(os.environ.get("PORT", "3000"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    logger.info("PSA proeftuin: http://localhost:%s", port)
    server.serve_forever()


if __name__ == "__main__":
    main()
