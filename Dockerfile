FROM ubuntu:24.04

# Install runtime dependencies: bash, jq, curl, python3, git
# Clean up apt cache to keep the image small
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        jq \
        curl \
        python3 \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create the rlm directory structure
RUN mkdir -p /rlm/tree /context

# Install rlm
COPY bin/rlm /usr/local/bin/rlm
RUN chmod +x /usr/local/bin/rlm

ENTRYPOINT ["rlm"]
