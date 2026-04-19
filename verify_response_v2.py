import socket, time, sys

def verify():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(20)
        s.connect(("localhost", 9105))
        
        # 1. Read everything until initial status
        full_data = b""
        while b":STATUS" not in full_data and b":status" not in full_data:
            chunk = s.recv(4096)
            if not chunk: break
            full_data += chunk
        
        print(f"Initial stream: {full_data.decode()}")

        # 2. Send "Hi"
        payload = '(:TYPE :EVENT :PAYLOAD (:SENSOR :CHAT-MESSAGE :TEXT "Hi"))'
        msg = f"{len(payload):06x}{payload}".encode()
        print(f"Sending: {msg.decode()}")
        s.sendall(msg)
        
        # 3. Read response
        responses = []
        start_time = time.time()
        while time.time() - start_time < 15:
            try:
                chunk = s.recv(4096).decode()
                if not chunk: break
                print(f"Received chunk: {chunk}")
                responses.append(chunk)
                if ":CHAT" in chunk:
                    print("Found reasoning response!")
            except socket.timeout:
                break
        
        s.close()
        
        # Assertions
        all_text = "".join(responses)
        if ":status" in all_text or ":status" in full_data.decode():
            print("FAILURE: Found lowercase :status!")
        else:
            print("SUCCESS: Keywords are normalized to uppercase.")
            
        if ":CHAT" in all_text:
            print("SUCCESS: Full response loop closed.")
        else:
            print("FAILURE: No chat response received.")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

verify()
