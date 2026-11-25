#!/usr/bin/env python3
"""
Apple Books Desktop App for Windows (with built-in Same-Wi-Fi Sync Server)
Can be run directly with Python 3 or compiled into a standalone .exe via Build-EXE.bat.
"""
import json
import os
import socket
import subprocess
import sys
import threading
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = 8765


def get_resource_dir():
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return sys._MEIPASS
    return os.path.dirname(os.path.abspath(__file__))


def get_data_dir():
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    path = os.path.join(base, "AppleBooksWindows")
    os.makedirs(path, exist_ok=True)
    return path


RESOURCE_DIR = get_resource_dir()
SYNC_FILE = os.path.join(get_data_dir(), "sync_state.json")


def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def read_sync_state():
    if os.path.exists(SYNC_FILE):
        try:
            with open(SYNC_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def write_sync_state(data):
    tmp = SYNC_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, SYNC_FILE)


class BooksHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RESOURCE_DIR, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        if self.path == "/api/ping":
            self._send_json({"booksWifiSync": True, "lanUrl": f"http://{get_lan_ip()}:{PORT}"})
            return
        if self.path == "/api/sync":
            self._send_json(read_sync_state())
            return
        if self.path == "/":
            self.path = "/index.html"
        super().do_GET()

    def do_PUT(self):
        if self.path == "/api/sync":
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length > 0 else b"{}"
            try:
                incoming = json.loads(raw.decode("utf-8"))
                current = read_sync_state()
                merged_progress = dict(current.get("progress", {}))
                for bid, prog in incoming.get("progress", {}).items():
                    old_p = merged_progress.get(bid)
                    if not old_p or prog.get("updatedAt", 0) >= old_p.get("updatedAt", 0):
                        merged_progress[bid] = prog
                incoming["progress"] = merged_progress
                write_sync_state(incoming)
                self._send_json({"ok": True})
            except Exception as exc:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(str(exc).encode("utf-8"))
            return
        self.send_response(404)
        self.end_headers()

    def _send_json(self, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def start_server():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), BooksHandler)
    server.serve_forever()


def launch_window(url, wifi_url):
    # Option 1: Native embedded WebView2 desktop window if pywebview is installed
    try:
        import webview
        webview.create_window(
            f"Books — iPad/iPhone Wi-Fi Link: {wifi_url}",
            url,
            width=1240,
            height=820,
            min_size=(840, 600),
        )
        webview.start()
        return
    except Exception:
        pass

    # Option 2: Standalone chromeless app window using built-in Windows Edge
    edge_paths = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]
    for edge in edge_paths:
        if os.path.exists(edge):
            print(f"iPad/iPhone Same-Wi-Fi URL: {wifi_url}")
            proc = subprocess.Popen([edge, f"--app={url}", "--window-size=1240,820"])
            proc.wait()
            return

    webbrowser.open(url)
    input(f"Books is running! Open {wifi_url} on iPad/iPhone. Press Enter to quit...")


if __name__ == "__main__":
    t = threading.Thread(target=start_server, daemon=True)
    t.start()
    local_url = f"http://127.0.0.1:{PORT}"
    wifi_url = f"http://{get_lan_ip()}:{PORT}"
    launch_window(local_url, wifi_url)
