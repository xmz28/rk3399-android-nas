"""Normalize duplicate Android headers, forwarding bodies with reusable buffers."""
import socket
import socketserver
import threading

def pump(source, destination, limit=None):
    buffer = bytearray(262144)
    view = memoryview(buffer)
    while limit is None or limit > 0:
        count = source.recv_into(view if limit is None else view[:min(limit, len(view))])
        if not count:
            break
        destination.sendall(view[:count])
        if limit is not None:
            limit -= count

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        upstream = None
        try:
            self.request.settimeout(300)
            upstream = socket.create_connection(('127.0.0.1', 3000), timeout=300)
            def send_request():
                try:
                    pump(self.request, upstream)
                except OSError:
                    pass
            threading.Thread(target=send_request, daemon=True).start()
            data = b''
            while b'\r\n\r\n' not in data:
                chunk = upstream.recv(65536)
                if not chunk or len(data) > 65536:
                    raise ValueError('Invalid response headers')
                data += chunk
            head, initial = data.split(b'\r\n\r\n', 1)
            lines = head.split(b'\r\n')
            out, seen = [lines[0]], {}
            for line in lines[1:]:
                name, value = line.split(b':', 1)
                name = name.lower()
                if name in (b'content-length', b'content-type'):
                    if name in seen:
                        if seen[name] != value.strip():
                            raise ValueError('Conflicting response headers')
                        continue
                    seen[name] = value.strip()
                if name not in (b'connection', b'keep-alive'):
                    out.append(line)
            out.append(b'Connection: close')
            self.request.sendall(b'\r\n'.join(out) + b'\r\n\r\n' + initial)
            length = seen.get(b'content-length')
            remaining = max(0, int(length) - len(initial)) if length is not None else None
            pump(upstream, self.request, remaining)
        except (OSError, ValueError):
            pass
        finally:
            if upstream:
                try:
                    upstream.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                upstream.close()

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(('127.0.0.1', 3002), Handler) as server:
    server.serve_forever()
