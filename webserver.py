from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return

        body = Path('/root/metrics.txt').read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        # No access log: Prometheus scrapes every few seconds and would flood the container log
        pass

def main():
    print("Server starting...")
    ThreadingHTTPServer(("", 9300), MetricsHandler).serve_forever()

main()
