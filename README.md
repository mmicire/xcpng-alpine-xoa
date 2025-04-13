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
```

---

## 📦 After Installing Alpine

Log into the VM (via `xl console` or SSH) and run:

```bash
wget -O- https://raw.githubusercontent.com/mmicire/xcpng-alpine-xoa/main/postinstall.sh | sh
```

This installs Docker, pulls Xen Orchestra, and runs Watchtower to keep it updated.

---

## 🛠 Files

| File                     | Description                                              |
|--------------------------|----------------------------------------------------------|
| `create-latest-alpine-vm.sh` | Main script to create the Alpine VM on XCP-ng            |
| `postinstall.sh`              | Run inside Alpine after OS install to deploy Xen Orchestra |
| `cleanup-alpine-xoa.sh`       | Deletes VMs, disks, and optionally ISOs for a clean environment |

---

## 🧹 VM Cleanup Script

### `cleanup-alpine-xoa.sh`

This script safely and flexibly removes VMs matching a given name prefix (default: `Alpine-Docker-XOA-`) and optionally deletes orphaned ISO files.

### 🔧 Features

- ✅ Deletes VMs created by `create-latest-alpine-vm.sh`
- ✅ Cleans up associated VIFs, VBDs, and VDIs
- ✅ Supports dry-run mode (shows what would be deleted)
- ✅ Logs all actions to a file
- ✅ Customizable VM name prefix
- ✅ Can remove unused ISO images from ISO SRs

---

### 🧪 Example Usage

#### 🔍 Show what would be deleted (no action taken):

```bash
./cleanup-alpine-xoa.sh --dry-run
```

#### 🧹 Perform full cleanup and log to a file:

```bash
./cleanup-alpine-xoa.sh --log cleanup.log
```

#### 🧹 Cleanup VMs with a custom prefix (e.g., Alpine-XOA-Test):

```bash
./cleanup-alpine-xoa.sh --prefix Alpine-XOA-Test
```

#### 🧼 Remove unused ISOs from ISO SRs as well:

```bash
./cleanup-alpine-xoa.sh --clean-isos
```

#### 📦 Combine all options:

```bash
./cleanup-alpine-xoa.sh --prefix Alpine-XOA-Test --clean-isos --log cleanup.log
```

---

### 🆘 Script Help

You can always view the built-in help menu with:

```bash
./cleanup-alpine-xoa.sh --help
```

---

MIT License. Maintained by [mmicire](https://github.com/mmicire).

