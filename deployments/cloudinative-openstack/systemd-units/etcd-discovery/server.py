from http.server import BaseHTTPRequestHandler, HTTPServer
import json, threading

STORE = {}
LOCK = threading.Lock()

class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _ensure(self, token, size=1):
        with LOCK:
            if token not in STORE:
                STORE[token] = {"size": size, "members": []}
            return STORE[token]

    def do_GET(self):
        path = self.path.split("?")[0].strip("/")
        parts = path.split("/") if path else []
        # /<token>/_config/size
        if len(parts) >= 3 and parts[-2] == "_config" and parts[-1] == "size":
            d = self._ensure(parts[0])
            return self._send(200, json.dumps({"node":{"value": str(d["size"])}}))
        # /<token>  -> list members
        if len(parts) == 1:
            d = self._ensure(parts[0])
            nodes = [{"key": "/_etcd/registry/"+parts[0]+"/"+m[0], "value": m[1]} for m in d["members"]]
            return self._send(200, json.dumps({"action":"get","node":{"key":"/_etcd/registry/"+parts[0],"dir":True,"nodes":nodes}}))
        self._send(404, json.dumps({"error":"not found", "path": self.path}))

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode() if length else ""
        path = self.path.split("?")[0].strip("/")
        parts = path.split("/")
        # /<token>/<member_id>
        if len(parts) == 2:
            d = self._ensure(parts[0])
            d["members"] = [m for m in d["members"] if m[0] != parts[1]]
            d["members"].append((parts[1], body))
            return self._send(201, json.dumps({"action":"set","node":{"key":"/_etcd/registry/"+parts[0]+"/"+parts[1],"value":body}}))
        self._send(404, json.dumps({"error":"not found"}))

    def log_message(self,*a,**k): pass

HTTPServer(("0.0.0.0", 9379), H).serve_forever()
