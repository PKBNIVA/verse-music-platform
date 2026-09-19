import base64, io, os, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
import requests
from PIL import Image

PORT = int(os.environ.get('PORT', '10000'))
CACHE = {}
LOCK = threading.Lock()
ALLOWED_HOSTS = {'eventhug-5f90dbe31c80.herokuapp.com','sociana.s3.ap-south-1.amazonaws.com'}

def decode_token(token):
    pad = '=' * (-len(token) % 4)
    return base64.urlsafe_b64decode((token + pad).encode()).decode()

def normalize(source):
    host = urlparse(source).hostname
    if host not in ALLOWED_HOSTS:
        raise ValueError('source host not allowed')
    with LOCK:
        if source in CACHE:
            return CACHE[source]
    r = requests.get(source, timeout=30, allow_redirects=True)
    r.raise_for_status()
    final_host = urlparse(r.url).hostname
    if final_host not in ALLOWED_HOSTS:
        raise ValueError('redirect host not allowed')
    im = Image.open(io.BytesIO(r.content))
    im.verify()
    im = Image.open(io.BytesIO(r.content)).convert('RGB')
    canvas = Image.new('RGB', (1024, 1024), 'white')
    im.thumbnail((900, 900), Image.Resampling.NEAREST)
    canvas.paste(im, ((1024-im.width)//2, (1024-im.height)//2))
    out = io.BytesIO()
    canvas.save(out, format='JPEG', quality=95, optimize=True)
    data = out.getvalue()
    if not data.startswith(b'\xff\xd8') or len(data) < 1000:
        raise ValueError('normalized jpeg invalid')
    with LOCK:
        CACHE[source] = data
    return data

def send_image(h, data, head=False):
    h.send_response(200)
    h.send_header('Content-Type','image/jpeg')
    h.send_header('Content-Length',str(len(data)))
    h.send_header('Cache-Control','public, max-age=86400')
    h.send_header('Content-Disposition','inline; filename="qrcode.jpg"')
    h.end_headers()
    if not head:
        h.wfile.write(data)

class Handler(BaseHTTPRequestHandler):
    def _serve_dynamic(self, head=False):
        try:
            token=self.path.split('/q/',1)[1].split('.jpg',1)[0]
            source=decode_token(token)
            data=normalize(source)
            print('MEDIA_OK', len(data), self.headers.get('User-Agent',''), flush=True)
            send_image(self,data,head)
        except Exception as e:
            print('MEDIA_FAIL', repr(e), flush=True)
            self.send_response(422); self.end_headers()
            if not head: self.wfile.write(b'invalid media')
    def do_HEAD(self):
        if self.path.startswith('/q/') and self.path.endswith('.jpg'):
            return self._serve_dynamic(True)
        self.send_response(200 if self.path=='/' else 404); self.end_headers()
    def do_GET(self):
        if self.path.startswith('/q/') and self.path.endswith('.jpg'):
            return self._serve_dynamic(False)
        if self.path=='/health':
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok'); return
        self.send_response(200 if self.path=='/' else 404); self.end_headers(); self.wfile.write(b'ok' if self.path=='/' else b'not found')

ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
