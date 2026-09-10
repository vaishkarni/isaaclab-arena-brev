#!/bin/bash
# Organizer self-test: runs WORKSHOP-G1.md steps 2, 2b, 4, 5 unattended on a built node (~18 min). Usage: bash ~/isaaclab-arena-brev/validate-pipeline.sh > ~/sheet.log 2>&1
set -u
export PATH=$HOME/.local/bin:$PATH
say() { echo "[$(date +%H:%M:%S)] $*"; }
say "STEP 2 pytest"
docker exec isaaclab_arena-latest bash -c "cd /workspaces/isaaclab_arena && /isaac-sim/python.sh -m pytest isaaclab_arena/tests/test_g1_static_pick_and_place.py -v" 2>&1 | grep -E "passed|failed|error" | tail -1
say "STEP 2b convert"
script -qfc "$HOME/run_g1_convert.sh" /dev/null > /tmp/convert.out 2>&1; tail -c 200 /tmp/convert.out | tr "\r" "\n" | grep -v "^$" | tail -1
ls $HOME/datasets/isaaclab_arena/static_apple_tutorial/arena_g1_static_apple_dataset_recorded/lerobot/meta | tr "\n" " "; echo
say "STEP 4 finetune 1000"
$HOME/run_g1_finetune.sh 1000 $HOME/models/isaaclab_arena/static_apple_tutorial/my_finetune > /tmp/finetune.out 2>&1
grep -a -E "Training completed|Traceback|Error" /tmp/finetune.out | tail -1; ls -d $HOME/models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-* 2>/dev/null
say "STEP 5 serve + eval own checkpoint"
$HOME/run_gr00t_server.sh $HOME/models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-1000 > /tmp/server.out 2>&1 &
SRV=$!
for i in $(seq 1 90); do ss -tln | grep -q ":5555" && break; sleep 3; done
ss -tln | grep -q ":5555" && say "server listening" || { say "SERVER FAILED"; tail -5 /tmp/server.out; }
script -qfc "$HOME/run_g1_apple_client.sh 5 /models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-1000" /dev/null > /tmp/client.out 2>&1
grep -a -o -E "Metrics: \{[^}]*\}" /tmp/client.out | tail -1
kill $SRV 2>/dev/null; sleep 2; pkill -f run_gr00t_server.py 2>/dev/null
say "ALL DONE"
