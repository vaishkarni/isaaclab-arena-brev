# Runbook: Unitree G1 static apple-to-plate on the Brev launchable

Follows IsaacLab-Arena release/0.2.1 `docs/pages/example_workflows/static_apple` (environment
setup, teleop, GR00T N1.7 post-training, evaluation) and the NVIDIA GR00T e2e simulation
workflow. Everything below assumes the node was deployed from the launchable with
`G1_WORKFLOW=1` and a valid `HF_TOKEN`.

## What the setup script leaves on the node

| Item | Path on host | Path in Arena container |
|---|---|---|
| IsaacLab-Arena release/0.2.1 + submodules, image `isaaclab_arena:latest` | `~/IsaacLab-Arena` | `/workspaces/isaaclab_arena` |
| Standalone Isaac-GR00T (N1.7, commit 4b1dca9) with `uv` venv | `~/Isaac-GR00T` | not needed inside |
| Dataset: 200 demos HDF5 + LeRobot conversion | `~/datasets/isaaclab_arena/static_apple_tutorial/` | `/datasets/isaaclab_arena/static_apple_tutorial/` |
| Pre-trained checkpoint (weights only, ~13 GB) | `~/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple` | `/models/.../gn1x_tuned_static_apple` |
| Browser desktop (noVNC 6080) | systemd `gpu-desktop` | container windows land on `:0` |
| Helpers | `~/run_gr00t_server.sh`, `~/run_g1_apple_client.sh`, `~/run_g1_finetune.sh`, `~/run_g1_convert.sh` | |

## Prerequisites the organizer must handle before deploy

1. A Hugging Face account that has **accepted the license of `nvidia/Cosmos-Reason2-2B`**
   (gated). Every GR00T N1.7 checkpoint loads this backbone, so the server and the finetune both
   need it. Dataset and the tuned checkpoint are public.
2. A read token from that account, passed as the `HF_TOKEN` launch parameter (mark secret).
   The script uses it once to pre-cache the backbone (and the public GR00T-N1.7-3B base model)
   in `~/.cache/huggingface`, then deletes the token file. Participants never log in to HF.
   Without it the script still builds everything else and logs a warning.
3. GPU with 48 GB or more for finetuning (docs validated on RTX 6000 Ada; RTX PRO 6000 works).
   Disk 300 GB or more: image 27 GB, dataset 10 GB, checkpoint 13 GB, base model 7 GB, finetune output up to 5 x 15 GB.

## Session flow (per participant node)

### 0. Open the desktop (2 min)
Secure Link `desktop` (or `https://<ip>:6080/vnc.html`), VNC password, open a terminal.

### 1. Validate the environment (5 min) - step 1 of the workflow
```
cd ~/IsaacLab-Arena && export DISPLAY=:0 && ./docker/run_docker.sh
python -m pytest isaaclab_arena/tests/test_g1_static_pick_and_place.py -v   # ~2 min, 2 passed
```
Keep this container shell open; the helpers `docker exec` into it.

### 2. See the pre-trained policy do the task in the GUI (10 min) - step 4 of the workflow
Second terminal on the host:
```
~/run_gr00t_server.sh            # loads 12 GB of weights, prints "Server Ready and listening on 0.0.0.0:5555"
```
Third terminal on the host:
```
~/run_g1_apple_client.sh 5       # Isaac Lab window opens on the desktop; prints success_rate at the end
```
The GR00T server keeps the model resident, so re-running the client is fast.

### 3. Dataset walkthrough (5 min) - step 2/3 of the workflow
Teleop recording needs a Quest/Pico headset and CloudXR, so the workshop uses the released
200-demo dataset instead. Show:
```
ls -lh ~/datasets/isaaclab_arena/static_apple_tutorial/
ls ~/datasets/isaaclab_arena/static_apple_tutorial/lerobot/videos/chunk-000/observation.images.ego_view | head
```
The HDF5 to LeRobot conversion (`~/run_g1_convert.sh`) is only needed for participants' own recordings.

### 4. Post-train GR00T N1.7 (live: 15-25 min for a short run) - step 3 of the workflow
Stop the server first (Ctrl-C) so the GPU is free, then:
```
~/run_g1_finetune.sh 1000 ~/models/isaaclab_arena/static_apple_tutorial/workshop_finetune
```
- Full recipe is 20000 steps, 2-3 h. Suggest 1000 steps live to see the loop run and a
  `checkpoint-1000` appear; leave 20000 as homework or pre-run it the night before.
- First run downloads the base model `nvidia/GR00T-N1.7-3B` (~7 GB) into the HF cache.

### 5. Evaluate the participant's checkpoint (10 min)
```
~/run_gr00t_server.sh ~/models/isaaclab_arena/static_apple_tutorial/workshop_finetune/checkpoint-1000
~/run_g1_apple_client.sh 5 /models/isaaclab_arena/static_apple_tutorial/workshop_finetune/checkpoint-1000
```
Compare `success_rate` with the pre-trained checkpoint from step 2 (expect it to be lower after 1000 steps; that is the teaching point).

## Launchable settings that change for this workflow

Same as the base organizer guide, plus:

| Setting | Value |
|---|---|
| Disk | 300 GiB or more |
| Launch parameter `HF_TOKEN` | Text, secret, required |
| Launch parameter `G1_WORKFLOW` | Choice 1/0, default 1 |
| Launch parameter `DOWNLOAD_DATASET`, `DOWNLOAD_CHECKPOINT` | Choice 1/0, default 1 |
| Build time | 60-90 min image build + ~5 min downloads on a fast node |

## Known gotchas (verified on the dev node, 2026-09-09)

- Run the client as the container's root (default for `docker exec`); running as the mapped
  user broke asset loading with "No contact sensors added to the prim ... maple_table".
- `policy_runner` options go before the environment name; environment options after.
- `python` in the container is an alias for `/isaac-sim/python.sh`; `docker exec` needs the full path.
- The in-process `Gr00tClosedloopPolicy` (DROID example) needs the GR00T-flavored image
  (`./docker/run_docker.sh -g`, +45 min). The remote-policy path above needs only the base image.
- The N1.7 server does not know the N1.6 `OXE_DROID` embodiment tag; keep the workshop on the G1 task.
