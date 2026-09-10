#!/bin/bash
# Arena client: G1 apple-to-plate with the remote GR00T policy, Kit GUI on the browser desktop.
# Run on the HOST after the server prints "Server Ready". Uses the already-running Arena container.
# Usage: ~/run_g1_apple_client.sh [num_episodes]   (default 5)
docker exec -it -e DISPLAY=:0 isaaclab_arena-latest bash -c "cd /workspaces/isaaclab_arena && /isaac-sim/python.sh isaaclab_arena/evaluation/policy_runner.py \
  --viz kit \
  --policy_type isaaclab_arena_gr00t.policy.gr00t_remote_closedloop_policy.Gr00tRemoteClosedloopPolicy \
  --policy_config_yaml_path isaaclab_arena_gr00t/policy/config/g1_static_apple_gr00t_closedloop_config.yaml \
  --remote_host localhost --remote_port 5555 \
  --num_episodes ${1:-5} --enable_cameras \
  galileo_g1_static_pick_and_place --object apple_01_objaverse_robolab --destination clay_plates_hot3d_robolab --embodiment g1_wbc_agile_joint"
