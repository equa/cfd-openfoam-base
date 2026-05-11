# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 — Ubuntu 24.04 with OpenFOAM build dependencies
# ─────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS build-deps

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Stockholm

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN sed -i \
    -e 's|http://archive.ubuntu.com|http://se.archive.ubuntu.com|g' \
    -e 's|http://security.ubuntu.com|http://se.archive.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update -y && apt-get install -qy \
    git \
    build-essential \
    flex \
    bison \
    cmake \
    libfl-dev \
    zlib1g-dev \
    libopenmpi-dev \
    openmpi-bin \
    python3 \
    curl


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — Clone sources and compile OpenFOAM + ThirdParty
#
# This is the slow stage (~30–60 min first run). Docker BuildKit caches it
# as long as the COPY'd scripts and the ARGs do not change.
# ─────────────────────────────────────────────────────────────────────────────
FROM build-deps AS openfoam-builder

ARG OF_VERSION=13
ARG FOAM_INST_DIR=/opt/cfd

ENV FOAM_INST_DIR=${FOAM_INST_DIR}
ENV OPENFOAM_VERSION=${OF_VERSION}
ENV FOAM_ETC=${FOAM_INST_DIR}/OpenFOAM-${OF_VERSION}/etc
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# OpenFOAM requires bash as /bin/sh
RUN ln -sf /bin/bash /bin/sh

RUN git clone --depth 1 \
    https://github.com/OpenFOAM/OpenFOAM-${OF_VERSION}.git \
    ${FOAM_INST_DIR}/OpenFOAM-${OF_VERSION}

RUN git clone --depth 1 \
    https://github.com/OpenFOAM/ThirdParty-${OF_VERSION}.git \
    ${FOAM_INST_DIR}/ThirdParty-${OF_VERSION}

COPY scripts/build_openfoam.sh /build_openfoam.sh
ENV WM_NCOMPPROCS=10
RUN bash /build_openfoam.sh


# ─────────────────────────────────────────────────────────────────────────────
# Stage 3 — Strip build artifacts (intermediate; not a named target)
#
# Runs cleanup inside the builder environment where OF tools (wclean, strip)
# are available, then the result is copied into the lean runtime image below.
# ─────────────────────────────────────────────────────────────────────────────
FROM openfoam-builder AS openfoam-stripped

COPY scripts/cleanup_openfoam.sh /cleanup_openfoam.sh
RUN bash /cleanup_openfoam.sh


# ─────────────────────────────────────────────────────────────────────────────
# Target: openfoam13-base
#
# Lean runtime image. No build tools, no source. Use this as the base for
# downstream images that only need to run OpenFOAM (not compile against it).
# ─────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS openfoam13-base

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Stockholm

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN sed -i \
    -e 's|http://archive.ubuntu.com|http://se.archive.ubuntu.com|g' \
    -e 's|http://security.ubuntu.com|http://se.archive.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update -y && apt-get install -qy \
    libopenmpi3 \
    openmpi-bin \
    python3 \
    && rm -rf /var/lib/apt/lists/*

ARG OF_VERSION=13
ARG FOAM_INST_DIR=/opt/cfd

ENV FOAM_INST_DIR=${FOAM_INST_DIR}
ENV OPENFOAM_VERSION=${OF_VERSION}
ENV FOAM_ETC=${FOAM_INST_DIR}/OpenFOAM-${OF_VERSION}/etc

COPY --from=openfoam-stripped ${FOAM_INST_DIR} ${FOAM_INST_DIR}
COPY tests/smoke/run-all.sh /tests/smoke/run-all.sh
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

RUN ln -sf /bin/bash /bin/sh \
 && echo "source ${FOAM_ETC}/bashrc" > /etc/profile.d/99-openfoam.sh


# ─────────────────────────────────────────────────────────────────────────────
# Target: openfoam13-dev
#
# Full build environment plus developer tooling. Use this as base when you
# need to compile code against OpenFOAM (e.g. site extensions), or for
# interactive development inside the container.
# ─────────────────────────────────────────────────────────────────────────────
FROM openfoam-builder AS openfoam13-dev

RUN apt-get install -qy \
    neovim \
    ripgrep \
    bash-completion

ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

RUN ln -sf /bin/bash /bin/sh \
 && echo "source ${FOAM_ETC}/bashrc" > /etc/profile.d/99-openfoam.sh

# vim: set ft=dockerfile :
