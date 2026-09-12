#!/usr/bin/env python3
"""Minimal Jamf Pro mock for exercising the self-service-policy-scopes scripts.

Local authoring/test tool only; nothing here ships to a Mac. Implements just
enough of the Jamf Pro API (OAuth token, /v1/auth, invalidate) and the Classic
API (/JSSResource/policies, /policies/id/{id} GET+PUT, /categories) for the
writers' dry-run, apply and read-back paths.

Classic PUT semantics as documented: each top-level child supplied in the
request body replaces the same-named child of the stored policy in full.

Special IDs:
  404 -> GET answers 404
  500 -> GET answers HTTP 200 with an HTML body (proxy error page)
  429 -> every other GET answers 429 with Retry-After: 1 (seeded from policy-429.xml)
"""
import copy
import sys
import xml.etree.ElementTree as ET

# Parse with defusedxml when it is installed (XXE, billion-laughs); the tree
# building and serialising stays on the stdlib, which defusedxml does not wrap.
try:
    from defusedxml.ElementTree import fromstring as safe_fromstring, parse as safe_parse
except ImportError:  # pragma: no cover
    safe_fromstring, safe_parse = ET.fromstring, ET.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18081
SEED = sys.argv[2:]

STORE = {}
LOG = []
HITS = {}


def load(path):
    tree = safe_parse(path)
    root = tree.getroot()
    pid = root.find("general/id").text.strip()
    STORE[pid] = root


for p in SEED:
    load(p)

CATEGORIES = {"5": "Apps & Utilities", "9": "Productivity", "21": "Utilities"}


class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        LOG.append(fmt % args)
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    def _send(self, code, body=b"", ctype="application/xml"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _auth_ok(self):
        return self.headers.get("Authorization", "") == "Bearer tok-1"

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length else b""
        if self.path == "/api/v1/oauth/token":
            if b"grant_type=client_credentials" in body and b"client_id=cid" in body and b"client_secret=sec" in body:
                self._send(200, b'{"access_token":"tok-1","token_type":"Bearer","expires_in":3600,"scope":""}', "application/json")
            else:
                self._send(400, b'{"error":"invalid_client"}', "application/json")
            return
        if self.path == "/api/v1/auth/invalidate-token":
            self._send(204 if self._auth_ok() else 401)
            return
        self._send(404)

    def do_GET(self):
        if not self._auth_ok():
            self._send(401, b"<html>unauthorized</html>", "text/html")
            return
        if self.path == "/api/v1/auth":
            self._send(200, b'{"authenticationType":"CLIENT_CREDENTIALS"}', "application/json")
            return
        if self.path == "/JSSResource/policies":
            out = ET.Element("policies")
            for pid, pol in STORE.items():
                e = ET.SubElement(out, "policy")
                ET.SubElement(e, "id").text = pid
                ET.SubElement(e, "name").text = pol.find("general/name").text
            # Phantom entries so callers hit the 404 and non-XML paths.
            for pid, name in (("404", "Deleted Meanwhile"), ("500", "Behind Bad Proxy")):
                e = ET.SubElement(out, "policy")
                ET.SubElement(e, "id").text = pid
                ET.SubElement(e, "name").text = name
            self._send(200, ET.tostring(out, encoding="utf-8", xml_declaration=True))
            return
        if self.path.startswith("/JSSResource/policies/id/"):
            pid = self.path.rsplit("/", 1)[1]
            if pid == "429":
                HITS[pid] = HITS.get(pid, 0) + 1
                if HITS[pid] % 2 == 1:
                    self.send_response(429)
                    self.send_header("Retry-After", "1")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
            if pid == "500":
                self._send(200, b"<html><body><p>Service Unavailable<br>Try again later</body></html>", "text/html")
                return
            if pid not in STORE:
                self._send(404, b"<html>Not Found</html>", "text/html")
                return
            self._send(200, ET.tostring(STORE[pid], encoding="utf-8", xml_declaration=True))
            return
        if self.path.startswith("/JSSResource/categories/id/"):
            cid = self.path.rsplit("/", 1)[1]
            self._send(200 if cid in CATEGORIES else 404)
            return
        if self.path.startswith("/JSSResource/categories/name/"):
            from urllib.parse import unquote
            name = unquote(self.path.rsplit("/", 1)[1])
            self._send(200 if name in CATEGORIES.values() else 404)
            return
        self._send(404)

    def do_PUT(self):
        if not self._auth_ok():
            self._send(401)
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length else b""
        if not self.path.startswith("/JSSResource/policies/id/"):
            self._send(404)
            return
        pid = self.path.rsplit("/", 1)[1]
        if pid not in STORE:
            self._send(404)
            return
        if self.headers.get("Content-Type", "") != "application/xml":
            self._send(415)
            return
        try:
            req = safe_fromstring(body)
        except ET.ParseError:
            self._send(400, b"<html>XML format is incorrect</html>", "text/html")
            return
        stored = STORE[pid]
        for child in list(req):
            old = stored.find(child.tag)
            new = copy.deepcopy(child)
            if old is not None:
                idx = list(stored).index(old)
                stored.remove(old)
                stored.insert(idx, new)
            else:
                stored.append(new)
        # Jamf recomputes general/trigger from the booleans; emulate that so the
        # scripts' "legacy trigger moved" report has something to see.
        g = stored.find("general")
        if g is not None and g.find("trigger") is not None:
            auto = any((g.findtext(t) or "") == "true" for t in (
                "trigger_checkin", "trigger_startup", "trigger_login", "trigger_logout",
                "trigger_network_state_changed", "trigger_enrollment_complete")) or bool(g.findtext("trigger_other"))
            g.find("trigger").text = "EVENT" if auto else "USER_INITIATED"
        out = ET.Element("policy")
        ET.SubElement(out, "id").text = pid
        self._send(201, ET.tostring(out, encoding="utf-8", xml_declaration=True))


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
