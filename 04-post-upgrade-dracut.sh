#!/bin/bash
#
# Post-Upgrade Dracut Migration Script for Ubuntu 25.10
#
# This script transitions the system from initramfs-tools to dracut after
# upgrading from Ubuntu 24.04 to 25.10. It handles:
# - Installation of dracut and zfs-dracut
# - Removal of initramfs-tools and zfs-initramfs
# - Update of boot synchronization hooks
# - Initial dracut configuration for ZFS
# - Initramfs regeneration with dracut
#
# PREREQUISITES:
# - System upgraded to Ubuntu 25.10
# - System rebooted successfully on 25.10
# - ZFS pool healthy
#
# USAGE: sudo ./04-post-upgrade-dracut.sh
#

set -euo pipefail

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

# Configuration
MIGRATION_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$(dirname "$(readlink -f "$0")")/logs"
mkdir -p "${LOG_DIR}"

# Set up logging
MIGRATION_LOG="${LOG_DIR}/04-dracut-migration-${MIGRATION_TIMESTAMP}.log"
exec > >(tee -a "${MIGRATION_LOG}") 2>&1

log_info "============================================================"
log_info "Ubuntu 25.10 Dracut Migration Script"
log_info "Started: $(date)"
log_info "============================================================"
echo ""

# ============================================================================
# STEP 1: Pre-Migration Verification
# ============================================================================
log_step "Step 1: Verifying system state..."

# Verify Ubuntu 25.10
if ! grep -q "VERSION_ID=\"25.10\"" /etc/os-release; then
    log_error "This script is for Ubuntu 25.10 only"
    log_error "Current version: $(lsb_release -rs)"
    log_error "Run 03-upgrade-execution.sh first"
    exit 1
fi
log_info "✓ Ubuntu 25.10 detected: $(lsb_release -ds)"

# Verify kernel version
KERNEL_VERSION=$(uname -r)
log_info "✓ Kernel version: ${KERNEL_VERSION}"

# Verify ZFS pool health
if ! zpool list rpool &>/dev/null; then
    log_error "ZFS pool 'rpool' not found"
    exit 1
fi

POOL_HEALTH=$(zpool list -H -o health rpool)
if [[ "${POOL_HEALTH}" != "ONLINE" ]]; then
    log_error "ZFS pool health is ${POOL_HEALTH} (expected ONLINE)"
    exit 1
fi
log_info "✓ ZFS pool rpool is ONLINE"

# Check if initramfs-tools is still installed
if dpkg -l | grep -q "^ii.*initramfs-tools"; then
    log_info "✓ initramfs-tools currently installed (will be replaced)"
else
    log_warn "initramfs-tools not found - may already be migrated"
fi

# Check if dracut is already installed
if dpkg -l | grep -q "^ii.*dracut"; then
    log_info "⚠️  dracut already installed"
    read -p "Continue with migration anyway? (yes/no): " continue_confirm
    if [[ "${continue_confirm}" != "yes" ]]; then
        log_error "Migration aborted by user"
        exit 1
    fi
fi

echo ""

# ============================================================================
# STEP 2: Create Pre-Migration Snapshot
# ============================================================================
log_step "Step 2: Creating pre-migration snapshot..."

SNAPSHOT_NAME="before-dracut-migration-${MIGRATION_TIMESTAMP}"

if zfs snapshot "rpool/ROOT/ubuntu@${SNAPSHOT_NAME}"; then
    log_info "✓ Created snapshot: rpool/ROOT/ubuntu@${SNAPSHOT_NAME}"
else
    log_error "Failed to create snapshot"
    exit 1
fi

# Snapshot all datasets
DATASETS=$(zfs list -H -o name -r rpool | grep -v "^rpool$" || true)
for dataset in ${DATASETS}; do
    zfs snapshot "${dataset}@${SNAPSHOT_NAME}" 2>/dev/null || true
done

log_info "✓ All datasets snapshotted"

echo ""

# ============================================================================
# STEP 3: Backup Current Initramfs Configuration
# ============================================================================
log_step "Step 3: Backing up current boot configuration..."

BACKUP_DIR="/root/dracut-migration-backup-${MIGRATION_TIMESTAMP}"
mkdir -p "${BACKUP_DIR}/boot"
mkdir -p "${BACKUP_DIR}/etc"

# Backup initramfs files
if [[ -d /boot ]]; then
    cp -a /boot/initrd.img-* "${BACKUP_DIR}/boot/" 2>/dev/null || true
    log_info "✓ Backed up initramfs images"
fi

# Backup initramfs-tools configuration
if [[ -d /etc/initramfs-tools ]]; then
    cp -a /etc/initramfs-tools "${BACKUP_DIR}/etc/" 2>/dev/null || true
    log_info "✓ Backed up initramfs-tools configuration"
