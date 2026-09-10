#!/usr/bin/env bash
# =============================================================================
# IsaacLab-Arena workshop node setup for NVIDIA Brev (VM mode)
#
# Paste this as the Launchable "setup script", or run it once on an existing
# VM:  sudo -E bash brev-setup.sh
#
# What it does
#   1. GPU-backed XFCE desktop on Xorg :0 (NVIDIA virtual display)
#   2. x11vnc (password) -> noVNC on port 6080, viewable in any browser
#   3. systemd service so the desktop survives reboots
#   4. Clones IsaacLab-Arena (HTTPS, no GitHub login needed) + submodules
#   5. Optionally pre-builds the Arena docker image so attendees don't wait
#
# Launch parameters (Brev "Launch Parameters" -> env vars), all optional:
#   VNC_PASSWORD    password attendees type into noVNC (generated if empty)
#   NOVNC_TLS       0 = plain HTTP on 6080 (use behind a Brev Secure Link)  [default]
#                   1 = self-signed HTTPS on 6080 (direct public IP / BYOC nodes)
#   ARENA_BRANCH    IsaacLab-Arena branch/tag           [release/0.2.1]
#   PREBUILD_IMAGE  1 = build the Arena docker image now [1]
#   INSTALL_GROOT   1 = also build the GR00T variant (-g), adds ~45 min [0]
#   SCREEN          virtual desktop resolution          [1920x1080]
#   TARGET_USER     login user that owns the desktop    [auto: ubuntu/shadeform/first /home]
#   G1_WORKFLOW     1 = stage the Unitree G1 static apple-to-plate workflow (dataset,
#                   pre-trained checkpoint, GR00T N1.7 server/finetune helpers)  [1]
#   HF_TOKEN        Hugging Face read token of the person deploying (mark as secret in Brev).
#                   Written to ~/.cache/huggingface/token (same as `hf auth login`) and used to
#                   pre-cache the gated backbone nvidia/Cosmos-Reason2-2B that every GR00T N1.7
#                   model loads. The account must have accepted that repo's license (auto-approved).
#                   Dataset, tuned checkpoint and base model are public.  [empty = skip backbone]
#   DOWNLOAD_DATASET     1 = fetch nvidia/Arena-G1-Static-PickNPlace-Task (~10 GB, incl. LeRobot) [1]
#   DOWNLOAD_CHECKPOINT  1 = fetch nvidia/GN1x-Tuned-Arena-G1-Static-PickNPlace (~13 GB, weights only) [1]
#   PRECACHE_MODELS      1 = pre-cache nvidia/GR00T-N1.7-3B (~7 GB, public) and, with HF_TOKEN,
#                        nvidia/Cosmos-Reason2-2B (~5 GB, gated) in ~/.cache/huggingface  [1]
#   KEEP_HF_TOKEN        1 = leave the token file on the node so `hf` keeps working (participant's own
#                        token); 0 = delete it after caching (organizer-supplied token)  [1]
# =============================================================================
set -euo pipefail

NOVNC_TLS="${NOVNC_TLS:-0}"
ARENA_BRANCH="${ARENA_BRANCH:-release/0.2.1}"
PREBUILD_IMAGE="${PREBUILD_IMAGE:-1}"
INSTALL_GROOT="${INSTALL_GROOT:-0}"
SCREEN="${SCREEN:-1920x1080}"
ARENA_REPO="https://github.com/isaac-sim/IsaacLab-Arena.git"
LOG=/var/log/arena-workshop-setup.log

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# ---------------------------------------------------------------- 0. context
if [ "$(id -u)" -ne 0 ]; then
  echo "Re-running with sudo..."; exec sudo -E bash "$0" "$@"
fi
if [ -z "${TARGET_USER:-}" ]; then
  # 1) the person who ran "sudo bash brev-setup.sh"  2) Brev's default VM user  3) first home dir
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  elif id ubuntu >/dev/null 2>&1; then
    TARGET_USER=ubuntu
  else
    TARGET_USER="$(ls /home | head -1)"
  fi
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
as_user() { sudo -u "$TARGET_USER" -H bash -lc "$*"; }
touch "$LOG"; chmod 644 "$LOG"
log "=== IsaacLab-Arena workshop setup: user=$TARGET_USER home=$TARGET_HOME tls=$NOVNC_TLS branch=$ARENA_BRANCH prebuild=$PREBUILD_IMAGE groot=$INSTALL_GROOT"

