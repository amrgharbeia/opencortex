FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    sbcl \
    emacs-nox \
    curl \
    git \
    socat \
    netcat-openbsd \
    libssl-dev \
    libncurses5-dev \
    libffi-dev \
    zlib1g-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Quicklisp
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" --eval "(ql-util:without-prompting (ql:add-to-init-file))" \
    && rm quicklisp.lisp

WORKDIR /app
COPY . .

# Initialize system in non-interactive mode
RUN mkdir -p /root/memex && ./opencortex.sh setup --non-interactive

EXPOSE 9105

CMD ["./opencortex.sh", "boot"]