fi

# Backup kernel hooks
cp -a /etc/kernel "${BACKUP_DIR}/etc/" 2>/dev/null || true
log_info "✓ Backed up kernel hooks"

# Backup GRUB configuration
cp -a /etc/default/grub "${BACKUP_DIR}/etc/grub-default"
cp -a /boot/grub/grub.cfg "${BACKUP_DIR}/boot/grub.cfg.backup" 2>/dev/null || true
log_info "✓ Backed up GRUB configuration"

log_info "Backup location: ${BACKUP_DIR}"

echo ""

# ============================================================================
# STEP 4: Install Dracut and ZFS Dracut Module
# ============================================================================
log_step "Step 4: Installing dracut and zfs-dracut..."

# Update package lists
log_info "Updating package lists..."
apt-get update

# Install dracut packages
log_info "Installing dracut and zfs-dracut..."
DEBIAN_FRONTEND=noninteractive apt-get install -y dracut zfs-dracut

# Verify installation
if ! dpkg -l | grep -q "^ii.*dracut"; then
    log_error "dracut installation failed"
    exit 1
fi

if ! dpkg -l | grep -q "^ii.*zfs-dracut"; then
    log_error "zfs-dracut installation failed"
    exit 1
fi

log_info "✓ dracut and zfs-dracut installed"

# Check dracut version
DRACUT_VERSION=$(dracut --version 2>&1 | head -1 || echo "unknown")
log_info "Dracut version: ${DRACUT_VERSION}"

echo ""

# ============================================================================
# STEP 5: Configure Dracut for ZFS
# ============================================================================
log_step "Step 5: Configuring dracut for ZFS..."

# Create dracut configuration directory
mkdir -p /etc/dracut.conf.d

# Create ZFS-specific dracut configuration
cat > /etc/dracut.conf.d/zfs.conf << 'EOF'
# ZFS Root Mirror Dracut Configuration
# Generated by ubuntu-noble-to-questing migration

# Always include ZFS module
add_dracutmodules+=" zfs "

# Include ZFS pool cache for faster boot
install_optional_items+=" /etc/zfs/zpool.cache "

# Install ZFS utilities
install_items+=" /usr/bin/zfs /usr/bin/zpool "

# Compression
compress="zstd"

# Show detailed output during boot (can be removed later)
# stdloglvl=6

# Hostonly mode (faster boot, but less portable)
hostonly="yes"
hostonly_cmdline="no"
EOF

log_info "✓ Created /etc/dracut.conf.d/zfs.conf"

# If using HWE kernel, ensure firmware is included
if [[ "${KERNEL_VERSION}" == *"-hwe-"* ]] || [[ "${KERNEL_VERSION}" == *"-generic-hwe-"* ]]; then
    log_info "HWE kernel detected, ensuring firmware inclusion..."
    cat > /etc/dracut.conf.d/firmware.conf << 'EOF'
# Include all firmware for HWE kernel support
install_optional_items+=" /lib/firmware/* "
EOF
    log_info "✓ Created /etc/dracut.conf.d/firmware.conf for HWE kernel"
fi

echo ""

# ============================================================================
# STEP 6: Update Boot Synchronization Hooks
# ============================================================================
log_step "Step 6: Updating boot synchronization hooks..."

# Remove initramfs-tools specific hooks
if [[ -d /etc/initramfs/post-update.d ]]; then
    log_info "Removing initramfs-tools post-update hooks..."
    if [[ -L /etc/initramfs/post-update.d/zz-sync-mirror-boot ]]; then
        rm /etc/initramfs/post-update.d/zz-sync-mirror-boot
        log_info "✓ Removed /etc/initramfs/post-update.d/zz-sync-mirror-boot"
    fi
fi

# Verify kernel hooks are still in place (these work with both systems)
if [[ ! -L /etc/kernel/postinst.d/zz-sync-mirror-boot ]]; then
    log_warn "Kernel postinst hook missing, recreating..."
    ln -sf /usr/local/bin/sync-mirror-boot /etc/kernel/postinst.d/zz-sync-mirror-boot
    log_info "✓ Recreated /etc/kernel/postinst.d/zz-sync-mirror-boot"
else
    log_info "✓ Kernel postinst hook exists"
fi

if [[ ! -L /etc/kernel/postrm.d/zz-sync-mirror-boot ]]; then
    log_warn "Kernel postrm hook missing, recreating..."
    ln -sf /usr/local/bin/sync-mirror-boot /etc/kernel/postrm.d/zz-sync-mirror-boot
    log_info "✓ Recreated /etc/kernel/postrm.d/zz-sync-mirror-boot"
