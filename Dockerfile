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

# Install rlm, llm, and shared library
COPY bin/rlm bin/llm bin/_rlm-common.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/rlm /usr/local/bin/llm

ENTRYPOINT ["rlm"]
