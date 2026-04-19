import socket, time, sys

def verify():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(15)
        s.connect(("localhost", 9105))
        
        # 1. Read handshake
        print("Handshake:", s.recv(4096).decode())

        # 2. Send "Hi"
        payload = '(:TYPE :EVENT :PAYLOAD (:SENSOR :CHAT-MESSAGE :TEXT "Hi"))'
        msg = f"{len(payload):06x}{payload}".encode()
        s.sendall(msg)
        print("Sent 'Hi'")

        # 3. Read responses
        # We expect a STATUS then a CHAT
        responses = []
        start_time = time.time()
        while time.time() - start_time < 10:
            try:
                data = s.recv(4096).decode()
                if not data: break
                print(f"Received: {data}")
                responses.append(data)
                if ":CHAT" in data: break
            except socket.timeout:
                break
        
        s.close()
        
        all_responses = "".join(responses)
        if ":STATUS" in all_responses and ":CHAT" in all_responses:
            print("SUCCESS: Full cycle complete.")
            # Check for lowercase
            if ":status" in all_responses:
                print("FAILURE: Still seeing lowercase :status!")
        else:
            print("FAILURE: Missing expected response types.")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

verify()
