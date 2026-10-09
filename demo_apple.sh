#!/bin/bash
# One-command G1 apple pick-and-place demo: Arena container + GR00T N1.7 policy server + Isaac Sim
# client with the Kit GUI on the browser desktop (noVNC, port 6080).
# Usage: ~/demo_apple.sh [num_episodes] [model_dir_in_container]      default: 3 episodes, pre-trained checkpoint
#        ~/demo_apple.sh 5 /models/isaaclab_arena/static_apple_tutorial/static_apple_n17_finetune/checkpoint-1000
#        ~/demo_apple.sh stop        # stop the GR00T server and the Arena container
# Idempotent: reuses a running container / server. Logs: /tmp/arena-container.log ~/gr00t_server.log /tmp/demo_client.log
set -u
export DISPLAY=:0
C=isaaclab_arena-latest
PORT=${GR00T_PORT:-5557}   # 5555 is taken by DCGM (nv-hostengine) on some cloud images
say() { echo "[demo $(date +%H:%M:%S)] $*"; }
if [ "${1:-}" = "stop" ]; then
  pkill -f run_gr00t_server.py 2>/dev/null; docker rm -f $C >/dev/null 2>&1; say "GR00T server and Arena container stopped"; exit 0
fi
N=${1:-3}; MODEL=${2:-/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple}
HOSTMODEL=${MODEL/#\/models/$HOME/models}
[ -d "$HOSTMODEL" ] || { say "model dir not found on host: $HOSTMODEL"; exit 1; }

# 1. Arena container (run_docker.sh wants a tty, so start it detached under `script`)
if ! docker ps --format '{{.Names}}' | grep -qx "$C"; then
  say "starting Arena container ..."
  docker rm -f "$C" >/dev/null 2>&1
  ( cd ~/IsaacLab-Arena && setsid script -qfc "./docker/run_docker.sh" /dev/null >/tmp/arena-container.log 2>&1 </dev/null & )
  for _ in $(seq 1 60); do docker ps --format '{{.Names}}' | grep -qx "$C" && break; sleep 2; done
  docker ps --format '{{.Names}}' | grep -qx "$C" || { say "container did not start, see /tmp/arena-container.log"; exit 1; }
  sleep 3
fi
say "Arena container up"

# 2. GR00T policy server on the host (port $PORT), ~1 min to load
if pgrep -f run_gr00t_server.py >/dev/null && ss -tln | grep -q ":$PORT "; then
  say "GR00T server already listening on $PORT (serving whatever it was started with; '~/demo_apple.sh stop' to change model)"
else
  say "starting GR00T N1.7 server for $HOSTMODEL (log: ~/gr00t_server.log) ..."
  ss -tln | grep -q ":$PORT " && { say "port $PORT is busy: $(sudo ss -tlnp | grep ":$PORT " | grep -o "users:.*")"; exit 1; }
  nohup "$HOME/run_gr00t_server.sh" "$HOSTMODEL" >"$HOME/gr00t_server.log" 2>&1 &
  for _ in $(seq 1 100); do ss -tln | grep -q ":$PORT " && break; pgrep -f run_gr00t_server.py >/dev/null || break; sleep 3; done
  ss -tln | grep -q ":$PORT " || { say "server failed, last lines of ~/gr00t_server.log:"; tail -n 15 "$HOME/gr00t_server.log"; exit 1; }
fi
say "GR00T server ready"

# 3. Isaac Sim client with the Kit GUI (first launch ~1-4 min: shaders + asset download)
say "launching Isaac Sim client: $N episode(s); the window appears on the browser desktop"
if [ -t 0 ]; then
  "$HOME/run_g1_apple_client.sh" "$N" "$MODEL" 2>&1 | tee /tmp/demo_client.log
else
  script -qfc "$HOME/run_g1_apple_client.sh $N $MODEL" /dev/null >/tmp/demo_client.log 2>&1
fi
M=$(grep -a -o -E "Metrics: \{[^}]*\}" /tmp/demo_client.log | tail -1)
say "client finished. ${M:-no Metrics line found, see /tmp/demo_client.log}"
say "server and container left running for the next run; '~/demo_apple.sh stop' to shut them down"
