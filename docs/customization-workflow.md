# Customization Workflow — Integration with adempiere-ui-gateway

## Overview

Every commit pushed to your fork of `adempiere-customizations` and released as
a new version triggers a chain of dependent releases. Each container that
depends on it rebuilds its Docker image, and the image tags in
`adempiere-ui-gateway` are updated automatically. The scripts described below
automate this entire chain.

---

## Dependency chain

```
adempiere-customizations
        ├── adempiere-zk                  ─┐
        ├── adempiere-grpc-server          ├─► adempiere-ui-gateway
        └── adempiere-processors-service  ─┘
```

---

## Step-by-step propagation

1. **Push commits** to your `adempiere-customizations` fork and ensure the
   GitHub Actions CI workflow passes.
2. **Create a release tag** — this triggers the publish workflow, which uploads
   the Maven artifact to GitHub Packages.
3. **Each dependent container** (`adempiere-grpc-server`, `adempiere-zk`,
   `adempiere-processors-service`) updates its `adempiere-customizations`
   dependency version, pushes the change, and waits for its own CI to pass.
4. **A GitHub release** is created for each container, which triggers its
   publish workflow and produces a new Docker image on Docker Hub.
5. **`adempiere-ui-gateway`** `docker-compose/env_template.env` is updated
   with the new image tags and pushed.

---

## Intended execution context

> **Important:** These scripts are designed to run against **your own fork** of
> the relevant repositories — not against the upstream `adempiere` GitHub
> organization. `adempiere-customizations` is a template repository for exactly
> this purpose: fork it into your own organization, where you hold full
> administrative control, and run the entire CI/CD chain there.

---

## Required permissions

The scripts require the following access rights. Missing any of them will cause
the script to fail silently at the privileged step — no release, package, or
image will be created or updated:

| Permission | Required for |
|---|---|
| GitHub write access to each repository in the chain | Pushing commits and creating GitHub Releases via `gh release create` |
| GitHub Packages `write:packages` scope on the PAT | Publish workflows uploading Maven artifacts |
| Docker Hub push access to your image namespaces | CI/CD publish workflows pushing Docker images |
| GitHub Actions trigger rights on each repository | `gh release create` triggering publish workflows |

---

## Automation scripts

Two template scripts are provided in `scripts/templates/`. They must be copied
to `scripts/local/` (which is git-ignored) and all placeholder values must be
filled in before use.

| Template | Purpose |
|---|---|
| `scripts/templates/stack-update.template.sh` | Full chain: from a new `adempiere-customizations` release, propagates through `adempiere-grpc-server` up to `adempiere-ui-gateway` |
| `scripts/templates/release-adempiere-grpc-server.template.sh` | Single step: creates a release for `adempiere-grpc-server` and updates its image tag in `adempiere-ui-gateway` |

### Missing scripts — community contribution needed

Template scripts for the `adempiere-zk` and `adempiere-processors-service`
release steps do not exist yet. The `stack-update.sh` template covers only the
`adempiere-grpc-server` step. Contributions of the missing scripts are welcome.

### Setup

```bash
cp scripts/templates/stack-update.template.sh          scripts/local/stack-update.sh
cp scripts/templates/release-adempiere-grpc-server.template.sh  scripts/local/release-adempiere-grpc-server.sh
```

Open each copied file and fill in all values in the `# ── CONFIGURE BEFORE USE ──`
block at the top.

### Usage

```bash
# Full chain — real run
./scripts/local/stack-update.sh "Fix invoice posting logic"

# Full chain — preview only, no changes made
./scripts/local/stack-update.sh --dry-run "Fix invoice posting logic"

# Full chain — dry-run with default placeholder notes
./scripts/local/stack-update.sh -n

# Single step — grpc-server only
./scripts/local/release-adempiere-grpc-server.sh "Fix invoice posting logic"
```

### Options

- `--dry-run` / `-n` — preview mode: prints every action that would be taken
  but makes no changes (no commits, no pushes, no GitHub releases). Read-only
  GitHub API calls still run so version transitions are shown accurately.
- `POLL_INTERVAL` — shell variable at the top of each script (default: 30 s).
  Controls how often CI/CD workflow status is checked.

---

[Back to README](../README.md)
