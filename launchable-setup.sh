#!/bin/bash
# Brev Launchable setup script (paste this, not brev-setup.sh).
# Pulls the workshop kit and runs the full node setup. All launch parameters
# (VNC_PASSWORD, PREBUILD_IMAGE, NOVNC_TLS, G1_WORKFLOW, HF_TOKEN, ...) pass straight through.
set -euo pipefail
REPO=https://github.com/vaishkarni/isaaclab-arena-brev.git
DIR="$HOME/isaaclab-arena-brev"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q; else git clone -q "$REPO" "$DIR"; fi
sudo -E bash "$DIR/brev-setup.sh"
