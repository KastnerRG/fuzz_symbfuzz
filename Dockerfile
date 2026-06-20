FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=usr
ARG CONT_WS=/repo/fuzzers/symbfuzz
ARG UID=1000
ARG GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git \
    build-essential make gcc g++ \
    python3 python3-pip python3-venv \
    cmake ninja-build \
    yosys z3 libz3-dev \
    ccache \
    bash-completion vim time unzip rsync \
 && rm -rf /var/lib/apt/lists/*

RUN ln -sf /bin/bash /bin/sh

RUN groupadd -g ${GID} ${USERNAME} \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

USER ${USERNAME}
WORKDIR ${CONT_WS}

RUN cat >> /home/${USERNAME}/.bashrc <<'EOF_BASHRC'
export PATH="$HOME/.local/bin:$PATH"
export PS1="\[\e[0;32m\][\u@\h \W]\$ \[\e[m\] "
EOF_BASHRC
