FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash build-essential ca-certificates curl git libglib2.0-0 libicu70 libtinfo5 \
    python3 unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

# The launcher reads the checkout's .aspect/version.axl to select the CLI.
ARG ASPECT_LAUNCHER_VERSION=2026.45.6
ARG BAZELISK_VERSION=1.27.0
ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64) aspect_arch=x86_64 ;; \
      arm64) aspect_arch=aarch64 ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --retry 3 \
      "https://github.com/aspect-build/aspect-cli/releases/download/v${ASPECT_LAUNCHER_VERSION}/aspect-launcher-${aspect_arch}-unknown-linux-musl" \
      --output /usr/local/bin/aspect \
    && curl --fail --location --retry 3 \
      "https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-${TARGETARCH}" \
      --output /usr/local/bin/bazel \
    && chmod +x /usr/local/bin/aspect /usr/local/bin/bazel

RUN git clone --depth 1 --branch v1.8.2 https://github.com/bats-core/bats-core.git /tmp/bats \
    && /tmp/bats/install.sh /usr/local \
    && rm -rf /tmp/bats \
    && git clone --depth 1 --branch v0.3.0 https://github.com/bats-core/bats-support.git /usr/local/lib/bats/bats-support \
    && git clone --depth 1 --branch v2.1.0 https://github.com/bats-core/bats-assert.git /usr/local/lib/bats/bats-assert

# Every Bazel invocation, including Aspect and Bats subprocesses, reads this.
COPY ci.bazelrc /etc/bazel.bazelrc

ENV BATS_LIB_PATH=/usr/local/lib/bats
ENV CI=true BUILDKITE=true
# Commands in the mounted checkout check /workspace; local clone's upload-pack
# checks /workspace/.git. Both are the agent-owned repository we mount.
RUN git config --system --add safe.directory /workspace \
    && git config --system --add safe.directory /workspace/.git
# rules_python's hermetic interpreter refuses to run as root.
RUN useradd --create-home --uid 1000 tester
ENV HOME=/home/tester
USER tester
WORKDIR /workspace
