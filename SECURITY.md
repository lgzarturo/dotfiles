# Security Policy

## Supported Versions

Only the latest stable release receives security fixes.

| Version | Supported | Notes                                                   |
| ------- | --------- | ------------------------------------------------------- |
| v1.1.0  | ✅ Yes    | Fixes all known installation issues on Windows & Ubuntu |
| < v1.0  | ❌ No     | Deprecated — upgrade to v1.1.0                          |

## Reporting a Vulnerability

If you discover a security issue, open a **private** GitHub Security Advisory
(repo → Security → Advisories → New draft advisory) instead of a public issue.
We aim to respond within 5 business days.

---

## Security Review — v1.1.0

### Scope

This audit covers `setup.sh`, `setup.ps1`, and all libraries under `lib/`. The
scripts install developer tooling and apply system optimizations; they do
**not** handle credentials, tokens, or network services.

---

### Findings Summary

| Category                       | Status  | Detail                                                                           |
| ------------------------------ | ------- | -------------------------------------------------------------------------------- |
| Remote code execution          | ✅ Safe | No `curl … \| sh` patterns — all downloads use `mktemp` first                    |
| Privilege escalation (Linux)   | ✅ Safe | All `sudo` calls go through `sudo_run()` wrapper; skips sudo if already root     |
| Privilege escalation (Windows) | ✅ Safe | Admin operations gated behind `Test-IsAdmin` checks                              |
| Arbitrary code injection       | ✅ Safe | No `eval`, no dynamic variable expansion in sensitive paths                      |
| Credential exposure            | ✅ Safe | No secrets, tokens, or API keys in code or config templates                      |
| Supply-chain risk              | ⚠️ Low  | Third-party installers fetched over HTTPS from official sources only (see below) |
| Idempotence / data safety      | ✅ Safe | Pre-existing files backed up before any symlink or overwrite                     |

---

### Secure Download Pattern

Every external installer is downloaded to a temporary file **before** being
executed. The pipe-to-shell anti-pattern (`curl … | sh`) is **not used**
anywhere in the codebase.

```sh
# setup.sh — pattern used for ALL external installers
tmp="$(mktemp)"
if curl -fsSL https://example.com/install.sh -o "$tmp"; then
  sh "$tmp" --yes
  rm -f "$tmp"
else
  rm -f "$tmp"
  log_warn "download failed — skipping"
fi
```

The same pattern applies to `lib/agent-tools.sh` (Ollama) and all runtime
installers (Starship, Zap, mise, uv).

---

### Privilege Escalation — Linux / macOS

`sudo` is never called directly in the scripts. All privileged operations go
through the `sudo_run()` helper defined in `lib/logger.sh`:

```sh
sudo_run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"          # already root — no sudo needed
  else
    sudo "$@"
  fi
}
```

`sudo` is only used for system-level writes: kernel parameters (`sysctl`), udev
rules, fstab tweaks, and ZRAM configuration. User-space tooling is installed
without elevated privileges.

---

### Privilege Escalation — Windows

Operations that require administrator rights (e.g., `netsh`, `fsutil`,
performance registry keys) are wrapped in explicit admin checks:

```powershell
if (Test-IsAdmin) {
    # privileged operation
}
```

The script **never** attempts to self-elevate. If admin rights are absent, the
privileged step is skipped and logged as a warning; installation continues
safely.

---

### External Sources

All third-party content is fetched exclusively over HTTPS from the official
distribution channel of each project:

| Tool        | Source URL                                           |
| ----------- | ---------------------------------------------------- |
| Starship    | `https://starship.rs/install.sh`                     |
| Zap (zsh)   | `https://raw.githubusercontent.com/zap-zsh/zap/…`    |
| Ollama      | `https://ollama.com/install.sh`                      |
| mise        | `https://mise.run`                                   |
| uv          | `https://astral.sh/uv/install.sh`                    |
| Nerd Fonts  | `https://github.com/ryanoasis/nerd-fonts/releases/…` |
| winget pkgs | `https://winget.run` (Microsoft-managed source)      |

No custom or third-party package mirrors are used.

---

### Idempotence and Backup Policy

The scripts are designed to be run multiple times without destructive side
effects. Before overwriting any existing configuration file, the original is
backed up using the following conventions:

#### Linux / macOS (`setup.sh`)

User-space config files are backed up **in-place** alongside the original:

```
~/.zshrc  →  ~/.zshrc.dotfiles-backup
```

System files modified by tuning steps are backed up with a datestamp:

```
/etc/fstab  →  /etc/fstab.dotfiles-backup-YYYYMMDD
```

The full backup root can be overridden with:

```sh
DOTFILES_BACKUP_DIR=~/my-backup ./setup.sh
```

Default location: `~/.dotfiles-backup/YYYYMMDD-HHmmss/`

#### Windows (`setup.ps1`)

Config files (e.g., PowerShell profile) are backed up in-place:

```
$PROFILE  →  $PROFILE.dotfiles-backup
```

Dotfiles symlink targets are backed up beside their destination:

```
~\AppData\Roaming\…\file  →  …\file.dotfiles-backup
```

Default backup root: `%USERPROFILE%\dotfiles-backup\YYYYMMDD-HHmmss\` Override
with the `-BackupDir` parameter.

---

### Dry-Run Mode

Both entry points support a non-destructive preview mode that makes **no
changes** to the system:

```sh
./setup.sh --dry-run        # Linux / macOS / WSL
.\setup.ps1 -DryRun         # Windows
```

In dry-run mode all `sudo_run` calls, symlink operations, package installs, and
system writes are replaced with informational log messages.

---

### No `eval`, No Dynamic Execution

A full-codebase search confirms **zero** uses of `eval` or equivalent dynamic
code execution constructs (`Invoke-Expression`, `` ` ``-quoting for
side-effects) in the production scripts. All command arguments are passed as
discrete tokens, preventing shell injection via crafted input.

---

## Conclusion

The v1.1.0 release of this dotfiles project is considered **safe for public
distribution**. The codebase follows established shell security practices: safe
downloads via temporary files, explicit privilege gating, no dynamic code
evaluation, no embedded secrets, and non-destructive idempotent behavior with
automatic backups.
