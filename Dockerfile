FROM ubuntu:26.04

ARG NIM_VERSION=2.2.10

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.local/bin:/root/.local/share/grabnim/current/bin:/root/.nimble/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      fonts-dejavu-core \
      fonts-dejavu-extra \
      git \
      libegl1-mesa-dev \
      libfontconfig1 \
      libgl1-mesa-dev \
      libgl1-mesa-dri \
      libgles2 \
      libgles2-mesa-dev \
      libglx-mesa0 \
      libvulkan1 \
      libx11-xcb-dev \
      libxcb1-dev \
      libxcursor-dev \
      libxkbcommon-dev \
      libxrender-dev \
      mesa-utils \
      mesa-vulkan-drivers \
      vulkan-tools \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://codeberg.org/janAkali/grabnim/raw/branch/master/misc/install.sh | bash \
    && grabnim "${NIM_VERSION}" \
    && curl -fsSL https://raw.githubusercontent.com/nim-lang/atlas/HEAD/install.sh | \
      ATLAS_INSTALL_DIR=/root/.local/bin bash \
    && nim -v \
    && atlas -v

WORKDIR /workspace

COPY merenda.nimble ./

RUN atlas -t --update --features:kosmo install

COPY . ./

ENV DISPLAY=:99

CMD ["bash"]
