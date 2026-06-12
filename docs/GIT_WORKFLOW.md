# Git Workflow

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Git Workflow  
**Previous:** [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md)  
**Next:** [DOCKERFILES.md](DOCKERFILES.md)

---

## Table of Contents

**Section 1 — Initial Repository Setup**

1. [Install Git and GitHub CLI](#1-install-git-and-github-cli)
2. [Configure GitHub SSH Access](#2-configure-github-ssh-access)
3. [Clone the Developer Repository](#3-clone-the-developer-repository)
4. [Create the DevOps Repository](#4-create-the-devops-repository)
5. [Initial Repository Checkpoint](#5-initial-repository-checkpoint)

**Section 2 — Commit and Push**

6. [Pre-Commit Checks](#6-pre-commit-checks)
7. [Copy Documentation Files Into the Repository](#7-copy-documentation-files-into-the-repository)
8. [Verify Full Repository Structure](#8-verify-full-repository-structure)
9. [Check Git Status](#9-check-git-status)
10. [Stage All Files](#10-stage-all-files)
11. [Commit](#11-commit)
12. [Push to GitHub](#12-push-to-github)
13. [Verify on GitHub](#13-verify-on-github)
14. [Troubleshooting](#14-troubleshooting)

---

# Section 1 — Initial Repository Setup

---

## 1. Install Git and GitHub CLI

```bash
sudo pacman -S git github-cli
```

Verify:

```bash
git --version
# Expected: git version 2.x.x

gh --version
# Expected: gh version 2.x.x
```

Configure your git identity:

```bash
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
```

Verify:

```bash
git config --list | grep user
# Expected: user.name and user.email are set
```

---

## 2. Configure GitHub SSH Access

Authenticate with GitHub using the CLI:

```bash
gh auth login
```

**Follow the interactive prompts:**

- **Where do you use GitHub?** Select `GitHub.com`
- **What is your preferred protocol?** Select `SSH`
- **Generate a new SSH key?** Select `Yes`
- **Passphrase:** Press Enter (leave blank)
- **Title for the SSH key:** Enter `devops ops-box-01`
- **How would you like to authenticate?** Select `Login with a web browser`
- Copy the one-time code displayed, open the URL shown, paste the code and authorise

**Expected output:**

```
Authentication complete.
Configured git protocol
Uploaded the SSH key to your GitHub account
Logged in as <github-username>
```

Test the connection:

```bash
ssh -T git@github.com
# Expected: Hi <github-username>! You have successfully authenticated...
```

**Verification:** GitHub SSH access confirmed

---

## 3. Clone the Developer Repository

```bash
cd ~/workspace
git clone git@github.com:<github-username>/humor-memory-game.git
```

Verify the clone:

```bash
ls -la humor-memory-game/
# Expected: backend/  frontend/  database/
```

Inspect key directories:

```bash
ls humor-memory-game/backend/
# Expected: server.js  package.json  package-lock.json  ...

ls humor-memory-game/frontend/
# Expected: src/  public/  package.json  ...

ls humor-memory-game/database/
# Expected: combined-init.sql
```

> **Do not run `npm install` or `npm start` in this repository.** The application runs inside Docker containers — not directly on the host.

---

## 4. Create the DevOps Repository

```bash
cd ~/workspace/humor-memory-game-devops
git init
git branch -M main
```

Create `.gitignore` immediately — before any other files are added:

```bash
cat > .gitignore << 'EOF'
# Environment secrets — NEVER commit this file
.env

# OS files
.DS_Store
Thumbs.db

# Editor directories
.idea/
.vscode/
EOF
```

Verify `.env` is ignored:

```bash
git check-ignore -v .env
# Expected: .gitignore:1:.env    .env
```

Create the remote repository on GitHub:

```bash
gh repo create humor-memory-game-devops --public
```

Initial commit:

```bash
git add .gitignore
git commit -m "Initial commit: add .gitignore and directory structure"
git push -u origin main
```

---

## 5. Initial Repository Checkpoint

```bash
# Git configured
git config --list | grep user
# Expected: user.name and user.email set

# GitHub SSH works
ssh -T git@github.com
# Expected: Hi <github-username>! You have successfully authenticated...

# Both repositories present
ls ~/workspace/
# Expected:
# humor-memory-game             Developer repository (cloned, never modified)
# humor-memory-game-devops      DevOps repository (Docker infrastructure)

# Developer repository structure correct
ls ~/workspace/humor-memory-game/
# Expected: backend/  frontend/  database/

# DevOps repository initialised
ls -la ~/workspace/humor-memory-game-devops/
# Expected: .git/  .gitignore  docker/  docs/

# .env is ignored
git -C ~/workspace/humor-memory-game-devops check-ignore -v .env
# Expected: .gitignore:1:.env    .env
```

All checks passing? Proceed to Dockerfiles.

---

**Next → [DOCKERFILES.md](DOCKERFILES.md)**

---

---

# Section 2 — Commit and Push

Run this section after all of the following are complete:

- All Dockerfiles and supporting config files are created
- `docker-compose.yml` and `.env.example` are in place
- Verification has passed — see [VERIFICATION.md](VERIFICATION.md) — `game_check.sh` 25/25 tests
- All documentation is in the `docs/` directory

---

## 6. Pre-Commit Checks

Navigate to the DevOps repository:

```bash
cd ~/workspace/humor-memory-game-devops
```

Confirm you are on the correct branch:

```bash
git status

git branch
```

Confirm `.env` is still ignored — run this before every commit:

```bash
git check-ignore -v .env
# Expected: .gitignore:1:.env    .env
```

If `.env` is not ignored — stop immediately and fix it:

```bash
echo ".env" >> .gitignore
git add .gitignore
git commit -m "Fix: add .env to .gitignore"
```

---

## 7. Copy Documentation Files Into the Repository

If documentation files were drafted on your local machine, transfer them using `scp` from your local terminal:

```bash
# Copy all docs at once
scp /path/to/local/docs/*.md devops@192.168.30.11:~/workspace/humor-memory-game-devops/docs/

# Copy README
scp /path/to/local/README.md devops@192.168.30.11:~/workspace/humor-memory-game-devops/
```

Confirm all documentation files are in place on the VM:

```bash
ls ~/workspace/humor-memory-game-devops/docs/
# Expected:
# DOCKER_OVERVIEW.md
# ENVIRONMENT_SETUP.md
# GIT_WORKFLOW.md
# DOCKERFILES.md
# DOCKER_CONFIG.md
# DOCKER_IMAGE_TESTS.md
# DOCKER_COMPOSE.md
# BUILD_AND_START.md
# VERIFICATION.md
```

---

## 8. Verify Full Repository Structure

```bash
find ~/workspace/humor-memory-game-devops -type f | grep -v ".git" | sort
```

Expected output:

```
humor-memory-game-devops/.env.example
humor-memory-game-devops/.gitignore
humor-memory-game-devops/README.md
humor-memory-game-devops/docker-compose.yml
humor-memory-game-devops/docker/backend/Dockerfile
humor-memory-game-devops/docker/frontend/Dockerfile
humor-memory-game-devops/docker/frontend/nginx.conf
humor-memory-game-devops/docker/frontend/start.sh
humor-memory-game-devops/docs/BUILD_AND_START.md
humor-memory-game-devops/docs/DOCKER_COMPOSE.md
humor-memory-game-devops/docs/DOCKER_CONFIG.md
humor-memory-game-devops/docs/DOCKER_IMAGE_TESTS.md
humor-memory-game-devops/docs/DOCKER_OVERVIEW.md
humor-memory-game-devops/docs/DOCKERFILES.md
humor-memory-game-devops/docs/ENVIRONMENT_SETUP.md
humor-memory-game-devops/docs/GIT_WORKFLOW.md
humor-memory-game-devops/docs/VERIFICATION.md
humor-memory-game-devops/game_check.sh
```

> `.env` must **not** appear in this list.

---

## 9. Check Git Status

```bash
git status
```

Expected:

```
On branch main
Untracked files:
  (use "git add <file>..." to include in what will be committed)
        README.md
        docker-compose.yml
        .env.example
        docker/
        docs/
        game_check.sh
```

---

## 10. Stage All Files

```bash
git add README.md
git add docker-compose.yml
git add .env.example
git add game_check.sh
git add docker/
git add docs/
```

Verify everything staged correctly:

```bash
git status
```

> If `.env` appears in the staged list — run `git reset HEAD .env` immediately and do not proceed.

---

## 11. Commit

```bash
git commit -m "Add Docker infrastructure, documentation, and test suite

- Add backend Dockerfile (node:22-alpine, multi-layer cached build)
- Add frontend Dockerfile (two-stage build: node:22 builder -> nginx:1.25 serve)
- Add nginx.conf (static serve + /api/ reverse proxy to backend)
- Add start.sh (environment variable injection before Nginx start)
- Add docker-compose.yml (4 services across 2 isolated networks)
- Add .env.example (safe environment variable template)
- Add README.md (project overview for recruiters and hiring managers)
- Add game_check.sh (automated 25-test end-to-end verification suite)
- Add docs/ with complete phase-by-phase deployment documentation
- Documents 9 issues encountered and resolved during containerisation"
```

---

## 12. Push to GitHub

```bash
git push origin main
```

Expected output:

```
Enumerating objects: XX, done.
Counting objects: 100% (XX/XX), done.
Compressing objects: 100% (XX/XX), done.
Writing objects: 100% (XX/XX), X.XX KiB | X.XX MiB/s, done.
To git@github.com:<github-username>/humor-memory-game-devops.git
   xxxxxxx..xxxxxxx  main -> main
```

---

## 13. Verify on GitHub

Open the repository in a browser:

```
https://github.com/<github-username>/humor-memory-game-devops
```

Confirm:

- [ ] `README.md` renders automatically on the landing page
- [ ] `docker/` directory visible with `backend/` and `frontend/` subdirectories
- [ ] `docs/` directory visible with all nine documents
- [ ] `game_check.sh` visible in root
- [ ] `docker-compose.yml` visible in root
- [ ] `.env.example` visible in root
- [ ] `.env` is **NOT** visible — git-ignored and absent from the repository

---

## 14. Troubleshooting

### Push rejected — not up to date

```bash
git pull origin main --rebase
git push origin main
```

### Accidentally staged .env

```bash
# Unstage immediately
git reset HEAD .env

# Confirm it is no longer staged
git status
# .env must not appear in the staged files list

# Verify it is in .gitignore
cat .gitignore | grep ".env"
```

### Wrong files committed

```bash
# Undo the last commit — keeps files, unstages them
git reset HEAD~1

# Review what is now unstaged
git status

# Re-add only the correct files and recommit
git add README.md docker/ docs/ ...
git commit -m "correct commit message"
```

### SSH authentication failed on push

```bash
# Test the SSH connection
ssh -T git@github.com

# If it fails, re-add the key to the SSH agent
ssh-add ~/.ssh/id_ed25519

# Retry the push
git push origin main
```
