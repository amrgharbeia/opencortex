import socket
import select

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', 9105))
server.listen(1)
print("MOCK DAEMON LIVE ON 9105")

conn, addr = server.accept()
# 1. Send Handshake
hello = '(:TYPE :EVENT :PAYLOAD (:ACTION :HANDSHAKE :VERSION \"0.1.0\"))'
conn.sendall(f"{len(hello):06x}{hello}".encode())

# 2. Receive and Echo
data = conn.recv(1024).decode()
print(f"MOCK RECEIVED: {data}")
if data:
    payload = data[6:] # Strip hex length
    # extract message text simple way
    import re
    match = re.search(r':TEXT \"([^\"]*)\"', payload)
    text = match.group(1) if match else "unknown"
    resp = f'(:TYPE :REQUEST :PAYLOAD (:ACTION :MESSAGE :TEXT \"PYTHON_MOCK_ECHO: {text}\"))'
    conn.sendall(f"{len(resp):06x}{resp}".encode())

conn.close()
server.close()
