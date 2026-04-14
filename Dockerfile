# ORG-AGENT v1.0 Production Environment
FROM debian:bookworm-slim

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install System Dependencies
# - sbcl: The Lisp Runtime
# - curl/git/unzip: Standard tools for Quicklisp and binaries
# - default-jre: Required by signal-cli
# - python3/pip: Required for Playwright bridge
RUN apt-get update && apt-get install -y \
    sbcl \
    curl \
    git \
    unzip \
    default-jre \
    libsqlite3-0 \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# 2. Setup Playwright (High-Fidelity Browsing)
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install playwright \
    && playwright install --with-deps chromium

# 3. Install signal-cli (v0.14.0)
ENV SIGNAL_CLI_VERSION=0.14.0
RUN curl -L https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux.tar.gz | tar xz -C /opt \
    && ln -s /opt/signal-cli-${SIGNAL_CLI_VERSION}/bin/signal-cli /usr/local/bin/signal-cli

# 4. Install Quicklisp & Pin Distribution
# Pinned to 2026-04-01 for bit-rot resistance.
WORKDIR /root
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --non-interactive \
        --load quicklisp.lisp \
        --eval '(quicklisp-quickstart:install)' \
        --eval '(ql-dist:install-dist "http://beta.quicklisp.org/dist/quicklisp/2026-04-01/distinfo.txt" :prompt nil :replace t)'

# 5. Configure SBCL to load Quicklisp on startup
RUN echo '(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))) (when (probe-file quicklisp-init) (load quicklisp-init)))' > /root/.sbclrc

# 6. Setup Application Directory
WORKDIR /app
COPY . /app/projects/org-agent

# 7. Pre-cache Lisp Dependencies
RUN sbcl --non-interactive \
    --eval '(push #p"/app/projects/org-agent/" asdf:*central-registry*)' \
    --eval '(ql:quickload :org-agent)'

# 8. Environment & Volumes
# The host's memex root should be mounted to /memex
ENV MEMEX_DIR=/memex
VOLUME ["/memex"]

# Default Ports
EXPOSE 9105 8080

# Entrypoint
CMD ["sbcl", "--non-interactive", \
     "--eval", "(push #p\"/app/projects/org-agent/\" asdf:*central-registry*)", \
     "--eval", "(ql:quickload :org-agent)", \
     "--eval", "(org-agent:main)"]