# ------------------------------------------------------------ 1. preflight
command -v nvidia-smi >/dev/null || { log "ERROR: nvidia-smi missing (no driver?)"; exit 1; }
command -v docker >/dev/null     || { log "ERROR: docker missing"; exit 1; }
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | tee -a "$LOG"
docker info 2>/dev/null | grep -q "Runtimes:.*nvidia" || log "WARN: nvidia container runtime not reported by docker info"
usermod -aG docker "$TARGET_USER" || true

# --------------------------------------------------------- 2. desktop stack
export DEBIAN_FRONTEND=noninteractive
log "Installing XFCE / x11vnc / noVNC ..."
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends \
  xfce4 xfce4-terminal x11vnc novnc websockify xterm dbus-x11 xauth \
  mesa-utils x11-xserver-utils git git-lfs curl openssl >>"$LOG" 2>&1
# make sure the NVIDIA X driver matching the kernel driver is present
DRV_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)
dpkg -s "xserver-xorg-video-nvidia-${DRV_MAJOR}" >/dev/null 2>&1 || \
  apt-get install -y -qq "xserver-xorg-video-nvidia-${DRV_MAJOR}" >>"$LOG" 2>&1 || \
  log "WARN: could not install xserver-xorg-video-nvidia-${DRV_MAJOR}; Xorg may fall back to software"

