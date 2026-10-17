#!/usr/bin/env bash
# Rendering only. Mutation must run in the controller process, not a pipeline.
ctl_render() {
    if [[ "$CTL_FORMAT" == json ]]; then cat; else
        jq --unbuffered -r --arg view "$1" -f "${SCRIPT_DIR}/lib/ctl-output.jq"
    fi
}
