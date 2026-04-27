import socket
import struct

def frame_message(msg_string):
    payload = msg_string.encode('utf-8')
    return f"{len(payload):06x}".encode('ascii') + payload

def read_framed(sock):
    header = b''
    while len(header) < 6:
        chunk = sock.recv(6 - len(header))
        if not chunk:
            return None
        header += chunk
    length = int(header, 16)
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            return None
        data += chunk
    return data.decode('utf-8')

msg = '(:TYPE :REQUEST :PAYLOAD (:ACTION :MESSAGE :TEXT "hello") :META (:SOURCE :CLI :SESSION-ID "test1"))'

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(('127.0.0.1', 9105))
sock.settimeout(10.0)

# Read handshake
handshake = read_framed(sock)
print("HANDSHAKE:", handshake)

# Read status
status = read_framed(sock)
print("STATUS:", status)

# Send message
sock.sendall(frame_message(msg))
print("SENT:", msg)

# Read response
response = read_framed(sock)
print("RESPONSE:", response)

sock.close()