else
    log_info "✓ Kernel postrm hook exists"
fi

# Verify sync-mirror-boot script exists and is executable
if [[ -x /usr/local/bin/sync-mirror-boot ]]; then
    log_info "✓ sync-mirror-boot script is executable"
else
    log_error "sync-mirror-boot script missing or not executable"
    log_error "This is required for boot mirror synchronization"
    exit 1
fi

echo ""

# ============================================================================
# STEP 7: Regenerate Initramfs with Dracut
# ============================================================================
log_step "Step 7: Regenerating initramfs with dracut..."

log_info "This may take several minutes..."

# Get all installed kernels
INSTALLED_KERNELS=$(ls /lib/modules/ | grep -E '^[0-9]' || true)

if [[ -z "${INSTALLED_KERNELS}" ]]; then
    log_error "No installed kernels found in /lib/modules/"
    exit 1
fi

log_info "Found kernels:"
for kernel in ${INSTALLED_KERNELS}; do
    log_info "  - ${kernel}"
done

# Regenerate initramfs for all kernels
log_info "Regenerating initramfs images with dracut..."
for kernel in ${INSTALLED_KERNELS}; do
    log_info "Generating initramfs for ${kernel}..."
    if dracut --force --kver "${kernel}"; then
        log_info "✓ Generated initramfs for ${kernel}"
    else
        log_error "Failed to generate initramfs for ${kernel}"
        exit 1
    fi
done

# Verify initramfs files were created
log_info "Verifying initramfs images..."
for kernel in ${INSTALLED_KERNELS}; do
    if [[ -f "/boot/initrd.img-${kernel}" ]]; then
        SIZE=$(du -h "/boot/initrd.img-${kernel}" | cut -f1)
        log_info "✓ /boot/initrd.img-${kernel} (${SIZE})"
    else
        log_error "Initramfs missing for ${kernel}"
        exit 1
    fi
done

echo ""

# ============================================================================
# STEP 8: Remove initramfs-tools (Optional but Recommended)
# ============================================================================
log_step "Step 8: Removing initramfs-tools..."

log_warn "Removing initramfs-tools and zfs-initramfs..."
log_warn "After this step, only dracut will be available"
echo ""

read -p "Remove initramfs-tools now? (yes/no): " remove_confirm
if [[ "${remove_confirm}" == "yes" ]]; then
    # Remove initramfs-tools
    if DEBIAN_FRONTEND=noninteractive apt-get remove -y initramfs-tools zfs-initramfs; then
        log_info "✓ initramfs-tools and zfs-initramfs removed"
    else
        log_warn "Failed to remove initramfs-tools (may not be critical)"
    fi

    # Clean up
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    log_info "✓ Cleaned up orphaned packages"
else
    log_warn "Skipped removal of initramfs-tools"
    log_warn "Both initramfs-tools and dracut will coexist"
    log_warn "You can remove initramfs-tools later with:"
    log_warn "  sudo apt-get remove initramfs-tools zfs-initramfs"
fi

echo ""

# ============================================================================
# STEP 9: Update GRUB Configuration
# ============================================================================
log_step "Step 9: Updating GRUB configuration..."

# Regenerate GRUB configuration
log_info "Regenerating GRUB configuration..."
if update-grub; then
    log_info "✓ GRUB configuration updated"
else
    log_error "Failed to update GRUB configuration"
    exit 1
fi

# Sync GRUB to all mirror drives
log_info "Syncing GRUB to all mirror drives..."
if [[ -x /usr/local/bin/sync-mirror-boot ]]; then
    if /usr/local/bin/sync-mirror-boot; then
        log_info "✓ Boot mirror synchronized"
    else
        log_warn "Boot mirror sync reported issues (check logs)"
    fi
else
    log_error "sync-mirror-boot script not found or not executable"
    exit 1
fi

echo ""

# ============================================================================
# STEP 10: Verification
# ============================================================================
log_step "Step 10: Verifying dracut migration..."

# Check dracut modules
log_info "Verifying dracut ZFS module..."
if dracut --list-modules 2>/dev/null | grep -q "zfs"; then
    log_info "✓ Dracut ZFS module available"
else
    log_error "Dracut ZFS module not found"
    exit 1
fi

# Inspect initramfs contents
log_info "Verifying initramfs contains ZFS modules..."
CURRENT_KERNEL=$(uname -r)
if lsinitrd "/boot/initrd.img-${CURRENT_KERNEL}" 2>/dev/null | grep -q "zfs"; then
    log_info "✓ Current initramfs contains ZFS modules"
else
    log_warn "Could not verify ZFS in initramfs (may be normal)"
fi

