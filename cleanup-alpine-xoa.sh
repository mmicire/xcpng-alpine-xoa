#!/bin/bash

set -e

# -------- DEFAULTS --------
DRY_RUN=false
LOG_FILE=""
PREFIX="Alpine-Docker-XOA-"
CLEAN_ISOS=false
SCRIPT_NAME=$(basename "$0")

# -------- FUNCTIONS --------

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Clean up VMs matching a given prefix and optionally unused ISOs.

Options:
  --dry-run           Show what would be deleted but take no action
  --log FILE          Write all output to specified log file
  --prefix NAME       Custom VM name prefix to match (default: Alpine-Docker-XOA-)
  --clean-isos        Delete unused ISOs from ISO SRs
  --help              Show this help message and exit
EOF
  exit 0
}

log() {
  echo "$@"
  if [ -n "$LOG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') $@" >> "$LOG_FILE"
  fi
}

action() {
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] $@"
  else
    log "$@"
    eval "$@"
  fi
}

# -------- ARG PARSING --------

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true ;;
    --log)
      shift
      LOG_FILE="$1"
      ;;
    --prefix)
      shift
      PREFIX="$1"
      ;;
    --clean-isos) CLEAN_ISOS=true ;;
    --help) usage ;;
    *) echo "❌ Unknown option: $1"; usage ;;
  esac
  shift
done

log ">>> Starting cleanup of VMs matching prefix '$PREFIX'..."

# -------- VM CLEANUP --------

VM_UUIDS=$(xe vm-list is-control-domain=false --minimal | tr ',' '\n' | while read UUID; do
  NAME=$(xe vm-param-get uuid=$UUID param-name=name-label)
  if echo "$NAME" | grep -q "^$PREFIX"; then
    echo "$UUID"
  fi
done)

if [ -z "$VM_UUIDS" ]; then
  log "✅ No matching VMs found. Nothing to clean."
else
  for VM_UUID in $VM_UUIDS; do
    VM_NAME=$(xe vm-param-get uuid=$VM_UUID param-name=name-label)
    log "🗑 Found VM: $VM_NAME ($VM_UUID)"

    log "⚡ Forcing power reset for $VM_NAME..."
    if ! action "xe vm-reset-powerstate force=true uuid=$VM_UUID" 2>/dev/null; then
      log "⚠️  xe failed — trying low-level xl destroy..."
      DOMID=$(xl list | awk -v name="$VM_NAME" '$1 == name {print $2}')
      if [ -n "$DOMID" ]; then
        log "🔨 Running: xl destroy $DOMID"
        action "xl destroy $DOMID"

        # Wait for domain to disappear
        log "⏳ Waiting for domain to be destroyed..."
        for i in {1..10}; do
          sleep 1
          STILL_RUNNING=$(xl list | awk '{print $1}' | grep -Fx "$VM_NAME" || true)
          if [ -z "$STILL_RUNNING" ]; then
            log "✅ Domain destroyed."
            sleep 3
            break
          fi
          if [ $i -eq 10 ]; then
            log "❌ Domain $VM_NAME is still active after 10 seconds. Aborting."
            exit 1
          fi
        done
      else
        log "ℹ️ No domid found — may already be stopped."
        sleep 3
      fi
    else
      log "✅ Power reset completed via xe."
      sleep 3
    fi

    # Destroy VIFs
    VIF_UUIDS=$(xe vif-list vm-uuid=$VM_UUID --minimal | tr ',' ' ')
    for VIF in $VIF_UUIDS; do
      log "🔌 Destroying VIF $VIF"
      if ! action "xe vif-destroy uuid=$VIF" 2>/dev/null; then
        log "⚠️ VIF $VIF destroy failed — retrying after 2s..."
        sleep 2
        action "xe vif-destroy uuid=$VIF" || log "❌ Failed to destroy VIF $VIF"
      fi
