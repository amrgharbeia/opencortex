#!/bin/bash
# org-agent-chat: The terminal mouthpiece for the Autonomous Brain.
PORT=9105
HOST=${1:-localhost}

# Check for socat (preferred)
if command -v socat >/dev/null 2>&1; then
    # Use socat with READLINE for history and arrow-key support.
    # It establishes a persistent bidirectional connection.
    socat READLINE,history=$HOME/.org_agent_history TCP:$HOST:$PORT
else
    # Fallback to nc (netcat) for a single-shot connection if socat is missing.
    # Note: This is less robust for agents with long-thinking times.
    echo "WARNING: socat not found. Falling back to nc (no line-editing support)."
    while true; do
        read -p "User: " MESSAGE
        if [ -z "$MESSAGE" ]; then continue; fi
        echo "$MESSAGE" | nc -N $HOST $PORT
    done
fi
