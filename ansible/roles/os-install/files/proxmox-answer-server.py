"""Serve Proxmox automated-installer answer files by MAC address.

The installer POSTs its system information as JSON to /answer. The answer
directory holds one <host>_<mac>.toml file per host; the first file whose MAC
matches one of the posted network interfaces is returned unchanged. Unknown
machines get a 404, which aborts the install with the response body shown.

Replaces slothcroissant/proxmox-auto-installer-server.
Protocol: https://pve.proxmox.com/wiki/Automated_Installation
"""

import json
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ANSWER_DIR = pathlib.Path("/app/answers")
MAX_BODY = 1024 * 1024
PORT = 8000


def answers_by_mac():
    return {
        path.stem.rsplit("_", 1)[-1].lower(): path for path in ANSWER_DIR.glob("*.toml")
    }


class AnswerHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/answer":
            self.reply(404, "text/plain", b"Not found\n")
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            if not 0 <= length <= MAX_BODY:
                self.reply(413, "text/plain", b"Request body too large\n")
                return
            info = json.loads(self.rfile.read(length))
            interfaces = info.get("network_interfaces", [])
            macs = [nic["mac"].lower() for nic in interfaces if "mac" in nic]
        except (ValueError, AttributeError, TypeError) as e:
            self.reply(400, "text/plain", f"Invalid request: {e}\n".encode())
            return

        answers = answers_by_mac()
        for mac in macs:
            if mac in answers:
                self.log_message("serving %s for %s", answers[mac].name, mac)
                self.reply(200, "application/toml", answers[mac].read_bytes())
                return

        self.log_message("no answer file for %s", ", ".join(macs) or "no MACs")
        self.reply(
            404, "text/plain", f"No answer file for {', '.join(macs)}\n".encode()
        )

    def reply(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    if not ANSWER_DIR.is_dir():
        sys.exit(f"Answer directory {ANSWER_DIR} does not exist")
    ThreadingHTTPServer(("0.0.0.0", PORT), AnswerHandler).serve_forever()
