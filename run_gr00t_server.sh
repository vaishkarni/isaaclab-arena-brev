#!/bin/bash
# GR00T N1.7 policy server for the G1 static apple-to-plate task (run on the HOST, not in Docker).
# Needs HF access to nvidia/Cosmos-Reason2-2B: accept the license on huggingface.co,
# then run once:  cd ~/Isaac-GR00T && uv run --no-sync hf auth login
export PATH=$HOME/.local/bin:$PATH
cd ~/Isaac-GR00T
exec uv run --no-sync python gr00t/eval/run_gr00t_server.py \
  --modality-config-path $HOME/IsaacLab-Arena/isaaclab_arena_gr00t/embodiments/g1/g1_sim_wbc_data_gr00t_n_1_7_config.py \
  --model-path $HOME/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple \
  --embodiment-tag NEW_EMBODIMENT --device cuda --host 0.0.0.0 --port 5555
