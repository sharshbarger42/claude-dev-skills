# Setup

Bootstrap helpers for getting Claude Code running on a new device against the
super-werewolves homelab.

## What's here

| Path | Purpose |
|------|---------|
| `new-device-prompt.md` | Copy-paste prompt for `claude` on a fresh device that already has LAN access. Sets up Gitea SSH, clones `development-skills`, hands off to `/setup-env`. |
| `wireguard-prompt.md` | Copy-paste prompt for `claude` on a fresh device that does **not** have LAN access. Walks the human through WireGuard client setup against OPNsense, then exits — they re-paste `new-device-prompt.md` afterwards. |
| `wsl-sandbox/setup-linux.sh` | Per-OS one-shot installer for the WSL Ubuntu-Claude sandbox. Installs core packages, Node, Claude CLI, Oh My Zsh, dotfiles. Defers all dev-skills config to `/setup-env`. |
| `wsl-sandbox/setup-windows.ps1` | Provisioning side of the WSL sandbox — runs from PowerShell on the Windows host. |
| `wsl-sandbox/teardown-windows.ps1` | Removes the WSL sandbox + cleanup. |
| `dotfiles-defaults/` | Fallback `.zshrc` / `.tmux.conf` if the user has no dotfiles repo. |
| `env-config.yaml` | Defaults for `setup-linux.sh` + `/setup-env` (Gitea URL, org, etc.). |

## Decision tree for a new device

```
            ┌─ LAN reachable? ──────────────────────────────────────────────┐
            │  (curl http://git.home.superwerewolves.ninja → 200/302)       │
            ▼                                                               │
        ┌───┴───┐                                                       ┌───┴───┐
        │  Yes  │                                                       │  No   │
        └───┬───┘                                                       └───┬───┘
            │                                                               │
            │                                                               ▼
            │                                                ┌── WireGuard already configured? ──┐
            │                                                │                                   │
            │                                          ┌─────┴──────┐                       ┌────┴────┐
            │                                          │ Yes, down  │                       │   No    │
            │                                          └─────┬──────┘                       └────┬────┘
            │                                                │                                   │
            │                                          bring tunnel up                  use wireguard-prompt.md
            │                                          → loop back to top                       │
            ▼                                                                                   │
   use new-device-prompt.md                                                                     │
                                                                                                ▼
                                                                                        manual WG setup,
                                                                                        then loop back to top
```

`new-device-prompt.md` performs the LAN check itself in Phase 0 and points the human at
`wireguard-prompt.md` if it can't reach the homelab. So in practice the flow from the
human's side is:

1. Run `claude` on the new device.
2. Paste `new-device-prompt.md`.
3. If Claude says "no LAN — run the WG prompt first", paste `wireguard-prompt.md` instead, finish that, then redo step 2.

## Conventions for adding new bootstrap pieces

- **One prompt per phase**, not one big monolith. Composable beats clever.
- **Pure copy-paste content** in prompt files — no human-facing framing inside the prompt
  body. Framing goes in this README, not the prompt file itself.
- **Default everything that can be defaulted** (hostname for peer name, well-known DNS
  endpoints, etc.) and only ask the human to override. Never re-ask for values you can
  read from the system.
- **Pull dynamic facts from APIs / repo files** rather than asserting things that can
  change (current peer assignments, OPNsense server pubkey, gateway availability, etc.).
- **Per-OS scripts go under `setup/platform-helpers/`** once they exist (see the
  standardize-scripts issue in `homelab-setup`). Until then, the prompts handle Linux/WSL
  inline and refer to GUI clients for everything else.
- **Never echo or copy private keys** — only ever show public counterparts.
