import socket, time, sys

def verify():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(20)
        s.connect(("localhost", 9105))
        
        # We need to read handshake and status first to clear the pipe
        full_data = b""
        while len(full_data) < 50: # Expecting at least handshake + status
            chunk = s.recv(4096)
            if not chunk: break
            full_data += chunk
        
        print(f"Data received: {full_data.decode()}")

        # Send "Hi"
        # Make sure we use the right length.
        # Send "Hi"
        # (:TYPE :EVENT :META (:SOURCE :CLI) :PAYLOAD (:SENSOR :USER-INPUT :TEXT "Hi"))
        payload = '(:TYPE :EVENT :META (:SOURCE :CLI) :PAYLOAD (:SENSOR :USER-INPUT :TEXT "Hi"))'
        length = len(payload)
        msg = f"{length:06x}{payload}".encode()
        print(f"Sending: {msg.decode()}")
        s.sendall(msg)

        # Read response
        while True:
            chunk = s.recv(4096).decode()
            if not chunk: break
            print(f"Received chunk: {chunk}")
            if ":REQUEST" in chunk or ":PAYLOAD" in chunk or "Neural Cascade Failure" in chunk:
                print("SUCCESS: Response received!")
                break
        s.close()
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

verify()
