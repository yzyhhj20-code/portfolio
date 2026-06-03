#!/usr/bin/env python3
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
import sys

class RangeHTTPRequestHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Accept-Ranges', 'bytes')
        super().end_headers()

    def send_head(self):
        if 'Range' in self.headers:
            return self.handle_range_request()
        return super().send_head()

    def handle_range_request(self):
        path = self.translate_path(self.path)
        if not os.path.exists(path):
            return super().send_head()
        
        size = os.path.getsize(path)
        start, end = 0, size - 1
        range_header = self.headers['Range']
        
        if range_header.startswith('bytes='):
            range_spec = range_header[6:]
            if '-' in range_spec:
                start_str, end_str = range_spec.split('-', 1)
                if start_str:
                    start = int(start_str)
                if end_str:
                    end = int(end_str)
        
        if start >= size or end >= size or start > end:
            self.send_response(416)
            self.send_header('Content-Range', f'bytes */{size}')
            self.end_headers()
            return None
        
        length = end - start + 1
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Length', str(length))
        self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        
        with open(path, 'rb') as f:
            f.seek(start)
            self.wfile.write(f.read(length))
        
        return None

def run_server(port=3000):
    server_address = ('', port)
    httpd = HTTPServer(server_address, RangeHTTPRequestHandler)
    print(f'Serving at http://localhost:{port}')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\nStopping server...')
        httpd.shutdown()

if __name__ == '__main__':
    port = 3000
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    run_server(port)
