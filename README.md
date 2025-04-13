# 🚀 Quickstart: XCP-ng Alpine VM + Xen Orchestra

Welcome to the **Alpine Docker XOA** bootstrap for XCP-ng.

This guide helps you:

✅ Create a minimal Alpine Linux VM  
✅ Install [ronivay/xen-orchestra](https://hub.docker.com/r/ronivay/xen-orchestra) via Docker  
✅ Automate cleanup and reuse

---

## ✨ Create the VM

Run this on your **XCP-ng host**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mmicire/xcpng-alpine-xoa/main/create-latest-alpine-vm.sh)
```

This will:
- Download the latest Alpine ISO
- Create the VM and ISO Storage Repository (if needed)
- Boot Alpine with the VM's network and disk preconfigured

---

## ⚙️ Alpine Install

Inside the VM console (`xl console <domid>`), run:

```bash
setup-alpine
```

Go through the installation ensuring that you install to xvda as the sys device.  

When the installation completes, run: 

```bash
sync ; halt
```
After a few seconds you should be back at a prompt for Dom0.

---

## 📀 Remove ISO and Boot from Disk

Once Alpine is installed, remove the ISO and switch to disk boot:

```bash
xe vm-list is-control-domain=false params=uuid,name-label
xe vm-cd-eject uuid=<VM-UUID> force=true
xe vm-param-set uuid=<VM-UUID> HVM-boot-params:order=c
xe vm-start uuid=<VM-UUID>
```

Your new console is likely n+1 from the last one you used. So, type:

```bash
xl console <domid+1>
```
---

## 🧰 Install Xen Orchestra in Alpine

Inside your Alpine VM:

```bash
wget -O- https://raw.githubusercontent.com/mmicire/xcpng-alpine-xoa/main/postinstall.sh | sh
```

This installs:
- Docker
- ronivay/xen-orchestra
- Watchtower for automatic updates
- xe-guest-utilities and added to runlevel default
- automatic daily updates and email on updates or error

You should then see some messages:

⚠️  Manual configuration required <- do these things if you want email alerts for updates

✅ Postinstall complete. Xen Orchestra is running at: http://xxx.xxx.xxx.xxx

Navigate to that URL and login in as admin@admin.net with the password admin.  Select "add a server" and add your host.  

Enjoy! 

---

## 🧹 OPTIONAL - Clean Up VMs and ISOs

If you messed up and need to delete test VMs and unused ISOs:

```bash
./cleanup-alpine-xoa.sh --clean-isos --log cleanup.log
```

Or simulate the cleanup first:

```bash
./cleanup-alpine-xoa.sh --dry-run
```

More options:

```bash
./cleanup-alpine-xoa.sh --help
```

---

## 📂 Files in This Repo

| File                        | Purpose                                                |
|-----------------------------|--------------------------------------------------------|
| `create-latest-alpine-vm.sh` | Create Alpine VM in XCP-ng                            |
| `answers.conf`               | Alpine preseed configuration                          |
| `postinstall.sh`             | Installs Docker + Xen Orchestra                       |
| `cleanup-alpine-xoa.sh`      | VM/ISO cleanup utility                                |

---

## 🗪 License

MIT License.  
Maintained by [@mmicire](https://github.com/mmicire)
