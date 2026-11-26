#!/usr/bin/env python3
"""
Apple Books Desktop App for Windows
- True 3-device simultaneous Wi-Fi Sync Server (Windows + iPhone + iPad)
- Closes to Windows System Tray (next to NVIDIA / Legion Toolkit / MSI Afterburner)
- Silent Startup support (--background)
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
SYNC_LOCK = threading.Lock()


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
BOOKS_FILE = os.path.join(get_data_dir(), "books_library.json")


def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def read_json(path, default):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return default
    return default


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def merge_sync_state(current, incoming):
    """Conflict-free 3-device merge (Windows + iPhone + iPad simultaneously)."""
    out = dict(current)

    # 1. Union of deleted tombstones
    del_books = sorted(set(current.get("deletedBookIds", [])) | set(incoming.get("deletedBookIds", [])))
    del_hls = sorted(set(current.get("deletedHighlightIds", [])) | set(incoming.get("deletedHighlightIds", [])))
    del_hl_set = set(del_hls)
    out["deletedBookIds"] = del_books
    out["deletedHighlightIds"] = del_hls

    # 2. Per-book progress: newest updatedAt wins
    prog = dict(current.get("progress", {}))
    for bid, p in incoming.get("progress", {}).items():
        if isinstance(p, dict):
            old_p = prog.get(bid)
            if not old_p or p.get("updatedAt", 0) >= old_p.get("updatedAt", 0):
                prog[bid] = p
    out["progress"] = prog

    # 3. Highlights: merge by ID (newest updatedAt/createdAt wins), respect deletions
    hl_map = {}
    for h in current.get("highlights", []):
        if isinstance(h, dict) and h.get("id") and h["id"] not in del_hl_set:
            hl_map[h["id"]] = h
    for h in incoming.get("highlights", []):
        if isinstance(h, dict) and h.get("id") and h["id"] not in del_hl_set:
            old_h = hl_map.get(h["id"])
            if not old_h or h.get("updatedAt", h.get("createdAt", 0)) >= old_h.get("updatedAt", old_h.get("createdAt", 0)):
                hl_map[h["id"]] = h
    out["highlights"] = list(hl_map.values())

    # 4. Bookmarks: union by ID per book
    bms = dict(current.get("bookmarks", {}))
    for bid, lst in incoming.get("bookmarks", {}).items():
        cur_lst = list(bms.get(bid, []))
        seen = {x.get("id") for x in cur_lst if isinstance(x, dict)}
        for item in lst:
            if isinstance(item, dict) and item.get("id") not in seen:
                cur_lst.append(item)
                seen.add(item.get("id"))
        bms[bid] = cur_lst
    out["bookmarks"] = bms

    # 5. Reading Goals Timer: keep max todaySeconds for same date, newest dailyMinutes target
    c_goals = dict(current.get("goals", {}))
    i_goals = incoming.get("goals", {})
    if isinstance(i_goals, dict) and i_goals:
        c_date = c_goals.get("todayDate", "")
        i_date = i_goals.get("todayDate", "")
        if i_date > c_date:
            merged_goals = dict(i_goals)
        elif c_date > i_date:
            merged_goals = dict(c_goals)
        else:
            merged_goals = dict(c_goals)
            c_sec = c_goals.get("todaySeconds", c_goals.get("todayMinutes", 0) * 60)
            i_sec = i_goals.get("todaySeconds", i_goals.get("todayMinutes", 0) * 60)
            best_sec = max(c_sec, i_sec)
            merged_goals["todaySeconds"] = best_sec
            merged_goals["todayMinutes"] = best_sec // 60
            merged_goals["todayDate"] = i_date or c_date
            merged_goals["streakDays"] = max(c_goals.get("streakDays", 1), i_goals.get("streakDays", 1))
            if i_goals.get("updatedAt", 0) >= c_goals.get("updatedAt", 0) and i_goals.get("dailyMinutes"):
                merged_goals["dailyMinutes"] = i_goals["dailyMinutes"]
                merged_goals["updatedAt"] = i_goals.get("updatedAt", 0)
        out["goals"] = merged_goals

    # 6. Custom Book Order: newest bookOrderUpdatedAt wins
    if incoming.get("bookOrderUpdatedAt", 0) >= current.get("bookOrderUpdatedAt", 0) and isinstance(incoming.get("bookOrder"), list):
        out["bookOrder"] = incoming["bookOrder"]
        out["bookOrderUpdatedAt"] = incoming.get("bookOrderUpdatedAt", 0)

    # 7. Collections & Library Version
    out["collections"] = list(dict.fromkeys(list(current.get("collections", [])) + list(incoming.get("collections", []))))
    out["libraryVersion"] = max(current.get("libraryVersion", 0), incoming.get("libraryVersion", 0))
    if "appDark" in incoming:
        out["appDark"] = bool(incoming["appDark"])
    if incoming.get("readerSettings"):
        out["readerSettings"] = incoming["readerSettings"]
    return out


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
            with SYNC_LOCK:
                st = read_json(SYNC_FILE, {})
                lib = read_json(BOOKS_FILE, {"libraryVersion": 0, "books": [], "deletedBookIds": []})
                st["libraryVersion"] = max(st.get("libraryVersion", 0), lib.get("libraryVersion", 0))
            self._send_json(st)
            return
        if self.path == "/api/books":
            with SYNC_LOCK:
                lib = read_json(BOOKS_FILE, {"libraryVersion": 0, "books": [], "deletedBookIds": []})
            self._send_json(lib)
            return
        if self.path == "/":
            self.path = "/index.html"
        super().do_GET()

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            incoming = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(str(exc).encode("utf-8"))
            return

        if self.path == "/api/sync":
            with SYNC_LOCK:
                current = read_json(SYNC_FILE, {})
                merged = merge_sync_state(current, incoming)
                write_json(SYNC_FILE, merged)
            self._send_json({"ok": True})
            return

        if self.path == "/api/books":
            with SYNC_LOCK:
                current = read_json(BOOKS_FILE, {"libraryVersion": 0, "books": [], "deletedBookIds": []})
                deleted = set(current.get("deletedBookIds", [])) | set(incoming.get("deletedBookIds", []))
                by_id = {
                    b["id"]: b
                    for b in current.get("books", [])
                    if isinstance(b, dict) and b.get("id") and b["id"] not in deleted
                }
                for b in incoming.get("books", []):
                    if isinstance(b, dict) and b.get("id") and b["id"] not in deleted:
                        by_id[b["id"]] = b
                merged = {
                    "libraryVersion": max(current.get("libraryVersion", 0), incoming.get("libraryVersion", 0)),
                    "books": list(by_id.values()),
                    "deletedBookIds": sorted(deleted),
                }
                write_json(BOOKS_FILE, merged)
            self._send_json({"ok": True, "count": len(merged["books"])})
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
    try:
        server = ThreadingHTTPServer(("0.0.0.0", PORT), BooksHandler)
        server.serve_forever()
    except OSError:
        pass


def load_tray_image():
    from PIL import Image
    ico_path = os.path.join(RESOURCE_DIR, "app_icon.ico")
    if os.path.exists(ico_path):
        return Image.open(ico_path)
    return Image.new("RGB", (64, 64), (255, 138, 61))


def run_with_tray(local_url, wifi_url, start_hidden=False):
    import webview
    import pystray

    quitting = {"flag": False}
    win = webview.create_window(
        f"Books — Home Wi-Fi Sync: {wifi_url}",
        local_url,
        width=1240,
        height=820,
        min_size=(840, 600),
        hidden=start_hidden,
    )

    def on_closing():
        if quitting["flag"]:
            return True
        # Close to Windows System Tray instead of exiting (keeps Wi-Fi sync alive for iPhone & iPad!)
        win.hide()
        return False

    win.events.closing += on_closing

    def show_window(icon=None, item=None):
        win.show()
        try:
            win.restore()
        except Exception:
            pass

    def quit_app(icon, item):
        quitting["flag"] = True
        icon.stop()
        try:
            win.destroy()
        except Exception:
            pass
        os._exit(0)

    menu = pystray.Menu(
        pystray.MenuItem("Open Books", show_window, default=True),
        pystray.MenuItem(f"Wi-Fi Sync: {wifi_url}", lambda i, it: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit Books & Stop Sync", quit_app),
    )
    tray_icon = pystray.Icon("AppleBooksWindows", load_tray_image(), f"Books ({wifi_url})", menu)
    threading.Thread(target=tray_icon.run, daemon=True).start()
    webview.start()


if __name__ == "__main__":
    start_hidden = "--background" in sys.argv
    threading.Thread(target=start_server, daemon=True).start()
    local_url = f"http://127.0.0.1:{PORT}"
    wifi_url = f"http://{get_lan_ip()}:{PORT}"
    try:
        run_with_tray(local_url, wifi_url, start_hidden=start_hidden)
    except Exception:
        if start_hidden:
            start_server()
        else:
            webbrowser.open(local_url)
            input(f"Books running at {wifi_url}. Press Enter to quit...")
