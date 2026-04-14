#!/bin/bash
# org-agent-chat: The terminal mouthpiece for the Sovereign Brain.
PORT=9105
HOST=${1:-localhost}

echo "Connecting to org-agent at $HOST:$PORT..."
echo "Type your message and press Enter. Ctrl+C to exit."
echo "--------------------------------------------------"

# Uses netcat (nc) for a simple bidirectional pipe. 
# Requires an open connection. We use a simple loop for persistence.
while true; do
    read -p "User: " MESSAGE
    if [ -z "$MESSAGE" ]; then continue; fi
    # Send message and wait for one line of response from Agent
    echo "$MESSAGE" | nc -N $HOST $PORT
done
