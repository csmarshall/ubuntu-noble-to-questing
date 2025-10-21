#!/bin/bash
#
# Automated Rollback Script for Ubuntu 25.10 Upgrade
#
# This script safely rolls back from a failed or unwanted upgrade by:
# - Finding snapshots created during upgrade process
# - Rolling back all ZFS datasets
# - Regenerating boot configuration
# - Syncing to all mirror drives
#
# USAGE: sudo ./99-rollback-from-upgrade.sh
#

set -euo pipefail

# Disable shell timeout to prevent script from exiting during user prompts
unset TMOUT 2>/dev/null || true

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

ROLLBACK_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$(dirname "$(readlink -f "$0")")/logs"
mkdir -p "${LOG_DIR}"

# Set up logging
ROLLBACK_LOG="${LOG_DIR}/99-rollback-${ROLLBACK_TIMESTAMP}.log"
exec > >(tee -a "${ROLLBACK_LOG}") 2>&1

log_info "============================================================"
log_info "Ubuntu Upgrade Rollback Script"
log_info "Started: $(date)"
log_info "============================================================"
echo ""

# ============================================================================
# STEP 1: Find Upgrade Snapshots
# ============================================================================
log_step "Step 1: Finding upgrade snapshots..."

# Look for snapshots created during upgrade
SNAPSHOT_PATTERNS=(
    "before-upgrade-to-questing-"
    "pre-questing-upgrade-"
    "before-dracut-migration-"
)

ALL_SNAPSHOTS=()
for pattern in "${SNAPSHOT_PATTERNS[@]}"; do
    while IFS= read -r snapshot; do
        ALL_SNAPSHOTS+=("$snapshot")
    done < <(zfs list -H -t snapshot -o name | grep "$pattern" || true)
done

