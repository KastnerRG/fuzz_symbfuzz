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
    ccache \
    bash-completion vim time unzip rsync \
 && rm -rf /var/lib/apt/lists/*

# Yosys and Z3 are built/fetched rather than apt-installed: Ubuntu 22.04 ships
# yosys 0.9 (2019) and z3 4.8.12, but this tool needs yosys >= 0.35 and
# z3 >= 4.12 per the README. yosys 0.9 cannot even constant-fold the generate
# conditions sv2v emits for parameterised SV ("Condition for generate if is not
# constant"), so real designs fail to read.
ARG YOSYS_VERSION=v0.59
RUN apt-get update && apt-get install -y --no-install-recommends \
    bison flex libreadline-dev gawk tcl-dev libffi-dev zlib1g-dev pkg-config \
 && git clone --depth 1 --branch ${YOSYS_VERSION} \
      https://github.com/YosysHQ/yosys.git /tmp/yosys \
 && cd /tmp/yosys && (git submodule update --init --recursive --depth 1 || true) \
 && make config-gcc \
 && make -j16 ENABLE_TCL=0 ENABLE_PLUGINS=0 ENABLE_ABC=0 \
 && make install ENABLE_TCL=0 ENABLE_PLUGINS=0 ENABLE_ABC=0 \
 && rm -rf /tmp/yosys /var/lib/apt/lists/*

ARG Z3_VERSION=4.13.4
RUN curl -fsSL -o /tmp/z3.zip \
      https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VERSION}/z3-${Z3_VERSION}-x64-glibc-2.35.zip \
 && unzip -q /tmp/z3.zip -d /tmp \
 && cp /tmp/z3-${Z3_VERSION}-x64-glibc-2.35/bin/z3 /usr/local/bin/ \
 && cp /tmp/z3-${Z3_VERSION}-x64-glibc-2.35/bin/*.so* /usr/local/lib/ \
 && cp -r /tmp/z3-${Z3_VERSION}-x64-glibc-2.35/include/* /usr/local/include/ \
 && ldconfig \
 && rm -rf /tmp/z3.zip /tmp/z3-${Z3_VERSION}-x64-glibc-2.35

# sv2v, required by --sv2v for SystemVerilog Yosys cannot parse.
ARG SV2V_VERSION=v0.0.13
RUN curl -fsSL -o /tmp/sv2v.zip \
      https://github.com/zachjs/sv2v/releases/download/${SV2V_VERSION}/sv2v-Linux.zip \
 && unzip -q /tmp/sv2v.zip -d /tmp \
 && mv /tmp/sv2v-Linux/sv2v /usr/local/bin/sv2v && chmod +x /usr/local/bin/sv2v \
 && rm -rf /tmp/sv2v.zip /tmp/sv2v-Linux

RUN ln -sf /bin/bash /bin/sh

RUN groupadd -g ${GID} ${USERNAME} \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

USER ${USERNAME}
WORKDIR ${CONT_WS}

RUN cat >> /home/${USERNAME}/.bashrc <<'EOF_BASHRC'
export PATH="$HOME/.local/bin:$PATH"
export PS1="\[\e[0;32m\][\u@\h \W]\$ \[\e[m\] "
EOF_BASHRC
