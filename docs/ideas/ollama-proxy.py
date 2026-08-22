#!/usr/bin/env python3
import http.server
import json
import socketserver
import urllib.request
import urllib.error

TARGET_URL = "http://192.168.5.222:11434"
PORT = 11435

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # JSON の場合、messages 配列内の途中にある system ロールを user に変換
        content_type = self.headers.get("Content-Type", "")
        if content_type.startswith("application/json"):
            try:
                data = json.loads(body.decode("utf-8"))
                if "messages" in data and isinstance(data["messages"], list):
                    for i, msg in enumerate(data["messages"]):
                        # 先頭以外の system メッセージを user に書き換える
                        if i > 0 and msg.get("role") == "system":
                            msg["role"] = "user"
                            if isinstance(msg.get("content"), str):
                                msg["content"] = f"[System Instruction]\n{msg['content']}"
                            elif isinstance(msg.get("content"), list):
                                for block in msg["content"]:
                                    if block.get("type") == "text":
                                        block["text"] = f"[System Instruction]\n{block['text']}"
                body = json.dumps(data).encode("utf-8")
            except Exception:
                pass

        headers = {k: v for k, v in self.headers.items() if k.lower() not in ["host", "content-length"]}
        headers["Content-Length"] = str(len(body))

        req = urllib.request.Request(
            f"{TARGET_URL}{self.path}",
            data=body,
            headers=headers,
            method="POST"
        )

        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ["transfer-encoding"]:
                        self.send_header(k, v)
                self.end_headers()
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in ["transfer-encoding"]:
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(e.read())
            self.wfile.flush()

    def do_GET(self):
        headers = {k: v for k, v in self.headers.items() if k.lower() != "host"}
        req = urllib.request.Request(
            f"{TARGET_URL}{self.path}",
            headers=headers,
            method="GET"
        )
        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ["transfer-encoding"]:
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(resp.read())
                self.wfile.flush()
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in ["transfer-encoding"]:
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(e.read())
            self.wfile.flush()

    def log_message(self, format, *args):
        # 冗長なアクセスログの出力を抑制
        pass

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    with ReusableTCPServer(("", PORT), ProxyHandler) as httpd:
        print(f"Ollama Proxy listening on port {PORT} -> {TARGET_URL}")
        httpd.serve_forever()