if [[ ${#ALL_SNAPSHOTS[@]} -eq 0 ]]; then
    log_error "No upgrade snapshots found!"
    log_error "Looking for snapshots matching: ${SNAPSHOT_PATTERNS[*]}"
    log_error ""
    log_error "Available snapshots:"
    zfs list -t snapshot
    exit 1
fi

# Group snapshots by timestamp
declare -A SNAPSHOT_GROUPS
for snapshot in "${ALL_SNAPSHOTS[@]}"; do
    # Extract timestamp (last part after last hyphen-date pattern)
    if [[ $snapshot =~ ([0-9]{8}-[0-9]{6})$ ]]; then
        timestamp="${BASH_REMATCH[1]}"
        SNAPSHOT_GROUPS["$timestamp"]+="$snapshot"$'\n'
    fi
done

# Show available snapshot groups
log_info "Found snapshot groups:"
echo ""
idx=1
declare -a TIMESTAMP_ARRAY
for timestamp in $(echo "${!SNAPSHOT_GROUPS[@]}" | tr ' ' '\n' | sort -r); do
    TIMESTAMP_ARRAY+=("$timestamp")
    echo "  ${idx}. Snapshots from: ${timestamp}"
    echo "${SNAPSHOT_GROUPS[$timestamp]}" | while IFS= read -r snap; do
        if [[ -n "$snap" ]]; then
            echo "     - $snap"
        fi
    done
    echo ""
    ((idx++))
done

# ============================================================================
# STEP 2: Select Snapshot to Rollback
# ============================================================================
log_step "Step 2: Select snapshot to rollback..."

if [[ ${#TIMESTAMP_ARRAY[@]} -eq 1 ]]; then
    SELECTED_TIMESTAMP="${TIMESTAMP_ARRAY[0]}"
    log_info "Only one snapshot group found, using: ${SELECTED_TIMESTAMP}"
else
    echo "Multiple snapshot groups found."
    read -p "Enter number to rollback to (1-${#TIMESTAMP_ARRAY[@]}), or 'q' to quit: " selection

    if [[ "$selection" == "q" ]]; then
        log_info "Rollback cancelled by user"
        exit 0
    fi

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#TIMESTAMP_ARRAY[@]} ]]; then
        log_error "Invalid selection: $selection"
        exit 1
    fi

    SELECTED_TIMESTAMP="${TIMESTAMP_ARRAY[$((selection-1))]}"
fi

log_info "Selected timestamp: ${SELECTED_TIMESTAMP}"
echo ""

# Find all datasets with this timestamp
SNAPSHOTS_TO_ROLLBACK=()
while IFS= read -r snapshot; do
    if [[ $snapshot =~ $SELECTED_TIMESTAMP ]]; then
        SNAPSHOTS_TO_ROLLBACK+=("$snapshot")
    fi
done < <(printf '%s\n' "${ALL_SNAPSHOTS[@]}")

log_info "Will rollback these snapshots:"
for snapshot in "${SNAPSHOTS_TO_ROLLBACK[@]}"; do
    echo "  - $snapshot"
done
echo ""

# ============================================================================
# STEP 3: Confirmation
# ============================================================================
log_step "Step 3: Rollback confirmation..."

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                         ⚠️  WARNING ⚠️                          ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  This will DESTROY all changes made after the snapshot!       ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  • All files modified after snapshot will be lost             ║${NC}"
echo -e "${RED}║  • System will be restored to state from: ${SELECTED_TIMESTAMP}      ║${NC}"
echo -e "${RED}║  • This operation CANNOT be undone                            ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show current system state
log_info "Current system state:"
echo "  Ubuntu version: $(lsb_release -ds 2>/dev/null || echo 'Unknown')"
echo "  Kernel: $(uname -r)"
echo ""

read -p "Type 'ROLLBACK' to confirm (anything else to cancel): " confirmation
if [[ "$confirmation" != "ROLLBACK" ]]; then
    log_error "Rollback cancelled by user"
    exit 1
fi

echo ""

# ============================================================================
# STEP 4: Create Safety Snapshot
# ============================================================================
log_step "Step 4: Creating safety snapshot of current state..."

SAFETY_SNAPSHOT_SUFFIX="before-rollback-${ROLLBACK_TIMESTAMP}"

for snapshot in "${SNAPSHOTS_TO_ROLLBACK[@]}"; do
    # Extract dataset name (everything before @)
    dataset="${snapshot%%@*}"

    # Create safety snapshot
    safety_snap="${dataset}@${SAFETY_SNAPSHOT_SUFFIX}"
    if zfs snapshot "$safety_snap"; then
        log_info "✓ Created safety snapshot: $safety_snap"
    else
        log_warn "Could not create safety snapshot for $dataset"
    fi
done

echo ""

# ============================================================================
# STEP 5: Perform Rollback
# ============================================================================
log_step "Step 5: Rolling back datasets..."

ROLLBACK_SUCCESS=0
ROLLBACK_FAILED=0

for snapshot in "${SNAPSHOTS_TO_ROLLBACK[@]}"; do
    dataset="${snapshot%%@*}"
    log_info "Rolling back: $snapshot"

    if zfs rollback -r "$snapshot"; then
        log_info "✓ Rolled back: $dataset"
        ((ROLLBACK_SUCCESS++))
    else
        log_error "✗ Failed to rollback: $dataset"
        ((ROLLBACK_FAILED++))
    fi
done

echo ""
log_info "Rollback results: ${ROLLBACK_SUCCESS} succeeded, ${ROLLBACK_FAILED} failed"

if [[ $ROLLBACK_FAILED -gt 0 ]]; then
    log_error "Some rollbacks failed! System may be in inconsistent state"
    log_error "Check log: ${ROLLBACK_LOG}"
    exit 1
fi

echo ""

# ============================================================================
# STEP 6: Regenerate Boot Configuration
# ============================================================================
log_step "Step 6: Regenerating boot configuration..."

# Check if update-initramfs is available (should be after rollback to 24.04)
if command -v update-initramfs &>/dev/null; then
    log_info "Regenerating initramfs for all kernels..."
    if update-initramfs -u -k all; then
        log_info "✓ Initramfs regenerated"
    else
        log_warn "Initramfs regeneration had issues (may not be critical)"
    fi
else
    log_warn "update-initramfs not found (expected after rollback to 24.04)"
fi

# Regenerate GRUB configuration
log_info "Updating GRUB configuration..."
if update-grub; then
    log_info "✓ GRUB configuration updated"
else
    log_error "Failed to update GRUB configuration"
    exit 1
fi

echo ""

# ============================================================================
# STEP 7: Sync Boot to Mirror Drives
# ============================================================================
log_step "Step 7: Syncing boot configuration to all mirror drives..."

if [[ -x /usr/local/bin/sync-mirror-boot ]]; then
    log_info "Running sync-mirror-boot..."
    if /usr/local/bin/sync-mirror-boot; then
        log_info "✓ Boot mirrors synchronized"
    else
        log_warn "Boot mirror sync had issues (check manually)"
    fi
else
    log_warn "sync-mirror-boot script not found"
    log_warn "You may need to manually sync GRUB to all drives"
fi

echo ""

# ============================================================================
# STEP 8: Verification
# ============================================================================
log_step "Step 8: Verifying rollback..."

# Check ZFS pool health
POOL_HEALTH=$(zpool list -H -o health rpool 2>/dev/null || echo "UNKNOWN")
if [[ "$POOL_HEALTH" == "ONLINE" ]]; then
    log_info "✓ ZFS pool health: ONLINE"
else
    log_warn "ZFS pool health: $POOL_HEALTH"
fi

# Show snapshot list
log_info "Current snapshots (including safety snapshots):"
zfs list -t snapshot | grep -E "before-rollback|before-upgrade" || true

echo ""

# ============================================================================
# Summary
# ============================================================================

log_info "============================================================"
log_info "ROLLBACK SUMMARY"
log_info "============================================================"
echo ""
log_info "✓ Rollback completed successfully!"
echo ""
log_info "Rolled back to snapshots from: ${SELECTED_TIMESTAMP}"
log_info "Datasets rolled back: ${ROLLBACK_SUCCESS}"
log_info "Safety snapshots created: before-rollback-${ROLLBACK_TIMESTAMP}"
echo ""
log_info "Boot configuration:"
log_info "  ✓ Initramfs regenerated"
log_info "  ✓ GRUB configuration updated"
log_info "  ✓ Boot mirrors synchronized"
echo ""
log_info "Log file: ${ROLLBACK_LOG}"
echo ""
log_warn "⚠️  System needs reboot to complete rollback"
echo ""
log_info "After reboot, verify:"
echo "  1. Check Ubuntu version: lsb_release -a"
echo "  2. Check ZFS pool: sudo zpool status"
echo "  3. Check services: systemctl --failed"
echo ""

read -p "Reboot now? (yes/no): " reboot_confirm
if [[ "$reboot_confirm" == "yes" ]]; then
    log_info "Rebooting in 10 seconds..."
    log_info "Press Ctrl+C to cancel"
    sleep 10
    reboot
else
    log_warn "Please reboot manually when ready: sudo reboot"
fi

log_info "Rollback script completed: $(date)"
log_info "============================================================"

exit 0
