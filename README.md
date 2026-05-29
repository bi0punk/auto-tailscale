# auto-tailscale

One-shot installer script for Tailscale on Linux. Handles installation, authentication (auth key or web), SSH enablement, and route acceptance.

## Stack

Bash

## Usage

```bash
# Install with web auth
bash install_tailscale_server.sh

# Install with auth key
bash install_tailscale_server.sh --auth-key tskey-xxxx

# With SSH and route acceptance
bash install_tailscale_server.sh --ssh --accept-routes

# Uninstall
bash install_tailscale_server.sh --uninstall
```

## Features

- Distro-agnostic (apt/dnf/pacman)
- Auth key or interactive login
- Optional Tailscale SSH
- Optional `--accept-routes`
- `--reset` flag
- Comprehensive logging

## License

MIT