# ---------------------------------------------------------- 3. xorg.conf
BUSID=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader | head -1)   # 00000000:01:00.0
B=$((16#$(echo "$BUSID" | cut -d: -f2))); D=$((16#$(echo "$BUSID" | cut -d: -f3 | cut -d. -f1))); F=$(echo "$BUSID" | cut -d. -f2)
W=${SCREEN%x*}; H=${SCREEN#*x}
cat > /etc/X11/xorg.conf <<EOF
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
Section "Device"
    Identifier "Device0"
    Driver "nvidia"
    BusID "PCI:$B:$D:$F"
    Option "AllowEmptyInitialConfiguration" "True"
EndSection
Section "Monitor"
    Identifier "Monitor0"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual $W $H
    EndSubSection
EndSection
EOF
log "xorg.conf written for GPU $BUSID, virtual screen ${W}x${H}"

# --------------------------------------------- 4. VNC password + TLS cert
install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.vnc"
if [ -n "${VNC_PASSWORD:-}" ]; then
  as_user "x11vnc -storepasswd '$VNC_PASSWORD' ~/.vnc/passwd >/dev/null 2>&1 && chmod 600 ~/.vnc/passwd"
elif [ -s "$TARGET_HOME/.vnc/passwd" ]; then
  VNC_PASSWORD="(unchanged, set at first deploy)"
  log "No VNC_PASSWORD given; keeping the existing one (rerun)"
else
  VNC_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10)
  log "No VNC_PASSWORD given; generated one (see $TARGET_HOME/WORKSHOP.md)"
  as_user "x11vnc -storepasswd '$VNC_PASSWORD' ~/.vnc/passwd >/dev/null 2>&1 && chmod 600 ~/.vnc/passwd"
fi
WS_TLS_ARGS=""
if [ "$NOVNC_TLS" = "1" ]; then
  PUBIP=$(curl -s -m 5 ifconfig.me || hostname -I | awk '{print $1}')
  [ -f "$TARGET_HOME/.vnc/novnc.crt" ] || as_user "openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout ~/.vnc/novnc.key -out ~/.vnc/novnc.crt -subj '/CN=$PUBIP' -addext 'subjectAltName=IP:$PUBIP' >/dev/null 2>&1 && chmod 600 ~/.vnc/novnc.key"
  WS_TLS_ARGS="--cert $TARGET_HOME/.vnc/novnc.crt --key $TARGET_HOME/.vnc/novnc.key --ssl-only"
fi

# ------------------------------------------------- 5. start / stop scripts
# noVNC web root overlay: the bare Secure Link URL (no query string) lands on index.html, which
# redirects to vnc.html with autoconnect + scale-to-window; defaults.json applies the same to
# anyone who opens vnc.html directly.
NOVNC_WEB="$TARGET_HOME/.vnc/novnc-web"
as_user "mkdir -p '$NOVNC_WEB' && ln -sfn /usr/share/novnc/* '$NOVNC_WEB/' 2>/dev/null; rm -f '$NOVNC_WEB/index.html' '$NOVNC_WEB/defaults.json'"
cat > "$NOVNC_WEB/index.html" <<'NVEOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Workshop desktop</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000">
<script>location.replace("vnc.html?autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000" + location.hash);</script>
</head><body>Opening the desktop...</body></html>
NVEOF
cat > "$NOVNC_WEB/defaults.json" <<'NVEOF'
{ "resize": "scale", "reconnect": true, "reconnect_delay": 2000, "show_dot": true }
NVEOF
chown -R "$TARGET_USER:$TARGET_USER" "$NOVNC_WEB"

cat > "$TARGET_HOME/start-desktop.sh" <<EOF
#!/bin/bash
# GPU-backed virtual desktop: Xorg :0 -> XFCE -> x11vnc:5900 (localhost) -> noVNC:6080
pkill -x websockify 2>/dev/null; pkill -x x11vnc 2>/dev/null; sudo pkill -x Xorg 2>/dev/null; sleep 1
sudo nohup Xorg :0 -ac -config /etc/X11/xorg.conf -noreset +extension GLX +extension RANDR +extension RENDER -logfile /tmp/xorg.log > /tmp/xorg.out 2>&1 &
for i in \$(seq 1 20); do [ -S /tmp/.X11-unix/X0 ] && break; sleep 0.5; done
sudo chmod 777 /tmp/.X11-unix 2>/dev/null; sudo chmod a+rw /tmp/.X11-unix/X0 2>/dev/null
export DISPLAY=:0
xset s off -dpms 2>/dev/null || true
# the NVIDIA virtual display defaults to 1024x768; switch the output to the full virtual screen
OUT=\$(xrandr 2>/dev/null | awk '/ connected/{print \$1; exit}'); [ -n "\$OUT" ] && xrandr --output \$OUT --mode ${W}x${H} 2>/dev/null || true
nohup dbus-launch --exit-with-session startxfce4 > /tmp/xfce.log 2>&1 &
sleep 3
nohup x11vnc -display :0 -forever -shared -noxdamage -rfbport 5900 -localhost -rfbauth \$HOME/.vnc/passwd -o /tmp/x11vnc.log > /dev/null 2>&1 &
sleep 1
nohup websockify --web=$NOVNC_WEB $WS_TLS_ARGS 0.0.0.0:6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
sleep 1
echo "--- status ---"; ss -tlnp | grep -E ":5900|:6080"
DISPLAY=:0 glxinfo 2>/dev/null | grep "OpenGL renderer"
EOF
cat > "$TARGET_HOME/stop-desktop.sh" <<'EOF'
#!/bin/bash
pkill -x websockify 2>/dev/null; pkill -x x11vnc 2>/dev/null; pkill -x xfce4-session 2>/dev/null; sudo pkill -x Xorg 2>/dev/null; true
EOF
chmod +x "$TARGET_HOME"/start-desktop.sh "$TARGET_HOME"/stop-desktop.sh
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"/start-desktop.sh "$TARGET_HOME"/stop-desktop.sh
# the start script needs passwordless sudo for Xorg/chmod
echo "$TARGET_USER ALL=(ALL) NOPASSWD: /usr/bin/Xorg, /usr/bin/pkill, /usr/bin/chmod, /usr/bin/xhost" > /etc/sudoers.d/90-gpu-desktop
chmod 440 /etc/sudoers.d/90-gpu-desktop

# ------------------------------------------------------- 6. systemd unit
cat > /etc/systemd/system/gpu-desktop.service <<EOF
[Unit]
Description=GPU-backed XFCE desktop with x11vnc + noVNC on :6080
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$TARGET_USER
WorkingDirectory=$TARGET_HOME
ExecStart=$TARGET_HOME/start-desktop.sh
ExecStop=$TARGET_HOME/stop-desktop.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable gpu-desktop.service >/dev/null 2>&1
systemctl restart gpu-desktop.service || true
sleep 2
ss -tlnp | grep -q ":6080" && log "noVNC listening on 6080" || log "WARN: noVNC not listening; check /tmp/xorg.log and journalctl -u gpu-desktop"

# --------------------------------------------------------- 7. firewall
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 6080/tcp >/dev/null && log "ufw: allowed 6080/tcp"
  # BYOC nodes reset ufw from an init.sh at boot; keep the rule there too
  for f in /home/*/init.sh /root/init.sh; do
    [ -f "$f" ] && ! grep -q "ufw allow 6080/tcp" "$f" && sed -i '/^ufw allow 22\/tcp/a ufw allow 6080/tcp' "$f" && log "added 6080 to $f"
  done
fi

# --------------------------------------------- 8. clone IsaacLab-Arena
log "Cloning IsaacLab-Arena ($ARENA_BRANCH) ..."
as_user "git config --global url.'https://github.com/'.insteadOf 'git@github.com:'"
if [ ! -d "$TARGET_HOME/IsaacLab-Arena/.git" ]; then
  as_user "cd ~ && git clone --branch '$ARENA_BRANCH' --recurse-submodules '$ARENA_REPO'" >>"$LOG" 2>&1
fi
as_user "cd ~/IsaacLab-Arena && git submodule update --init --recursive" >>"$LOG" 2>&1
as_user "mkdir -p ~/datasets ~/models ~/eval"
as_user "cd ~/IsaacLab-Arena && git submodule status" | tee -a "$LOG"

# ---------------------------- 8b. standalone Isaac GR00T (workflow steps 9-12)
# The NVIDIA e2e workflow runs GR00T outside the Arena container at a pinned commit.
GROOT_COMMIT="${GROOT_COMMIT:-4b1dca9d88d2a0b9ea5a65aa61c82ff89f5c4f0e}"
if [ "${PRESETUP_GROOT:-1}" = "1" ]; then
  if ! as_user "test -x ~/.local/bin/uv || command -v uv" >/dev/null 2>&1; then
    as_user "curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh" >>"$LOG" 2>&1 || true
    as_user "test -x ~/.local/bin/uv" && log "uv installed to ~/.local/bin/uv" || log "WARN: uv install failed"
    as_user "grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
  fi
  groot_sync() {
    # the repo keeps prebuilt wheels in Git LFS; without git-lfs the clone holds pointer files and
    # `uv sync` dies with "Invalid zip file structure" on flash_attn-*.whl
    as_user "git lfs install --skip-repo" >>"$LOG" 2>&1 || true
    as_user "cd ~/Isaac-GR00T && git lfs pull --include='scripts/deployment/*/wheels/*'" >>"$LOG" 2>&1 \
      || log "WARN: git lfs pull failed in Isaac-GR00T"
    as_user "cd ~/Isaac-GR00T && export PATH=\$HOME/.local/bin:\$PATH && uv sync" >"$TARGET_HOME/uv-sync.log" 2>&1 \
      && log "Isaac-GR00T uv env ready" \
      || { log "WARN: uv sync failed for Isaac-GR00T, last lines of ~/uv-sync.log:"; tail -n 15 "$TARGET_HOME/uv-sync.log" | tee -a "$LOG"; }
  }
  if [ ! -d "$TARGET_HOME/Isaac-GR00T/.git" ]; then
    as_user "git clone https://github.com/NVIDIA/Isaac-GR00T.git ~/Isaac-GR00T" >>"$LOG" 2>&1
    as_user "cd ~/Isaac-GR00T && git checkout -q $GROOT_COMMIT" >>"$LOG" 2>&1 \
      && log "Isaac-GR00T at $GROOT_COMMIT" || log "WARN: could not checkout Isaac-GR00T commit $GROOT_COMMIT"
    groot_sync
  elif ! ls -d "$TARGET_HOME"/Isaac-GR00T/.venv/lib/python*/site-packages/torch >/dev/null 2>&1; then
    # checkout exists (earlier run) but the venv never got built: finish the job, do not touch the code
    log "Isaac-GR00T present without a venv; running lfs pull + uv sync"
    groot_sync
  else
    # never touch an existing working checkout (dev boxes may have their own work / env in it)
    log "Isaac-GR00T already present at $(as_user 'cd ~/Isaac-GR00T && git rev-parse --short HEAD') with venv; leaving it unchanged (workflow pin: ${GROOT_COMMIT:0:7})"
  fi
fi

# ------------------------------------------- 9. pre-build docker image
build_image() {  # $1 = tag, $2 = INSTALL_GROOT true|false
  log "docker build isaaclab_arena:$1 (INSTALL_GROOT=$2) — this takes 30-60+ min"
  as_user "cd ~/IsaacLab-Arena && docker build --pull --progress=plain \
      --build-arg WORKDIR=/workspaces/isaaclab_arena --build-arg INSTALL_GROOT=$2 \
      -t isaaclab_arena:$1 --file docker/Dockerfile.isaaclab_arena ." >>"$LOG" 2>&1 \
    && log "image isaaclab_arena:$1 ready" || log "ERROR: image build failed, see $LOG"
}
if [ "$PREBUILD_IMAGE" = "1" ]; then
  [ -n "$(docker images -q isaaclab_arena:latest 2>/dev/null)" ] || build_image latest false
  if [ "$INSTALL_GROOT" = "1" ]; then
    [ -n "$(docker images -q isaaclab_arena:cuda_gr00t_gn16 2>/dev/null)" ] || build_image cuda_gr00t_gn16 true
  fi
fi

# ------------------------- 9b. Unitree G1 static apple-to-plate workflow staging
# Mirrors IsaacLab-Arena docs/pages/example_workflows/static_apple (release/0.2.1):
# dataset + pre-trained checkpoint from Hugging Face, GR00T N1.7 server / finetune helpers.
G1_WORKFLOW="${G1_WORKFLOW:-1}"
if [ "$G1_WORKFLOW" = "1" ]; then
  DS_DIR="$TARGET_HOME/datasets/isaaclab_arena/static_apple_tutorial"
  MD_DIR="$TARGET_HOME/models/isaaclab_arena/static_apple_tutorial"
  CKPT_DIR="$MD_DIR/gn1x_tuned_static_apple"
  as_user "mkdir -p '$DS_DIR' '$MD_DIR'"
  # standalone `hf` CLI (uv tool), so downloads do not depend on the Isaac-GR00T venv
  if ! as_user "test -x ~/.local/bin/hf"; then
    as_user "export PATH=\$HOME/.local/bin:\$PATH && uv tool install -q 'huggingface_hub[cli]'" >>"$LOG" 2>&1 \
      || as_user "python3 -m pip install -q --user 'huggingface_hub[cli]'" >>"$LOG" 2>&1 || true
  fi
  as_user "test -x ~/.local/bin/hf" && log "hf CLI: $(as_user '~/.local/bin/hf version 2>/dev/null | head -1')" || log "WARN: hf CLI not installed; downloads will fail"
  HF="export PATH=\$HOME/.local/bin:\$PATH && hf"

  # Hugging Face token (token file, same thing `hf auth login` writes)
  if [ -n "${HF_TOKEN:-}" ]; then
    as_user "mkdir -p ~/.cache/huggingface && umask 077 && printf '%s' '$HF_TOKEN' > ~/.cache/huggingface/token"
  fi
  HF_LOGGED_IN=0
  if [ -s "$TARGET_HOME/.cache/huggingface/token" ]; then
    as_user "$HF auth whoami" >>"$LOG" 2>&1 && { HF_LOGGED_IN=1; log "Hugging Face login OK ($(as_user "$HF auth whoami 2>/dev/null | grep -o 'user: .*'"))"; } \
      || log "WARN: Hugging Face token rejected by huggingface.co"
  else
    log "No HF token: the gated backbone nvidia/Cosmos-Reason2-2B cannot be pre-cached; run 'hf auth login' on the node and rerun"
  fi

  # Dataset: 200 recorded demos (HDF5) + the same data pre-converted to LeRobot format
  if [ "${DOWNLOAD_DATASET:-1}" = "1" ] && [ ! -f "$DS_DIR/arena_g1_static_apple_dataset_recorded.hdf5" ]; then
    log "Downloading nvidia/Arena-G1-Static-PickNPlace-Task to $DS_DIR (~10 GB) ..."
    as_user "$HF download nvidia/Arena-G1-Static-PickNPlace-Task --repo-type dataset --local-dir '$DS_DIR'" >>"$LOG" 2>&1 \
      && as_user "cd '$DS_DIR' && ln -sf arena_g1_static_apple_dataset_recorded_200_demos.hdf5 arena_g1_static_apple_dataset_recorded.hdf5 && mkdir -p arena_g1_static_apple_dataset_recorded && [ -e arena_g1_static_apple_dataset_recorded/lerobot ] || ln -s ../lerobot arena_g1_static_apple_dataset_recorded/lerobot" \
      && log "dataset ready: $DS_DIR (hdf5 + lerobot/)" || log "WARN: dataset download failed"
  fi

  # Pre-trained GR00T N1.7 checkpoint (skip the 16 GB optimizer state and 13 GB ONNX exports)
  if [ "${DOWNLOAD_CHECKPOINT:-1}" = "1" ] && [ ! -f "$CKPT_DIR/model.safetensors.index.json" ]; then
    log "Downloading nvidia/GN1x-Tuned-Arena-G1-Static-PickNPlace to $CKPT_DIR (~13 GB) ..."
    as_user "$HF download nvidia/GN1x-Tuned-Arena-G1-Static-PickNPlace --repo-type model --local-dir '$CKPT_DIR' --exclude 'optimizer.pt' --exclude 'exports/*'" >>"$LOG" 2>&1 \
      && log "checkpoint ready: $CKPT_DIR" || log "WARN: checkpoint download failed"
  fi

  # Pre-cache the models GR00T loads from the hub at runtime, so nobody needs a token later.
  # transformers/huggingface_hub fall back to the cached snapshot when the hub HEAD request fails (401 without token).
  if [ "${PRECACHE_MODELS:-1}" = "1" ]; then
    if [ ! -d "$TARGET_HOME/.cache/huggingface/hub/models--nvidia--GR00T-N1.7-3B/snapshots" ]; then
      log "Pre-caching nvidia/GR00T-N1.7-3B (~7 GB, public) ..."
      as_user "$HF download nvidia/GR00T-N1.7-3B --repo-type model" >>"$LOG" 2>&1 \
        && log "base model cached" || log "WARN: base model download failed"
    fi
    if [ ! -d "$TARGET_HOME/.cache/huggingface/hub/models--nvidia--Cosmos-Reason2-2B/snapshots" ]; then
      if [ "$HF_LOGGED_IN" = "1" ]; then
        log "Pre-caching nvidia/Cosmos-Reason2-2B (~5 GB, gated) ..."
        as_user "$HF download nvidia/Cosmos-Reason2-2B --repo-type model" >>"$LOG" 2>&1 \
          && log "backbone cached: GR00T server/finetune will not need the hub" \
          || log "WARN: backbone download failed (did this HF account accept the Cosmos-Reason2-2B license?)"
      else
        log "WARN: backbone nvidia/Cosmos-Reason2-2B NOT cached (not logged in to Hugging Face)"
      fi
    fi
  fi
  # Optional: remove the token after caching (use when the organizer supplied it, not the participant)
  if [ -n "${HF_TOKEN:-}" ] && [ "${KEEP_HF_TOKEN:-1}" = "0" ]; then
    as_user "rm -f ~/.cache/huggingface/token ~/.huggingface/token" && log "HF token file removed"
  fi

  # Point Arena's client config at the served checkpoint (container path; ~/models is mounted at /models)
  Y="$TARGET_HOME/IsaacLab-Arena/isaaclab_arena_gr00t/policy/config/g1_static_apple_gr00t_closedloop_config.yaml"
  [ -f "$Y" ] && as_user "cp -n '$Y' '$Y.orig'; sed -i 's|^model_path:.*|model_path: /models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple|' '$Y'"

  # Helper scripts (all run on the HOST; the client/convert ones exec into the running Arena container)
  cat > "$TARGET_HOME/run_gr00t_server.sh" <<'EOF'
#!/bin/bash
# GR00T N1.7 policy server (host). Usage: ~/run_gr00t_server.sh [model_dir]
# Default model: the pre-trained static-apple checkpoint. Pass your finetune dir to serve your own,
# e.g. ~/run_gr00t_server.sh ~/models/isaaclab_arena/static_apple_tutorial/static_apple_n17_finetune/checkpoint-20000
export PATH=$HOME/.local/bin:$PATH
MODEL=${1:-$HOME/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple}
cd ~/Isaac-GR00T
exec uv run --no-sync python gr00t/eval/run_gr00t_server.py \
  --modality-config-path $HOME/IsaacLab-Arena/isaaclab_arena_gr00t/embodiments/g1/g1_sim_wbc_data_gr00t_n_1_7_config.py \
  --model-path "$MODEL" --embodiment-tag NEW_EMBODIMENT --device cuda --host 0.0.0.0 --port 5555
EOF
  cat > "$TARGET_HOME/run_g1_apple_client.sh" <<'EOF'
#!/bin/bash
# Arena client with Kit GUI on the browser desktop (host). Usage: ~/run_g1_apple_client.sh [num_episodes] [model_dir_in_container]
# Requires: ./docker/run_docker.sh started once (container isaaclab_arena-latest) and the server printing "Server Ready".
N=${1:-5}; MODEL=${2:-/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple}
Y=isaaclab_arena_gr00t/policy/config/g1_static_apple_gr00t_closedloop_config.yaml
docker exec -it -e DISPLAY=:0 isaaclab_arena-latest bash -c "cd /workspaces/isaaclab_arena && sed -i 's|^model_path:.*|model_path: $MODEL|' $Y && /isaac-sim/python.sh isaaclab_arena/evaluation/policy_runner.py \
  --viz kit --policy_type isaaclab_arena_gr00t.policy.gr00t_remote_closedloop_policy.Gr00tRemoteClosedloopPolicy \
  --policy_config_yaml_path $Y --remote_host localhost --remote_port 5555 --num_episodes $N --enable_cameras \
  galileo_g1_static_pick_and_place --object apple_01_objaverse_robolab --destination clay_plates_hot3d_robolab --embodiment g1_wbc_agile_joint"
EOF
  cat > "$TARGET_HOME/run_g1_convert.sh" <<'EOF'
#!/bin/bash
# Convert the recorded HDF5 to LeRobot format inside the Arena container (only needed for your OWN recordings;
# the downloaded dataset already ships a lerobot/ folder).
docker exec -it isaaclab_arena-latest bash -c "cd /workspaces/isaaclab_arena && /isaac-sim/python.sh isaaclab_arena_gr00t/lerobot/convert_hdf5_to_lerobot.py --yaml_file isaaclab_arena_gr00t/lerobot/config/g1_static_apple_config.yaml"
EOF
  cat > "$TARGET_HOME/run_g1_finetune.sh" <<'EOF'
#!/bin/bash
# Post-train GR00T N1.7 on the static apple dataset (host, standalone Isaac-GR00T venv).
# Usage: ~/run_g1_finetune.sh [max_steps] [output_dir]     e.g. ~/run_g1_finetune.sh 1000 for a live-workshop demo
# Docs: 20000 steps take ~2-3 h on an RTX 6000 Ada; checkpoints land in <output_dir>/checkpoint-<step>.
export PATH=$HOME/.local/bin:$PATH
STEPS=${1:-20000}
# save at least once: a 1000-step live run must still leave a checkpoint-1000 to evaluate
SAVE=$(( STEPS < 5000 ? STEPS : 5000 ))
DATASET_DIR=$HOME/datasets/isaaclab_arena/static_apple_tutorial
MODELS_DIR=$HOME/models/isaaclab_arena/static_apple_tutorial
OUT=${2:-$MODELS_DIR/static_apple_n17_finetune}
cd ~/Isaac-GR00T
exec uv run --no-sync python -m torch.distributed.run --nproc_per_node=1 --standalone \
  gr00t/experiment/launch_finetune.py \
  --base-model-path nvidia/GR00T-N1.7-3B \
  --dataset-path $DATASET_DIR/arena_g1_static_apple_dataset_recorded/lerobot \
  --output-dir "$OUT" \
  --modality-config-path $HOME/IsaacLab-Arena/isaaclab_arena_gr00t/embodiments/g1/g1_sim_wbc_data_gr00t_n_1_7_config.py \
  --embodiment-tag new_embodiment \
  --global-batch-size 12 --max-steps "$STEPS" --num-gpus 1 \
  --save-steps "$SAVE" --save-total-limit 5 \
  --no-tune-llm --tune-visual --tune-projector --tune-diffusion-model \
  --dataloader-num-workers 8 \
  --color-jitter-params brightness 0.3 contrast 0.4 saturation 0.5 hue 0.08
EOF
  chmod +x "$TARGET_HOME"/run_gr00t_server.sh "$TARGET_HOME"/run_g1_apple_client.sh "$TARGET_HOME"/run_g1_convert.sh "$TARGET_HOME"/run_g1_finetune.sh
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"/run_g1_*.sh "$TARGET_HOME"/run_gr00t_server.sh
  log "G1 workflow helpers written: run_gr00t_server.sh, run_g1_apple_client.sh, run_g1_convert.sh, run_g1_finetune.sh"
fi

# SSH shells have no DISPLAY; run_docker.sh calls xhost and Kit windows must land on the desktop
as_user "grep -q 'export DISPLAY=:0' ~/.bashrc || printf '\n# IsaacLab-Arena workshop: GUI apps go to the browser desktop\nexport DISPLAY=:0\n' >> ~/.bashrc"

# ------------------------------------------------- 10. attendee README
PUBIP=$(curl -s -m 5 ifconfig.me || hostname -I | awk '{print $1}')
if [ "$NOVNC_TLS" = "1" ]; then URL="https://$PUBIP:6080/"; else URL="the Brev Secure Link 'desktop' (or http://$PUBIP:6080/)"; fi
cat > "$TARGET_HOME/WORKSHOP.md" <<EOF
# IsaacLab-Arena workshop node

Desktop in your browser: $URL
VNC password: $VNC_PASSWORD

Inside the desktop, open a terminal and run:

    cd ~/IsaacLab-Arena
    ./docker/run_docker.sh          # drops you into the Arena container (GUI-enabled)

Then, inside the container (runner options before the environment name, environment options after):

    python isaaclab_arena/evaluation/policy_runner.py --policy_type zero_action --viz kit --num_steps 3000 \\
      pick_and_place_maple_table --embodiment droid_rel_joint_pos --hdr home_office_robolab

The Isaac Lab window opens on this desktop (3-5 min on first launch). Ctrl-C in the terminal stops it.
Headless test: python -m pytest isaaclab_arena/tests/test_g1_static_pick_and_place.py -v

## Unitree G1 apple-to-plate: GR00T N1.7 training + evaluation (see WORKSHOP-G1.md)

Hugging Face: the HF_TOKEN you entered at deploy time is already logged in on this node and the
gated backbone nvidia/Cosmos-Reason2-2B is cached (check: ls ~/.cache/huggingface/hub). If you
deployed without a token: accept https://huggingface.co/nvidia/Cosmos-Reason2-2B, then
    hf auth login && hf download nvidia/Cosmos-Reason2-2B

    ~/run_gr00t_server.sh                      # host, terminal 2: serves the pre-trained checkpoint, wait for "Server Ready"
    ~/run_g1_apple_client.sh 5                 # host, terminal 3: G1 does the task in the Isaac Lab window, prints success_rate
    ~/run_g1_finetune.sh 1000 ~/models/isaaclab_arena/static_apple_tutorial/my_finetune   # stop the server first (Ctrl-C)
    ~/run_gr00t_server.sh ~/models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-1000
    ~/run_g1_apple_client.sh 5 /models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-1000

Dataset (200 demos, HDF5 + LeRobot): ~/datasets/isaaclab_arena/static_apple_tutorial
Pre-trained checkpoint:              ~/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple

Housekeeping: ~/start-desktop.sh / ~/stop-desktop.sh, service gpu-desktop, log $LOG
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/WORKSHOP.md"; chmod 600 "$TARGET_HOME/WORKSHOP.md"
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$KIT_DIR/WORKSHOP-G1.md" ] && install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "$KIT_DIR/WORKSHOP-G1.md" "$TARGET_HOME/WORKSHOP-G1.md"
log "=== DONE. Attendee instructions in $TARGET_HOME/WORKSHOP.md"
