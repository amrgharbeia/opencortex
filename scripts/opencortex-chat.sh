#!/bin/bash
# opencortex-chat: The terminal mouthpiece for the Autonomous Brain.
PORT=9105
HOST=${1:-localhost}

# Check for socat (preferred)
if command -v socat >/dev/null 2>&1; then
    # Use socat with READLINE for history and arrow-key support.
    # It establishes a persistent bidirectional connection.
    # Note: socat READLINE doesn't handle hex-length framing automatically for input.
    # We use a wrapper to frame the message.
    
    echo "Connected to OpenCortex on $HOST:$PORT (Channel: CLI)"
    while true; do
        read -p "User: " MESSAGE
        if [ -z "$MESSAGE" ]; then continue; fi
        if [ "$MESSAGE" = "/exit" ]; then break; fi
        
        # Frame the message: (:TYPE :EVENT :META (:SOURCE :CLI) :PAYLOAD (:SENSOR :USER-INPUT :TEXT "msg"))
        PAYLOAD="(:TYPE :EVENT :META (:SOURCE :CLI) :PAYLOAD (:SENSOR :USER-INPUT :TEXT \"$MESSAGE\"))"
        LEN=$(printf "%s" "$PAYLOAD" | wc -c)
        HEXLEN=$(printf "%06x" $LEN)
        
        # Send and read response
        (printf "%s%s" "$HEXLEN" "$PAYLOAD" | nc -N $HOST $PORT) | while read -r LINE; do
            # The line will have the 6-char hex length prefix.
            # We strip it and look for the response.
            CLEAN=$(echo "$LINE" | sed 's/^......//')
            if [[ "$CLEAN" == *":TEXT"* ]]; then
                 # Extract the text content (simple grep-like extraction for CLI fallback)
                 TEXT=$(echo "$CLEAN" | sed -n 's/.*:TEXT "\([^"]*\)".*/\1/p')
                 echo "Agent: $TEXT"
            fi
        done
    done
else
    echo "Error: socat or nc required."
    exit 1
fi
