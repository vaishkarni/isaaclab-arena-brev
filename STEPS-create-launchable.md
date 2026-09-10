# Create the IsaacLab-Arena workshop Launchable on Brev (do-it-yourself steps)

Goal: participants open a browser, see a full Linux desktop (XFCE over noVNC), and when they
run the Arena demo the Isaac Sim / Isaac Lab window appears on that desktop.

Everything the VM needs is done by `brev-setup.sh` (this folder). You only build the Launchable
around it in the Brev console. Wizard order below is the current console (same one the
isaac-launchable README describes).

## 0. Before you start (2 min)
- Sign in at https://brev.nvidia.com, pick the org that has credits (top-left org switcher; the
  CLI is currently on "Jetson BYOC Physical AI Lab", which has no instances).
- Open `brev-setup.sh` in an editor, select all, copy (you paste it in step 3).
- Decide the shared VNC password for the workshop (participants type it into noVNC).

## 1. Launchables -> Create Launchable
Console left nav: Launchables -> green "Create Launchable" button (top right).

## 2. Files / code
Choose "I don't have any code files" (or the Notebook option and upload
`isaaclab_arena_workshop.ipynb` if you want it on the box; not required, the desktop has a
terminal).

## 3. Runtime / environment
- Choose **VM Mode** ("Basic VM with Python installed"). Do NOT choose Container mode; the
  script needs the host NVIDIA driver, Docker and Xorg.
- Setup script -> **Paste Script** tab -> paste the whole `brev-setup.sh`.
- Click Next.

## 4. Jupyter
"No, I don't want Jupyter" (or Yes if you want the notebook UI on 8888; it makes its own link).

## 5. Exposed ports
- **Secure Link** tab: name `desktop`, port `6080`. This gives a Brev-login-protected HTTPS URL
  for the browser desktop, so NOVNC_TLS stays 0.
- **TCP/UDP ports** tab: nothing. (The isaac-launchable template opens 1024/47998/49100 for
  WebRTC streaming; we use VNC instead, so skip them.)
- Click Next.

## 6. Launch parameters (environment variables for the setup script)
Add these; participants see them on the Deploy page.

| Name | Type | Required | Default | Note |
|---|---|---|---|---|
| VNC_PASSWORD | text (mark secret) | yes | none | one shared workshop password |
| PREBUILD_IMAGE | choice 1 / 0 | no | 1 | builds `isaaclab_arena:latest` during setup (30-60 min) |
| INSTALL_GROOT | choice 0 / 1 | no | 0 | GR00T-flavored `-g` image, not needed for the sim-setup lesson |
| NOVNC_TLS | choice 0 / 1 | no | 0 | keep 0 behind the Secure Link |
| ARENA_BRANCH | text | no | release/0.2.1 | pin |
| G1_WORKFLOW | choice 1 / 0 | no | 1 | stage the G1 apple-to-plate helpers |
| HF_TOKEN | text (secret) | no | empty | only needed for the GR00T finetune/eval lessons (gated Cosmos-Reason2-2B) |
| DOWNLOAD_DATASET | choice 1 / 0 | no | 1 | 10 GB HF dataset for the LeRobot export lesson |
| DOWNLOAD_CHECKPOINT | choice 1 / 0 | no | 1 | 13 GB tuned checkpoint for the eval lesson |

If you only teach the sim-setup lesson set DOWNLOAD_DATASET=0 and DOWNLOAD_CHECKPOINT=0 to
save ~25 GB and 15+ min.

## 7. Compute
- GPU: **NVIDIA L40S (48 GB)** on AWS (what the official Isaac Launchable uses; RT cores,
  Isaac Sim-compatible driver). RTX PRO 6000 / RTX 6000 Ada also fine. Avoid Crusoe (Isaac
  Sim streaming is known-incompatible there) and any card without RT cores (A100/H100 will
  not render the Kit GUI).
- 1 GPU, 16+ vCPU, 128 GiB RAM.
- Storage: **300 GiB** (Arena image 27 GB + Isaac Sim base + dataset + checkpoint + shader cache).

## 8. Name and create
- Name: `isaaclab-arena-workshop` (cannot be renamed later).
- Description: "IsaacLab-Arena 0.2.1 + Isaac Sim 6.0 with browser desktop, for the GR00T
  simulation workflow workshop".
- View access: "Anyone with the link" for an external workshop.
- Click **Create Launchable**, copy the share URL.

## 9. Dry run (do this the day before; 60-90 min to Built)
1. Open the share URL in a private window -> Deploy Launchable -> enter VNC_PASSWORD -> Deploy.
2. Wait for Running + Built + setup script finished. Progress: open the instance terminal and
   `tail -f /var/log/arena-workshop-setup.log` (last line is "=== DONE").
3. Instance page -> "Using Secure Links" -> click the arrow next to `desktop`. Log in with your
   Brev account. Add `?autoconnect=true&resize=scale` to the URL if it does not auto-connect.
   Enter the VNC password. You should see an XFCE desktop.
4. Show the Isaac Lab GUI (this is what participants will do):
   - In the desktop, open a terminal (Applications -> Terminal).
   - `cd ~/IsaacLab-Arena && ./docker/run_docker.sh` (drops into the container; DISPLAY=:0 is
     forwarded because the desktop terminal already has it).
   - Headless check first (this is the doc's test, it shows NO window on purpose):
     `python -m pytest isaaclab_arena/tests/test_g1_static_pick_and_place.py -v`  -> "2 passed"
     (re-run once if the apple falls through the shelf).
   - GUI, verified on the test box (DROID on the maple table):
     `python isaaclab_arena/evaluation/policy_runner.py --policy_type zero_action --viz kit --num_steps 3000 pick_and_place_maple_table --embodiment droid_rel_joint_pos --hdr home_office_robolab`
   - GUI, the workshop's own G1 apple-to-plate scene (same env the pytest uses; not yet verified
     with zero_action, try it during the dry run):
     `python isaaclab_arena/evaluation/policy_runner.py --policy_type zero_action --viz kit --num_steps 600 --enable_cameras galileo_g1_static_pick_and_place --object apple_01_objaverse_robolab --destination clay_plates_hot3d_robolab --embodiment g1_wbc_agile_joint`
   - The Isaac Sim window opens on the desktop after 3-5 min on first launch (shader compile +
     asset download); later launches take about a minute. Ctrl-C stops it.
   Rules that bite: runner options go BEFORE the env name; `--viz kit` is required (default is
   headless); `--num_steps` or `--num_episodes` is mandatory.
5. If everything works, Stop the instance (keep it, restart on workshop day) or delete it.

## 10. On workshop day
Option A: each participant deploys the share link into an org with credits (60-90 min wait).
Option B (recommended): you deploy N instances the day before, stop them, start them 15 min before
the session, and give each participant the `desktop` Secure Link + VNC password. Secure Links
require a Brev login, so invite participants to the org (`brev invite`) or use NOVNC_TLS=1 and
share the raw https://IP:6080 URL instead.

## Troubleshooting
- Secure Link blank / refused: `sudo systemctl restart gpu-desktop`; check /tmp/xorg.log for (EE).
- Xorg fails on the Brev image: driver X module missing; the script installs
  `xserver-xorg-video-nvidia-<major>` and falls back to the runfile-provided module. Check the
  log; if the driver was installed via runfile the module is already present.
- No window from policy_runner: `echo $DISPLAY` inside the container must print `:0`.
- Build too slow on the day: set PREBUILD_IMAGE=1 (default) and deploy the day before.
