from http.server import BaseHTTPRequestHandler, HTTPServer


class HelloHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Hello World</title></head>
<body><h1>Hello World from Python</h1></body></html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


HTTPServer(("0.0.0.0", 80), HelloHandler).serve_forever()