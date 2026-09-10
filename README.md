# IsaacLab-Arena on NVIDIA Brev — workshop launchable kit

Template for a Brev Launchable that gives every participant a GPU-backed Linux desktop in the
browser (XFCE over noVNC, port 6080) with IsaacLab-Arena 0.2.1 / Isaac Sim 6.0 pre-built, so
the Isaac Sim GUI opens right on that desktop. Follows NVIDIA's
[GR00T simulation workflow: Setup Isaac Lab-Arena](https://docs.nvidia.com/learning/physical-ai/gr00t-e2e-workflow/latest/simulation-workflow/sim-setup-isaac-lab-arena.html).

## Use as a Launchable

Paste `launchable-setup.sh` as the setup script (VM Mode). It clones this repo and runs
`brev-setup.sh`. Full console walkthrough: [STEPS-create-launchable.md](STEPS-create-launchable.md).

```bash
#!/bin/bash
set -euo pipefail
git clone -q https://github.com/vaishkarni/-isaaclab-arena-brev.git "$HOME/isaaclab-arena-brev"
sudo -E bash "$HOME/isaaclab-arena-brev/brev-setup.sh"
```

Launch parameters (all optional except the first): `VNC_PASSWORD`, `PREBUILD_IMAGE` (1),
`INSTALL_GROOT` (0), `NOVNC_TLS` (0), `ARENA_BRANCH` (release/0.2.1), `G1_WORKFLOW` (1),
`HF_TOKEN`, `DOWNLOAD_DATASET` (1), `DOWNLOAD_CHECKPOINT` (1). Secure Link `desktop` on port 6080.
Hardware: L40S / RTX PRO 6000 class GPU with RT cores, 128 GiB RAM, 300 GiB disk.

## Use on an existing VM

```bash
git clone https://github.com/vaishkarni/-isaaclab-arena-brev.git && cd isaaclab-arena-brev
VNC_PASSWORD=changeme sudo -E bash brev-setup.sh
```

## Files

| File | What |
|---|---|
| `launchable-setup.sh` | 8-line bootstrap to paste into the Launchable |
| `brev-setup.sh` | the real setup: desktop, noVNC, systemd unit, Arena clone + image build, GR00T checkout, G1 workflow staging |
| `STEPS-create-launchable.md` | organizer: click-by-click Launchable creation + dry run |
| `RUNBOOK-g1-static-apple.md` | organizer: G1 apple-to-plate dataset / finetune / eval runbook |
| `run_gr00t_server.sh`, `run_g1_apple_client.sh` | helpers written to the node for the eval lesson |
| `isaaclab_arena_workshop.ipynb` | participant notebook |
| `docs/`, `*.pdf` | organizer and participant guides |

## Quick GUI check on a built node

Inside the browser desktop, open a terminal:

```bash
cd ~/IsaacLab-Arena && ./docker/run_docker.sh
python -m pytest isaaclab_arena/tests/test_g1_static_pick_and_place.py -v      # headless, "2 passed"
python isaaclab_arena/evaluation/policy_runner.py --policy_type zero_action --viz kit --num_steps 3000 \
  pick_and_place_maple_table --embodiment droid_rel_joint_pos --hdr home_office_robolab   # window opens on the desktop
```