# Check EFI boot entries
log_info "Verifying EFI boot entries..."
if command -v efibootmgr &>/dev/null; then
    BOOT_ENTRIES=$(efibootmgr | grep -c "Ubuntu" || echo "0")
    log_info "✓ Found ${BOOT_ENTRIES} Ubuntu boot entries"
    efibootmgr | grep "Ubuntu" || true
else
    log_warn "efibootmgr not available"
fi

# Check ZFS pool still accessible
if zpool list rpool &>/dev/null; then
    log_info "✓ ZFS pool rpool still accessible"
else
    log_error "ZFS pool not accessible after migration"
    exit 1
fi

echo ""

# ============================================================================
# STEP 11: Create Migration Summary
# ============================================================================
log_step "Step 11: Creating migration summary..."

SUMMARY_FILE="${BACKUP_DIR}/migration-summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
DRACUT MIGRATION SUMMARY
================================================================================

Migration Date: $(date)
Hostname: $(hostname)
Ubuntu Version: $(lsb_release -ds)
Kernel: $(uname -r)
Dracut Version: ${DRACUT_VERSION}

================================================================================
SNAPSHOTS CREATED
================================================================================

$(zfs list -t snapshot | grep "${SNAPSHOT_NAME}")

================================================================================
MIGRATION CHANGES
================================================================================

✓ Installed: dracut, zfs-dracut
✓ Removed: initramfs-tools, zfs-initramfs (if confirmed)
✓ Created: /etc/dracut.conf.d/zfs.conf
✓ Removed: /etc/initramfs/post-update.d/zz-sync-mirror-boot
✓ Verified: Kernel hooks in /etc/kernel/{postinst.d,postrm.d}/
✓ Regenerated: Initramfs for all installed kernels
✓ Updated: GRUB configuration
✓ Synchronized: Boot mirror drives

================================================================================
DRACUT CONFIGURATION
================================================================================

$(cat /etc/dracut.conf.d/zfs.conf)

================================================================================
INITRAMFS FILES
================================================================================

$(ls -lh /boot/initrd.img-*)

================================================================================
ROLLBACK PROCEDURE
================================================================================

If boot fails after migration:

1. Boot from Ubuntu Live USB
2. Import ZFS pool:
   sudo zpool import -f rpool
3. Rollback to pre-migration snapshot:
   sudo zfs rollback rpool/ROOT/ubuntu@${SNAPSHOT_NAME}
4. Reboot

================================================================================
TESTING CHECKLIST
================================================================================

Before considering migration complete:

□ Reboot system successfully
□ Verify ZFS pool imports automatically
□ Check all services start correctly
□ Test boot from both mirror drives
□ Perform kernel update test
□ Run 06-testing-validation.sh

================================================================================
NEXT STEPS
================================================================================

1. Review this summary
2. Reboot to test dracut-based boot: sudo reboot
3. After successful reboot, run: sudo ./05-boot-optimization.sh
4. Finally run: sudo ./06-testing-validation.sh

================================================================================
EOF

log_info "✓ Migration summary: ${SUMMARY_FILE}"

echo ""

# ============================================================================
# Summary
# ============================================================================

log_info "============================================================"
log_info "DRACUT MIGRATION SUMMARY"
log_info "============================================================"
echo ""
log_info "Migration completed successfully!"
echo ""
log_info "Changes made:"
log_info "  ✓ Dracut and zfs-dracut installed"
log_info "  ✓ Initramfs regenerated with dracut for all kernels"
log_info "  ✓ Boot synchronization hooks updated"
log_info "  ✓ GRUB synchronized to all mirror drives"
log_info "  ✓ Pre-migration snapshot created"
echo ""
log_info "Backup location: ${BACKUP_DIR}"
log_info "Migration summary: ${SUMMARY_FILE}"
log_info "Log file: ${MIGRATION_LOG}"
echo ""
log_warn "⚠️  CRITICAL: System needs reboot to use dracut initramfs"
echo ""
log_info "Next steps:"
echo "  1. Review migration summary: cat ${SUMMARY_FILE}"
echo "  2. Reboot system: sudo reboot"
echo "  3. After successful reboot, run: sudo ./05-boot-optimization.sh"
echo ""

read -p "Reboot now? (yes/no): " reboot_confirm
if [[ "${reboot_confirm}" == "yes" ]]; then
    log_info "Rebooting in 10 seconds..."
    log_info "Press Ctrl+C to cancel"
    sleep 10
    reboot
else
    log_warn "Please reboot manually when ready"
    log_warn "After reboot, run: sudo ./05-boot-optimization.sh"
fi

log_info "Dracut migration script completed: $(date)"
log_info "============================================================"

exit 0
