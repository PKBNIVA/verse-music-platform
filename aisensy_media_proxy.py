import base64, hashlib, io, json, os, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
import requests
from PIL import Image

PORT = int(os.environ.get('PORT', '10000'))
CACHE = {}
HITS = {}
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
    source_bytes = r.content
    im = Image.open(io.BytesIO(source_bytes))
    source_format, source_mode, source_size = im.format, im.mode, im.size
    im.verify()
    im = Image.open(io.BytesIO(source_bytes)).convert('RGB')
    canvas = Image.new('RGB', (1024, 1024), 'white')
    im.thumbnail((900, 900), Image.Resampling.NEAREST)
    canvas.paste(im, ((1024-im.width)//2, (1024-im.height)//2))
    out = io.BytesIO()
    canvas.save(out, format='JPEG', quality=95, optimize=True)
    data = out.getvalue()
    if not data.startswith(b'\xff\xd8') or len(data) < 1000:
        raise ValueError('normalized jpeg invalid')
    meta = {
        'source_format': source_format,
        'source_mode': source_mode,
        'source_width': source_size[0],
        'source_height': source_size[1],
        'source_bytes': len(source_bytes),
        'jpeg_bytes': len(data),
        'source_sha256': hashlib.sha256(source_bytes).hexdigest(),
        'jpeg_sha256': hashlib.sha256(data).hexdigest(),
    }
    with LOCK:
        CACHE[source] = (data, meta)
    return data, meta

def parse_q_path(path):
    clean = path.split('?',1)[0]
    parts = clean.split('/')
    if len(parts) != 4 or parts[1] != 'q' or not parts[3].endswith('.jpg'):
        raise ValueError('invalid path')
    row_id = parts[2]
    token = parts[3][:-4]
    return row_id, decode_token(token)

def mark_hit(row_id, method, user_agent):
    with LOCK:
        d = HITS.setdefault(row_id, {'head':0,'get':0,'last_user_agent':'','last_method':''})
        if method == 'HEAD': d['head'] += 1
        if method == 'GET': d['get'] += 1
        d['last_user_agent'] = user_agent or ''
        d['last_method'] = method
        return dict(d)

def send_json(h, obj, status=200):
    body=json.dumps(obj,separators=(',',':')).encode()
    h.send_response(status)
    h.send_header('Content-Type','application/json')
    h.send_header('Content-Length',str(len(body)))
    h.end_headers()
    h.wfile.write(body)

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
            row_id, source = parse_q_path(self.path)
            data, meta = normalize(source)
            hit = mark_hit(row_id, 'HEAD' if head else 'GET', self.headers.get('User-Agent',''))
            print('MEDIA_OK', json.dumps({'row':row_id,'method':'HEAD' if head else 'GET','bytes':len(data),'ua':hit['last_user_agent']}), flush=True)
            send_image(self,data,head)
        except Exception as e:
            print('MEDIA_FAIL', repr(e), flush=True)
            self.send_response(422); self.end_headers()
            if not head: self.wfile.write(b'invalid media')
    def do_HEAD(self):
        if self.path.startswith('/q/'):
            return self._serve_dynamic(True)
        self.send_response(200 if self.path=='/' else 404); self.end_headers()
    def do_GET(self):
        if self.path.startswith('/q/'):
            return self._serve_dynamic(False)
        if self.path.startswith('/hit/'):
            row_id=self.path.split('/hit/',1)[1].split('?',1)[0]
            with LOCK: hit=dict(HITS.get(row_id, {'head':0,'get':0,'last_user_agent':'','last_method':''}))
            return send_json(self, {'row':row_id, **hit})
        if self.path=='/stats':
            with LOCK:
                return send_json(self, {'cached':len(CACHE),'tracked':len(HITS),'gets':sum(x['get'] for x in HITS.values()),'heads':sum(x['head'] for x in HITS.values())})
        if self.path=='/health':
            return send_json(self, {'ok':True})
        self.send_response(200 if self.path=='/' else 404); self.end_headers(); self.wfile.write(b'ok' if self.path=='/' else b'not found')

ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
