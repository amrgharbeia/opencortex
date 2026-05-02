FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    sbcl emacs-nox curl git socat netcat-openbsd rlwrap \
    libssl-dev libncurses-dev libffi-dev zlib1g-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --non-interactive --load quicklisp.lisp \
        --eval "(quicklisp-quickstart:install)" \
        --eval "(ql-util:without-prompting (ql:add-to-init-file))" \
    && rm quicklisp.lisp

WORKDIR /app
COPY . .

RUN mkdir -p /root/memex && ./opencortex.sh configure --non-interactive

EXPOSE 9105

CMD ["./opencortex.sh", "daemon"]
