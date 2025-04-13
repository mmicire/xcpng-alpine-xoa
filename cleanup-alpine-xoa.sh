#!/bin/bash

set -e

echo ">>> Cleaning up all VMs matching 'Alpine-Docker-XOA-*'..."

# Get all non-control domain VM UUIDs and filter by name prefix
VM_UUIDS=$(xe vm-list is-control-domain=false --minimal | tr ',' '\n' | while read UUID; do
  NAME=$(xe vm-param-get uuid=$UUID param-name=name-label)
  if echo "$NAME" | grep -q '^Alpine-Docker-XOA-'; then
    echo $UUID
  fi
done)

if [ -z "$VM_UUIDS" ]; then
  echo "✅ No matching VMs found. Nothing to clean."
  exit 0
fi

for VM_UUID in $VM_UUIDS; do
  VM_NAME=$(xe vm-param-get uuid=$VM_UUID param-name=name-label)
  echo "🗑 Cleaning up VM: $VM_NAME ($VM_UUID)"

  # Force shutdown with fallback to xl destroy and wait for cleanup
  echo "⚡ Forcing power reset for $VM_NAME..."
  if ! xe vm-reset-powerstate force=true uuid=$VM_UUID 2>/dev/null; then
    echo "⚠️  xe failed — trying low-level xl destroy..."
    DOMID=$(xl list | awk -v name="$VM_NAME" '$1 == name {print $2}')
    if [ -n "$DOMID" ]; then
      echo "🔨 Running: xl destroy $DOMID"
      xl destroy "$DOMID"

      # Wait for domain to disappear
      echo "⏳ Waiting for domain to be destroyed..."
      for i in {1..10}; do
        sleep 1
        STILL_RUNNING=$(xl list | awk '{print $1}' | grep -Fx "$VM_NAME" || true)
        if [ -z "$STILL_RUNNING" ]; then
          echo "✅ Domain destroyed."
          sleep 3  # Allow Xen to settle before device cleanup
          break
        fi
        if [ $i -eq 10 ]; then
          echo "❌ Domain $VM_NAME is still active after 10 seconds. Aborting."
          exit 1
        fi
      done
    else
      echo "ℹ️ No domid found — may already be stopped."
      sleep 3  # Still wait before trying to destroy devices
    fi
  else
    echo "✅ Power reset completed via xe."
    sleep 3  # Allow Xen to settle before cleanup
  fi

  # Unplug and destroy VIFs
  VIF_UUIDS=$(xe vif-list vm-uuid=$VM_UUID --minimal | tr ',' ' ')
  for VIF in $VIF_UUIDS; do
    echo "🔌 Destroying VIF $VIF"
    if ! xe vif-destroy uuid=$VIF 2>/dev/null; then
      echo "⚠️ VIF $VIF destroy failed — retrying after 2s..."
      sleep 2
      xe vif-destroy uuid=$VIF || echo "❌ Failed to destroy VIF $VIF"
    fi
  done

  # Unplug and destroy VBDs and associated VDIs
  VBD_UUIDS=$(xe vbd-list vm-uuid=$VM_UUID --minimal | tr ',' ' ')
  for VBD in $VBD_UUIDS; do
    VDI_UUID=$(xe vbd-param-get uuid=$VBD param-name=vdi-uuid)
    echo "💽 Destroying VBD $VBD and VDI $VDI_UUID"
    if ! xe vbd-unplug uuid=$VBD 2>/dev/null; then
      echo "⚠️ VBD $VBD unplug failed — retrying after 2s..."
      sleep 2
      xe vbd-unplug uuid=$VBD || echo "❌ Failed to unplug VBD $VBD"
    fi
    xe vbd-destroy uuid=$VBD
    if [ -n "$VDI_UUID" ]; then
      xe vdi-destroy uuid=$VDI_UUID
    fi
  done

  # Finally, destroy the VM itself
  echo "🧨 Destroying VM $VM_NAME"
  xe vm-destroy uuid=$VM_UUID
done

echo "✅ Cleanup complete."
