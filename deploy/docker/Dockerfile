FROM debian:bookworm-slim

# Install SBCL, ripgrep, and build dependencies
RUN apt-get update && \
    apt-get install -y sbcl build-essential curl git ripgrep libsqlite3-dev lynx python3 python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Quicklisp globally
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp && \
    sbcl --non-interactive \
         --load quicklisp.lisp \
         --eval '(quicklisp-quickstart:install :path "/opt/quicklisp")' \
         --eval '(ql-util:without-prompting (ql:add-to-init-file))' && \
    rm quicklisp.lisp

# Set up the working directory
WORKDIR /app

# Copy source code and system definition
COPY org-agent.asd /app/
COPY src/ /app/src/

# Build the standalone binary natively inside the container
# This ensures GLIBC compatibility with the runtime environment.
RUN sbcl --non-interactive \
         --eval '(push "/app/" asdf:*central-registry*)' \
         --eval '(ql:quickload :org-agent)' \
         --eval '(asdf:make :org-agent)'

# Ensure the binary is executable
RUN chmod +x /app/org-agent-server

# Expose the OACP and Web Dashboard ports
EXPOSE 9105 8080

# The app expects the memex to be mounted here
VOLUME /memex

# Run the natively compiled standalone daemon
CMD ["./org-agent-server"]
