#!/bin/bash

set -e

# -------- CONFIGURATION --------
VM_NAME="Alpine-Docker"
DISK_SIZE_GB=8
MEMORY_MB=1024
VCPUS=1
ISO_DIR="/var/opt/xen/iso_import"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64"

# -------- PREP ISO STORAGE --------
echo ">>> Checking ISO storage directory..."

if [ ! -d "$ISO_DIR" ]; then
  echo ">>> ISO directory $ISO_DIR does not exist. Creating it..."
  mkdir -p "$ISO_DIR"
else
  echo "✅ ISO directory exists: $ISO_DIR"
fi

FREE_KB=$(df --output=avail -k "$ISO_DIR" | tail -n 1)
if [ "$FREE_KB" -lt 1048576 ]; then
  echo "❌ Not enough free space in $ISO_DIR (need at least 1 GiB)"
  exit 1
fi

# -------- FETCH LATEST ISO NAME --------
echo ">>> Fetching latest Alpine ISO filename..."
ISO_FILENAME=$(curl -s "$ALPINE_MIRROR/" \
  | grep -oE 'alpine-standard-[0-9.]+-x86_64\.iso"' \
  | sed 's/"$//' \
  | sort -V \
  | tail -n 1)

if [ -z "$ISO_FILENAME" ]; then
  echo "❌ Could not determine latest Alpine ISO. Exiting."
  exit 1
fi

SHA_FILENAME="${ISO_FILENAME}.sha512"

echo "✅ Latest Alpine ISO: $ISO_FILENAME"

# -------- DOWNLOAD AND VERIFY ISO --------
cd "$ISO_DIR"

if [ ! -f "$ISO_FILENAME" ]; then
  echo ">>> Downloading ISO: $ISO_FILENAME"
  wget "$ALPINE_MIRROR/$ISO_FILENAME"
else
  echo "✅ ISO already downloaded: $ISO_FILENAME"
fi

if [ ! -f "$SHA_FILENAME" ]; then
  echo ">>> Downloading checksum: $SHA_FILENAME"
  wget "$ALPINE_MIRROR/$SHA_FILENAME"
else
  echo "✅ SHA512 already downloaded: $SHA_FILENAME"
fi

echo ">>> Verifying checksum..."
SHA_CHECK=$(sed "s| \*.*| *$ISO_FILENAME|" "$SHA_FILENAME" | sha512sum -c - 2>/dev/null)

if echo "$SHA_CHECK" | grep -q ": OK"; then
  echo "✅ Checksum verified successfully."
else
  echo "❌ Checksum verification failed. Exiting."
  exit 1
fi

# -------- HANDLE ISO SR SELECTION --------
echo ">>> Checking for existing ISO SRs..."
ISO_SR_LIST=($(xe sr-list type=iso --minimal | tr ',' ' '))

