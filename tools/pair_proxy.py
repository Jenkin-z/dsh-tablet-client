"""临时测试工具：本地鉴权代理（用完即删）

App 端 adb input text 会把大小写吞掉，密码/令牌无法直接输入。
本代理监听 5099：改写 Authorization 为真实凭据后转发到共享服务 45278
（含 SSE 流式）。App 里地址填 http://127.0.0.1:4096、密码随便填。

用法: python pair_proxy.py <real_password>
"""
import base64
import http.client
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PASSWORD = sys.argv[1] if len(sys.argv) > 1 else ''
REAL_HOST, REAL_PORT = '127.0.0.1', 45278

# 把 App 发来的任意 Authorization 改写成正确凭据（App 端 adb 输入会丢大小写）
_REAL_AUTH = 'Basic ' + base64.b64encode(
    f'opencode:{PASSWORD}'.encode()).decode() if PASSWORD else None


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        print('[proxy]', fmt % args, flush=True)

    def do_GET(self):
        self._forward()

    do_POST = do_GET
    do_DELETE = do_GET
    do_PUT = do_GET

    def _forward(self):
        try:
            conn = http.client.HTTPConnection(REAL_HOST, REAL_PORT, timeout=15)
            headers = {k: v for k, v in self.headers.items()
                       if k.lower() not in ('host', 'connection', 'accept-encoding',
                                            'authorization')}
            if _REAL_AUTH:
                headers['Authorization'] = _REAL_AUTH
            headers['Accept-Encoding'] = 'identity'
            length = int(self.headers.get('Content-Length') or 0)
            body = self.rfile.read(length) if length else None
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() in ('connection', 'transfer-encoding', 'content-encoding',
                                 'content-length'):
                    continue
                self.send_header(k, v)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            while True:
                # read1：有多少读多少，不凑满——SSE 打字机增量不能被缓冲
                chunk = resp.read1(65536) if hasattr(resp, 'read1') else resp.read(512)
                if not chunk:
                    break
                self.wfile.write(b'%x\r\n' % len(chunk) + chunk + b'\r\n')
                self.wfile.flush()
            self.wfile.write(b'0\r\n\r\n')
            self.wfile.flush()
        except Exception as e:
            print('[proxy] error:', e, flush=True)
        finally:
            try:
                self.close_connection = True
            except Exception:
                pass


if __name__ == '__main__':
    print('proxy on 5099 →', f'{REAL_HOST}:{REAL_PORT}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 5099), Handler).serve_forever()
