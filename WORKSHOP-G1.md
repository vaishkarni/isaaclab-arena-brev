# Workshop: Unitree G1 apple-to-plate with Isaac Lab-Arena and GR00T N1.7

Participant hands-on sheet. Your Brev node already has everything installed by the launchable:
Isaac Lab-Arena 0.2.1 in Docker, the standalone Isaac-GR00T checkout with its `uv` environment,
the 200-demo dataset, and NVIDIA's pre-trained checkpoint. You will (1) validate the environment,
(2) watch the pre-trained policy do the task, (3) post-train your own GR00T N1.7 policy, and
(4) evaluate it in simulation. Follows NVIDIA's GR00T simulation workflow
(https://docs.nvidia.com/learning/physical-ai/gr00t-e2e-workflow/latest/simulation-workflow/).

## 0. Open your desktop (2 min)

Open the `desktop` Secure Link for your instance, sign in with your Brev account, enter the VNC
password from the organizer. You get a Linux desktop. Open a terminal: Applications -> Terminal.
Every command below runs in a terminal on this desktop unless it says otherwise. You will use
three terminals; open them as tabs.

## 1. One-time Hugging Face login (3 min)

GR00T N1.7 loads the gated backbone `nvidia/Cosmos-Reason2-2B`, so training and serving both need
a Hugging Face account that accepted its license.

1. On your own laptop: https://huggingface.co/nvidia/Cosmos-Reason2-2B -> accept the license.
2. https://huggingface.co/settings/tokens -> create a read token, copy it.
3. On the desktop terminal:

```bash
cd ~/Isaac-GR00T && uv run --no-sync hf auth login      # paste the token, answer n to git credential
uv run --no-sync hf auth whoami                          # prints your username
```

Skip this if the organizer deployed the node with an HF_TOKEN; `whoami` tells you.

## 2. Validate the environment (5 min) — terminal 1

```bash
cd ~/IsaacLab-Arena && ./docker/run_docker.sh
```

You are now inside the Arena container (prompt changes). Run the headless test from the docs:

```bash
export DATASET_DIR=/datasets/isaaclab_arena/static_apple_tutorial
export MODELS_DIR=/models/isaaclab_arena/static_apple_tutorial
python -m pytest isaaclab_arena/tests/test_g1_static_pick_and_place.py -v     # ~2 min, expect "2 passed"
```

If the apple falls through the shelf on the first run, run it once more (asset cache warm-up).
Keep this terminal open: the helper scripts in the next steps exec into this container.

The dataset is already in place. Look at it:

```bash
ls -lh $DATASET_DIR                     # arena_g1_static_apple_dataset_recorded.hdf5 + lerobot/
ls $DATASET_DIR/lerobot/meta            # info.json, modality.json, episodes.jsonl ...
```

`arena_g1_static_apple_dataset_recorded.hdf5` is the 200 teleoperated demos from
`nvidia/Arena-G1-Static-PickNPlace-Task`; `lerobot/` is the same data already converted with
`convert_hdf5_to_lerobot.py`. If you record your own demos later, `~/run_g1_convert.sh` does the
conversion.

## 3. Watch the pre-trained policy (10 min) — terminals 2 and 3

Terminal 2 (host, not in the container):

```bash
~/run_gr00t_server.sh
```

This starts `gr00t/eval/run_gr00t_server.py` on the checkpoint
`nvidia/GN1x-Tuned-Arena-G1-Static-PickNPlace`. Wait for
`Server Ready and listening on 0.0.0.0:5555` (about 2 min, loads 12 GB of weights).

Terminal 3 (host):

```bash
~/run_g1_apple_client.sh 5
```

This runs Arena's `policy_runner.py` with `Gr00tRemoteClosedloopPolicy`, `--viz kit`, 5 episodes,
embodiment `g1_wbc_agile_joint`. An Isaac Lab window opens on the desktop (3-5 min the first time,
shaders compile). Watch the G1 move the apple to the plate. At the end the terminal prints:

```
[Rank 0/1] Metrics: {'success_rate': ..., 'object_moved_rate': ..., 'num_episodes': 5}
```

Leave the server running for now; step 5 restarts it on your own checkpoint.

## 4. Post-train your own GR00T N1.7 policy (20 min live, 2-3 h full) — terminal 2

Stop the server with Ctrl-C in terminal 2 so the GPU is free, then:

```bash
~/run_g1_finetune.sh 1000 ~/models/isaaclab_arena/static_apple_tutorial/my_finetune
```

This is the documented `launch_finetune.py` recipe: base model `nvidia/GR00T-N1.7-3B` (downloaded
on first run, ~7 GB), Arena's `g1_sim_wbc_data_gr00t_n_1_7_config.py` as the modality config,
embodiment tag `new_embodiment`, batch 12, action horizon 40, tuning the visual backbone, projector
and diffusion head with the LLM frozen. The first argument is the number of steps: 1000 for the live
session (about 15-20 min on this GPU), 20000 for the full recipe from the docs (2-3 h, run it after
the session or overnight). A checkpoint lands at `.../my_finetune/checkpoint-1000`.

What to watch: the loss printed every few steps should trend down; GPU memory in `nvidia-smi`
sits around 40-50 GB.

## 5. Evaluate your checkpoint (10 min) — terminals 2 and 3

Terminal 2:

```bash
~/run_gr00t_server.sh ~/models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-1000
```

Terminal 3, once it prints Server Ready:

```bash
~/run_g1_apple_client.sh 5 /models/isaaclab_arena/static_apple_tutorial/my_finetune/checkpoint-1000
```

Compare `success_rate` with step 3. After 1000 steps it is normally lower than the pre-trained
checkpoint; that gap is the point: the released checkpoint was trained for 20000 steps on this
data. For a statistically useful number use more episodes, e.g. `~/run_g1_apple_client.sh 100`.

Parallel evaluation: edit the helper or run the docs command with `--num_envs 5`.

## 6. Where things are

| Item | Host path | In the Arena container |
|---|---|---|
| Isaac Lab-Arena 0.2.1 | `~/IsaacLab-Arena` | `/workspaces/isaaclab_arena` |
| Isaac-GR00T (commit 4b1dca9) + venv | `~/Isaac-GR00T` | not used inside |
| Dataset (HDF5 + LeRobot) | `~/datasets/isaaclab_arena/static_apple_tutorial` | `/datasets/isaaclab_arena/static_apple_tutorial` |
| Pre-trained checkpoint | `~/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple` | `/models/isaaclab_arena/static_apple_tutorial/gn1x_tuned_static_apple` |
| Your finetune | `~/models/isaaclab_arena/static_apple_tutorial/my_finetune` | `/models/isaaclab_arena/static_apple_tutorial/my_finetune` |
| Helpers | `~/run_gr00t_server.sh`, `~/run_g1_apple_client.sh`, `~/run_g1_finetune.sh`, `~/run_g1_convert.sh` | |

Each helper is a few lines; `cat` it to see the exact docs command it runs.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `401` / gated repo error from the server or finetune | Step 1 not done: accept the Cosmos-Reason2-2B license and `hf auth login`. |
| `Invalid action shape, expected: 23, received: 50` | Client embodiment must be `g1_wbc_agile_joint` (the helper already does this). |
| `Action key 'left_arm''s horizon must be 40` | Server modality config and checkpoint disagree; use the same `--modality-config-path` for training and serving (the helpers do). |
| No Isaac Lab window | Inside the container `echo $DISPLAY` must print `:0`. Start the container from a desktop terminal, not from SSH. |
| `docker exec` says no container `isaaclab_arena-latest` | Step 2 not running; start `./docker/run_docker.sh` in terminal 1. |
| CUDA out of memory during finetune | Stop the GR00T server first; or lower `--global-batch-size` in `~/run_g1_finetune.sh`. |
| Apple falls through the shelf | Re-run once; first-run asset cache. |