if [ ${#ISO_SR_LIST[@]} -eq 0 ]; then
  echo "⚠️  No ISO SRs found. Creating a new ISO SR named 'ISO Library'..."
  xe sr-create name-label="ISO Library" type=iso device-config:location="$ISO_DIR" device-config:legacy_mode=true content-type=iso

  ISO_SR_DUPES=$(xe sr-list name-label="ISO Library" --minimal | tr ',' '\n' | wc -l)
  if [ "$ISO_SR_DUPES" -gt 1 ]; then
    echo "⚠️ Warning: Multiple SRs named 'ISO Library' exist. Using the first match."
  fi

  ISO_SR_UUID=$(xe sr-list name-label="ISO Library" --minimal | cut -d, -f1)

else
  echo "✅ Found the following ISO SRs:"
  i=1
  for sr in "${ISO_SR_LIST[@]}"; do
    NAME=$(xe sr-param-get uuid=$sr param-name=name-label)
    echo "  [$i] $NAME ($sr)"
    ISO_SR_NAMES[$i]=$NAME
    ISO_SR_UUIDS[$i]=$sr
    i=$((i+1))
  done

  echo "  [$i] Create a new ISO SR named 'ISO Library'"

  read -p ">>> Choose ISO SR to use [1-$i]: " CHOICE
  if [ "$CHOICE" == "$i" ]; then
    echo ">>> Creating ISO SR 'ISO Library'..."
    xe sr-create name-label="ISO Library" type=iso device-config:location="$ISO_DIR" device-config:legacy_mode=true content-type=iso

    ISO_SR_DUPES=$(xe sr-list name-label="ISO Library" --minimal | tr ',' '\n' | wc -l)
    if [ "$ISO_SR_DUPES" -gt 1 ]; then
      echo "⚠️ Warning: Multiple SRs named 'ISO Library' exist. Using the first match."
    fi

    ISO_SR_UUID=$(xe sr-list name-label="ISO Library" --minimal | cut -d, -f1)
  else
    ISO_SR_UUID=${ISO_SR_UUIDS[$CHOICE]}
    echo "✅ Using existing ISO SR: ${ISO_SR_NAMES[$CHOICE]}"
  fi
fi

# -------- RESCAN ISO SR --------
echo ">>> Rescanning ISO SR..."
xe sr-scan uuid="$ISO_SR_UUID"

# -------- LOOKUP RESOURCES --------
TEMPLATE_UUID=$(xe template-list name-label="Other install media" --minimal)
SR_UUID=$(xe sr-list name-label="Local storage" --minimal)

NETWORK_UUID=$(xe network-list bridge=xenbr0 --minimal)
[ -z "$NETWORK_UUID" ] && NETWORK_UUID=$(xe network-list --minimal | cut -d, -f1)

# -------- CREATE VM --------
echo ">>> Creating VM: $VM_NAME"
VM_UUID=$(xe vm-install new-name-label="$VM_NAME" template="$TEMPLATE_UUID")

echo ">>> Setting memory and CPU..."
xe vm-param-set uuid=$VM_UUID memory-static-max=${MEMORY_MB}MiB memory-dynamic-max=${MEMORY_MB}MiB memory-dynamic-min=${MEMORY_MB}MiB memory-static-min=${MEMORY_MB}MiB
xe vm-param-set uuid=$VM_UUID VCPUs-max=$VCPUS VCPUs-at-startup=$VCPUS

# -------- DISK SETUP --------
echo ">>> Creating and attaching disk..."
VDI_SIZE_BYTES=$(($DISK_SIZE_GB * 1024 * 1024 * 1024))
VDI_UUID=$(xe vdi-create name-label="${VM_NAME}-disk" sr-uuid=$SR_UUID type=user virtual-size=$VDI_SIZE_BYTES || true)

if [ -n "$VDI_UUID" ]; then
  echo "✅ VDI created: $VDI_UUID"
  VBD_UUID=$(xe vbd-create vm-uuid=$VM_UUID vdi-uuid=$VDI_UUID device=0 bootable=true mode=RW type=Disk)
  echo "✅ VBD created: $VBD_UUID"
else
  echo "⚠️ Could not create VDI manually. Falling back to inline creation..."
  xe vm-disk-add vm=$VM_UUID sr-uuid=$SR_UUID device=0 disk-size=$VDI_SIZE_BYTES
fi

# -------- NETWORK & ISO --------
echo ">>> Adding network interface..."
xe vif-create vm-uuid=$VM_UUID network-uuid=$NETWORK_UUID device=0

echo ">>> Attaching ISO..."
xe vm-cd-add vm=$VM_UUID cd-name="$ISO_FILENAME" device=3
xe vm-param-set uuid=$VM_UUID other-config:install-method=cdrom
xe vm-param-set uuid=$VM_UUID HVM-boot-params:order=d

# -------- START VM --------
echo ">>> Starting VM..."
xe vm-start uuid=$VM_UUID

# -------- SHOW CONSOLE COMMAND --------
DOMID=$(xl list | awk -v name="$VM_NAME" '$1 == name {print $2}')

echo "✅ VM '$VM_NAME' created and booted!"
echo "💡 To access the console, run:"
echo "    xl console $DOMID"
