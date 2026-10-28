#!/usr/bin/env python3
"""Exports byte progress from velero.io Backup/PodVolumeRestore CRDs as Prometheus gauges."""
import json, os, ssl, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen

HOST = os.environ.get("KUBERNETES_SERVICE_HOST", "https://kubernetes.default.svc").replace("https://", "https://") if False else "https://kubernetes.default.svc"
NS = open("/var/run/secrets/kubernetes.io/serviceaccount/namespace").read().strip()
TOKEN = open("/var/run/secrets/kubernetes.io/serviceaccount/token").read().strip()
CA = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
CTX = ssl.create_default_context(cafile=CA)

PHASE = {"New": 0, "InProgress": 1, "Completed": 2, "Failed": 3, "PartiallyFailed": 4}

def api(path):
    req = Request(HOST + path, headers={"Authorization": f"Bearer {TOKEN}"})
    with urlopen(req, context=CTX, timeout=10) as r:
        return json.load(r)

def collect():
    lines = []
    for plural, metric, label in (
        ("podvolumerestores", "velero_pvr_progress_bytes", "podvolumerestore"),
        ("backups", "velero_backup_progress_bytes", "backup"),
    ):
        try:
            items = api(f"/apis/velero.io/v1/namespaces/{NS}/{plural}").get("items", [])
        except Exception:
            continue
        for it in items:
            name = it["metadata"]["name"]
            st = it.get("status") or {}
            prog = st.get("progress") or {}
            phase = st.get("phase", "New")
            base = f'{metric}{{name="{name}"}}'
            lines.append(f'{base}{{phase="{phase}"}} {PHASE.get(phase, -1)}')
            done, total = prog.get("bytesDone"), prog.get("totalBytes")
            if done is not None:
                lines.append(f'{base}{{kind="done"}} {done}')
            if total is not None:
                lines.append(f'{base}{{kind="total"}} {total}')
    return "\n".join(lines) + "\n"

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = collect().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), H).serve_forever()
