# Environment Setup

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Environment Setup  
**Previous:** [DOCKER_OVERVIEW.md](DOCKER_OVERVIEW.md)  
**Next:** [GIT_WORKFLOW.md](GIT_WORKFLOW.md)

---

## Table of Contents

1. [SSH Into the DevOps VM](#1-ssh-into-the-devops-vm)
2. [Update the System](#2-update-the-system)
3. [Install Docker Engine and Docker Compose](#3-install-docker-engine-and-docker-compose)
4. [Configure Docker to Run Without sudo](#4-configure-docker-to-run-without-sudo)
5. [Set Up the Workspace and Directory Structure](#5-set-up-the-workspace-and-directory-structure)
6. [Environment Setup Checkpoint](#6-environment-setup-checkpoint)

---

## 1. SSH Into the DevOps VM

From your local machine, connect to the DevOps VM:

```bash
ssh devops@192.168.30.11
```

Confirm you are on the correct machine:

```bash
uname -m
# Expected: x86_64

hostnamectl
# Expected: shows ops-box-01 and Arch Linux as the OS
```

---

## 2. Update the System

Always update the system before installing new packages to avoid dependency conflicts:

```bash
sudo pacman -Syu
```

When prompted `Proceed with installation? [Y/n]` — press `Y` and Enter.

**Expected output (last lines):**

```
:: Running post-transaction hooks...
(1/1) Arming ConditionNeedsUpdate...
```

Reboot if any kernel updates were applied:

```bash
sudo reboot now
```

Reconnect after reboot:

```bash
ssh devops@192.168.30.11
```

---

## 3. Install Docker Engine and Docker Compose

On Arch Linux, Docker Engine and Docker Compose are separate packages and must both be installed explicitly:

```bash
sudo pacman -S docker docker-compose
```

Enable and start the Docker service:

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

Verify Docker is running:

```bash
sudo systemctl status docker
# Expected: Active: active (running)
# Press q to exit

sudo docker --version
# Expected: Docker version 26.x.x or later

docker compose version
# Expected: Docker Compose version v2.x.x or later
```

---

## 4. Configure Docker to Run Without sudo

By default, Docker requires `sudo` for every command. Adding your user to the `docker` group removes this requirement:

```bash
sudo usermod -aG docker $USER
```

Apply the group change without logging out:

```bash
newgrp docker
```

> **Best practice:** Log out of the SSH session and log back in even after running `newgrp docker`. The group change fully applies only on a fresh login.

```bash
exit
ssh devops@192.168.30.11
```

Verify your groups include `docker`:

```bash
groups
# Expected output includes: docker
```

Verify Docker works without sudo:

```bash
docker ps
# Expected: empty table — no containers running yet
# CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

> If `docker ps` still requires sudo after logging back in, log out and back in again. The group change has not fully applied.

---

## 5. Set Up the Workspace and Directory Structure

Create a consistent workspace directory. Both repositories will live here:

```bash
mkdir -p ~/workspace
cd ~/workspace
```

Verify:

```bash
pwd
# Expected: /home/devops/workspace
```

Create the DevOps repository directory structure:

```bash
mkdir -p humor-memory-game-devops/docker/backend
mkdir -p humor-memory-game-devops/docker/frontend
mkdir -p humor-memory-game-devops/docs
```

Verify the structure:

```bash
find ~/workspace/humor-memory-game-devops -type d
# Expected:
# /home/devops/workspace/humor-memory-game-devops
# /home/devops/workspace/humor-memory-game-devops/docker
# /home/devops/workspace/humor-memory-game-devops/docker/backend
# /home/devops/workspace/humor-memory-game-devops/docker/frontend
# /home/devops/workspace/humor-memory-game-devops/docs
```

> The developer repository (`humor-memory-game`) will be cloned into `~/workspace` during the Git workflow step. All Docker infrastructure files will be created inside `humor-memory-game-devops/`.

---

## 6. Environment Setup Checkpoint

Run through this checklist before proceeding to the Git workflow:

```bash
# Docker engine running
systemctl status docker | grep "Active:"
# Expected: Active: active (running)

# Docker works without sudo
docker ps
# Expected: empty table, no error

# Docker Compose available
docker compose version
# Expected: Docker Compose version v2.x.x or later

# Workspace exists
ls ~/workspace/
# Expected: humor-memory-game-devops/

# DevOps directory structure correct
find ~/workspace/humor-memory-game-devops -type d
# Expected: docker/  docker/backend/  docker/frontend/  docs/
```

All checks passing? Proceed to the Git workflow.

---

**Next → [GIT_WORKFLOW.md](GIT_WORKFLOW.md)**
