import io, os
from http.server import BaseHTTPRequestHandler, HTTPServer
import requests
from PIL import Image

SOURCE = 'https://eventhug-5f90dbe31c80.herokuapp.com//rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBcEJZIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--31891ab3b0921a103e51b261e52a12e5283379db/qrcode.png'
PORT = int(os.environ.get('PORT', '10000'))
JPEG = None
DIAG = {}

def prepare():
    global JPEG, DIAG
    r = requests.get(SOURCE, timeout=30, allow_redirects=True)
    r.raise_for_status()
    im = Image.open(io.BytesIO(r.content))
    DIAG = {'source_format': im.format, 'source_mode': im.mode, 'source_size': im.size, 'source_bytes': len(r.content), 'source_content_type': r.headers.get('content-type'), 'final_url': r.url}
    im = im.convert('RGB')
    canvas = Image.new('RGB', (1024, 1024), 'white')
    im.thumbnail((900, 900), Image.Resampling.NEAREST)
    x = (1024 - im.width) // 2
    y = (1024 - im.height) // 2
    canvas.paste(im, (x, y))
    out = io.BytesIO()
    canvas.save(out, format='JPEG', quality=95, optimize=True)
    JPEG = out.getvalue()
    DIAG['jpeg_bytes'] = len(JPEG)
    print('MEDIA_DIAG', DIAG, flush=True)

prepare()

class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == '/qr.jpg':
            self.send_response(200)
            self.send_header('Content-Type', 'image/jpeg')
            self.send_header('Content-Length', str(len(JPEG)))
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.send_header('Content-Disposition', 'inline; filename="qrcode.jpg"')
            self.end_headers()
        else:
            self.send_response(404); self.end_headers()
    def do_GET(self):
        if self.path == '/qr.jpg':
            print('MEDIA_HIT', self.command, self.headers.get('User-Agent'), flush=True)
            self.send_response(200)
            self.send_header('Content-Type', 'image/jpeg')
            self.send_header('Content-Length', str(len(JPEG)))
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.send_header('Content-Disposition', 'inline; filename="qrcode.jpg"')
            self.end_headers()
            self.wfile.write(JPEG)
        elif self.path == '/diag':
            import json
            body=json.dumps(DIAG).encode()
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok')

HTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
