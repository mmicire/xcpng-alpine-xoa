#!/bin/bash

set -e

ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64"
ISO_NAME_PREFIX="alpine-virt"
VM_BASE_NAME="Alpine-Docker-XOA"
VM_NAME="${VM_BASE_NAME}-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
ISO_DIR="/var/tmp/xcpng-isos"

echo ">>> Fetching latest Alpine virt ISO filename..."
ISO_FILENAME=$(curl -s "$ALPINE_MIRROR/" \
  | grep "${ISO_NAME_PREFIX}-.*x86_64\.iso" \
  | sed -n 's/.*href="\([^"]*\)".*/\1/p' \
  | grep -v '\.sha' \
  | sort -V \
  | tail -n 1)

ISO_URL="${ALPINE_MIRROR}/${ISO_FILENAME}"
ISO_PATH="${ISO_DIR}/${ISO_FILENAME}"

echo ">>> Latest ISO found: ${ISO_FILENAME}"
mkdir -p "$ISO_DIR"

if [ ! -f "$ISO_PATH" ]; then
  echo ">>> Downloading ISO..."
  curl -L -o "$ISO_PATH" "$ISO_URL"
else
  echo ">>> ISO already exists. Skipping download."
fi

echo ">>> Checking for ISO SR..."
ISO_SRS=$(xe sr-list type=iso --minimal)

if [ -z "$ISO_SRS" ]; then
  echo ">>> No ISO SR found. Creating 'ISO Library'..."
  xe sr-create name-label="ISO Library" type=iso device-config:location="$ISO_DIR" device-config:legacy_mode=true content-type=iso
  ISO_SR_UUID=$(xe sr-list name-label="ISO Library" --minimal)
else
  echo ">>> Existing ISO SR(s) detected:"
  ISO_SR_LABELS=$(xe sr-list type=iso params=name-label --minimal | tr ',' '\n')
  select SR in $ISO_SR_LABELS "Create a new ISO SR named 'ISO Library'"; do
    if [ "$SR" = "Create a new ISO SR named 'ISO Library'" ]; then
      echo ">>> Creating new ISO SR 'ISO Library'..."
      xe sr-create name-label="ISO Library" type=iso device-config:location="$ISO_DIR" device-config:legacy_mode=true content-type=iso
      ISO_SR_UUID=$(xe sr-list name-label="ISO Library" --minimal)
    else
      ISO_SR_UUID=$(xe sr-list name-label="$SR" --minimal)
    fi
    break
  done
fi

echo ">>> Rescanning ISO SR..."
xe-mount-iso-sr --uuid "$ISO_SR_UUID"
xe sr-scan uuid="$ISO_SR_UUID"

echo ">>> Creating VM: $VM_NAME"
VM_UUID=$(xe vm-install template="Other install media" new-name-label="$VM_NAME")

echo ">>> Setting VM parameters..."
xe vm-param-set uuid=$VM_UUID HVM-boot-params:order=d
xe vm-param-set uuid=$VM_UUID memory-static-max=512MiB memory-dynamic-max=512MiB memory-dynamic-min=512MiB memory-static-min=512MiB

echo ">>> Creating and attaching disk..."
DISK_UUID=$(xe vdi-create name-label="${VM_NAME}-disk" sr-uuid=$(xe sr-list name-label="Local storage" --minimal) type=user virtual-size=2GiB)
xe vbd-create vm-uuid=$VM_UUID vdi-uuid=$DISK_UUID device=0 type=Disk mode=RW bootable=true

echo ">>> Attaching ISO..."
ISO_VDI_UUID=$(xe vdi-list sr-uuid=$ISO_SR_UUID name-label="$ISO_FILENAME" --minimal)
xe vbd-create vm-uuid=$VM_UUID vdi-uuid=$ISO_VDI_UUID device=3 type=CD mode=RO

echo ">>> Creating network interface..."
NET_UUID=$(xe network-list bridge=xenbr0 --minimal)
xe vif-create vm-uuid=$VM_UUID network-uuid=$NET_UUID device=0

echo ">>> Starting VM..."
xe vm-start uuid=$VM_UUID

DOMID=$(xl list | awk -v name="$VM_NAME" '$1 == name {print $2}')
echo "✅ VM created and started: $VM_NAME"
echo "💻 To access console: xl console $DOMID"
