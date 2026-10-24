FROM node:24-bookworm-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6

ARG PI_PACKAGE=@earendil-works/pi-coding-agent
ARG PI_VERSION=0.87.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        git \
        ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g --ignore-scripts "${PI_PACKAGE}@${PI_VERSION}" \
    && npm cache clean --force

RUN mkdir -p /workspace /home/node/.pi/agent \
    && chown -R node:node /workspace /home/node/.pi

ENV HOME=/home/node \
    PI_CODING_AGENT_DIR=/home/node/.pi/agent

USER node
WORKDIR /workspace
CMD ["pi"]
