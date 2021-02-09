import simple_http_server.server as server

from simple_http_server import request_map
from pathlib import Path

@request_map("/metrics")
def metrics():
    return Path('/root/metrics.txt').read_text()

def main(*args):
    print("Server starting...")
    server.start(port=9300)
    print("Server started!")

main()
