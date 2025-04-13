# XCP-ng Alpine VM Bootstrap

This repository automates the creation of a minimal Alpine Linux VM on an XCP-ng host, including:

- Downloading and verifying the latest Alpine ISO
- Setting up an ISO Storage Repository (SR) if none exists
- Creating and configuring a VM (disk, network, ISO attachment)
- Booting the VM and displaying a direct console command

An optional `postinstall.sh` script is provided to run **inside** the Alpine VM after installation, which installs:

- Docker
- [ronivay/xen-orchestra](https://hub.docker.com/r/ronivay/xen-orchestra)
- Watchtower for automatic container updates

---

## 🚀 One-Liner Install (on XCP-ng host)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mmicire/xcpng-alpine-xoa/main/create-latest-alpine-vm.sh)
