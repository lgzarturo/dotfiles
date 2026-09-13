# Security Policy

## Supported Versions

Only the latest stable release receives security fixes.

| Version | Supported |
| ------- | --------- |
| latest  | ✅ Yes    |
| older   | ❌ No     |

## Reporting a Vulnerability

If you discover a security issue, open a **private** GitHub Security Advisory
(repo → Security → Advisories → New draft advisory) instead of a public issue.

## Current Security Posture

This repository is intended to be safe to publish publicly:

- No embedded API keys, tokens, or private keys are intentionally stored in the tracked files.
- Setup flows no longer download and execute remote installer scripts automatically.
- Unsafe agent aliases are **disabled by default** and require explicit opt-in.
- Shared Git config uses placeholders instead of personal identity data.

## What Is Enforced

### 1. No automatic remote installer execution

The setup scripts prefer trusted package managers (`apt`, `dnf`, `pacman`,
`brew`, `winget`). If a tool is not available from the configured package
manager, the scripts now stop at a warning and require a manual installation
from the project's official documentation.

This applies to the previously risky install paths for:

- Starship
- Zap
- mise
- uv
- Ollama
- lazygit release tarballs

### 2. Unsafe agent aliases require opt-in

Permission-bypassing aliases such as `--allow-dangerously-skip-permissions`,
`--dangerously-skip-permissions`, `--auto`, `--yolo`, or
`--dangerously-bypass-approvals-and-sandbox` are not written by default.

They are only configured when explicitly requested:

- Linux / macOS / WSL: `DOTFILES_ENABLE_UNSAFE_AGENT_ALIASES=true` or `./setup.sh --enable-unsafe-agent-aliases`
- Windows: `.\setup.ps1 -EnableUnsafeAgentAliases`

### 3. Public templates avoid personal paths and identity data

- Shared templates use placeholders for Git identity.
- Personal absolute paths such as `/home/<user>/.dotfiles/...` are not kept in tracked scripts.
- System paths like `/etc/...` and `/usr/...` may still appear where they are required for system provisioning.

## Residual Risks

This repository still performs privileged system configuration and package
installation. That means some trust remains in:

- the operating system package manager,
- configured package repositories,
- binaries already present on the local `PATH`.

The shell profiles also execute initialization output from locally installed
tools such as `starship` or `mise`. That is expected behavior, but it means the
security of those commands depends on the integrity of the locally installed
binary.

## Repeatable Security Checks

Run the repository audit before publishing changes:

```bash
./scripts/maintenance/repo-security-check.sh
```

The audit checks for:

- hardcoded secrets and credential patterns,
- personal absolute paths,
- remote-download-and-execute patterns in tracked scripts.

## Manual Review Guidance

Before merging or publishing:

1. Run `./scripts/maintenance/repo-security-check.sh`
2. Review changes to `setup.sh`, `setup.ps1`, `lib/`, and `scripts/setup/`
3. Confirm no new remote installer execution was introduced
4. Confirm no personal identity data or secrets were added
