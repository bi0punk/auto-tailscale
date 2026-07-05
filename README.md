# auto-tailscale

One-shot installer script for Tailscale on Linux. Handles installation, authentication (auth key or web), SSH enablement, and route acceptance.

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/tu-usuario/auto-tailscale/actions/workflows/ci.yml/badge.svg)](https://github.com/tu-usuario/auto-tailscale/actions/workflows/ci.yml)

## Tabla de Contenidos

- [Características](#características)
- [Stack](#stack)
- [Arquitectura](#arquitectura)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Tests](#tests)
- [CI](#ci)
- [Limitaciones / Roadmap](#limitaciones--roadmap)
- [Licencia](#licencia)

## Características

- Soporte multi-distribución (apt, dnf, pacman, apk)
- Autenticación por auth key o web interactiva
- Habilitación opcional de Tailscale SSH
- Aceptación de rutas (`--accept-routes`)
- Flag `--reset` para re-configuración
- Logging completo del proceso
- Modo desinstalación (`--uninstall`)

## Stack

- Bash, Tailscale CLI

## Arquitectura

```
auto-tailscale/
├── install_tailscale_server.sh   # Script principal
├── tests/
├── .github/workflows/ci.yml
├── LICENSE
└── README.md
```

## Requisitos

- Linux (Debian, Ubuntu, Fedora, Arch, Alpine, etc.)
- Acceso root (via sudo)
- Conexión a Internet

## Instalación

```bash
git clone https://github.com/tu-usuario/auto-tailscale.git
cd auto-tailscale
```

## Uso

```bash
# Instalar con autenticación web
sudo bash install_tailscale_server.sh

# Instalar con auth key
sudo bash install_tailscale_server.sh --auth-key tskey-xxxx

# Con SSH y aceptación de rutas
sudo bash install_tailscale_server.sh --ssh --accept-routes

# Reconfigurar
sudo bash install_tailscale_server.sh --reset

# Desinstalar
sudo bash install_tailscale_server.sh --uninstall
```

## Tests

```bash
# ShellCheck (lint)
shellcheck install_tailscale_server.sh
```

## CI

GitHub Actions ejecuta ShellCheck en cada push y PR sobre Ubuntu latest.

## Limitaciones / Roadmap

- [ ] Soporte para macOS
- [ ] Integración con systemd para auto-arranque
- [ ] Modo headless sin prompts interactivos
- [ ] Tests de integración en contenedores

## Licencia

MIT
