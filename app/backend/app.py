import json
import os
import socket
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({
            "service": "backend",
            "pod": socket.gethostname(),
            "color": os.getenv("APP_COLOR", "none"),
            "api_key_set": bool(os.getenv("API_KEY")),
            "time": datetime.now().isoformat(timespec="seconds"),
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 5000), Handler).serve_forever()
