#!/usr/bin/env python3
"""Download the voice model for real from a local server, on macOS: the production SGSingModel.m in a
background URL session, a corrupted file rejected, a cancel resumed, an install, a download picked up by
the next process, and removal. The model's files are served from a folder that holds them at their paths
(stage_model.py's output, or separator.mlmodelc itself); nothing is uploaded or fetched from the internet.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
from urllib.parse import parse_qs, urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path, help="a folder with the model's files at their paths")
args = parser.parse_args()
root = args.model.resolve()
here = Path(__file__).resolve().parent
src = here.parent.parent / "tweak/Sources"
WEIGHTS, GRAPH = "weights/weight.bin", "model.mil"


class Server:
    corrupt = False   # the graph is served with its last byte changed
    throttle = 0      # bytes per second for the weights, 0 for as fast as it goes
    offset = None     # where the last request for the weights started
    requests = 0      # requests for the weights


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *arguments):
        pass

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            pass   # a connection the client let go of

    def answer(self, status, body, kind="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/control":
            query = parse_qs(url.query)
            if "corrupt" in query:
                Server.corrupt = query["corrupt"][0] == "1"
            if "throttle" in query:
                Server.throttle = int(query["throttle"][0])
            if "reset" in query:
                Server.offset, Server.requests = None, 0
            self.answer(200, json.dumps({WEIGHTS: Server.offset, "requests": Server.requests}).encode())
            return
        name = url.path.lstrip("/")
        path = (root / name).resolve()
        if root not in path.parents or not path.is_file():
            self.answer(404, b"not found", "text/plain")
            return
        size, modified = path.stat().st_size, int(path.stat().st_mtime)
        corrupt = Server.corrupt and name == GRAPH
        tag = f'"{size}-{modified}-{int(corrupt)}"'
        start, end = 0, size - 1
        wanted = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
        ranged = wanted is not None and self.headers.get("If-Range", tag) == tag
        if ranged:
            start = int(wanted[1])
            end = int(wanted[2]) if wanted[2] else size - 1
        if name == WEIGHTS:
            Server.offset, Server.requests = start, Server.requests + 1
        self.send_response(206 if ranged else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("ETag", tag)
        self.send_header("Last-Modified", self.date_time_string(modified))
        if ranged:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        try:
            with path.open("rb") as file:
                file.seek(start)
                at, chunk = start, 256 << 10
                while at <= end:
                    data = bytearray(file.read(min(chunk, end - at + 1)))
                    if corrupt and at + len(data) == size:
                        data[-1] ^= 0xFF
                    self.wfile.write(data)
                    at += len(data)
                    if name == WEIGHTS and Server.throttle:
                        time.sleep(len(data) / Server.throttle)
        except (BrokenPipeError, ConnectionResetError):
            pass   # the client cancelled


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
port = server.server_address[1]
with tempfile.TemporaryDirectory(prefix="spoti-sing-model-") as directory:
    binary = Path(directory) / "model-test"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-g", "-O1", "-Wall", "-Werror", "-fsanitize=address,undefined",
                    "-I", str(src), f'-DSGSingModelBase=@"http://127.0.0.1:{port}/"',
                    f'-DSGSingModelRoot=@"{directory}/root"',
                    str(here / "model_test.m"), str(src / "Shared/Sing/SGSingModel.m"),
                    str(src / "Core/SGPrefs.m"), str(src / "Core/SGLog.m"),
                    "-framework", "Foundation", "-framework", "Network", "-o", str(binary)], check=True)
    for mode in ["all", "leave", "reconnect"]:
        subprocess.run([str(binary), mode], check=True)
server.shutdown()
