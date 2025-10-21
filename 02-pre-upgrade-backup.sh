#!/bin/bash
#
# Pre-Upgrade Backup Script for Ubuntu 24.04 → 25.10 Upgrade
#
# This script creates comprehensive backups before upgrading:
# - ZFS snapshots of all datasets
# - Configuration file backups
# - Package list export
# - System state documentation
#
# USAGE: sudo ./02-pre-upgrade-backup.sh
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
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/root/upgrade-backups/noble-to-questing-${BACKUP_TIMESTAMP}"
SNAPSHOT_PREFIX="pre-questing-upgrade"
LOG_DIR="$(dirname "$(readlink -f "$0")")/logs"

# Create directories
mkdir -p "${BACKUP_DIR}"
mkdir -p "${LOG_DIR}"

# Set up logging
BACKUP_LOG="${LOG_DIR}/02-backup-${BACKUP_TIMESTAMP}.log"
exec > >(tee -a "${BACKUP_LOG}") 2>&1

log_info "============================================================"
log_info "Ubuntu 24.04 → 25.10 Pre-Upgrade Backup Script"
log_info "Started: $(date)"
log_info "Backup directory: ${BACKUP_DIR}"
log_info "============================================================"
echo ""

# ============================================================================
# STEP 1: System Verification
# ============================================================================
log_step "Step 1: Verifying system prerequisites..."

# Verify Ubuntu version
if ! grep -q "VERSION_ID=\"24.04\"" /etc/os-release; then
    log_error "This script is for Ubuntu 24.04 only"
    log_error "Current version: $(lsb_release -rs)"
    exit 1
fi
log_info "✓ Ubuntu 24.04 detected"

# Verify ZFS pool exists and is healthy
if ! zpool list rpool &>/dev/null; then
    log_error "ZFS pool 'rpool' not found"
    exit 1
fi

POOL_HEALTH=$(zpool list -H -o health rpool)
if [[ "${POOL_HEALTH}" != "ONLINE" ]]; then
    log_error "ZFS pool health is ${POOL_HEALTH} (expected ONLINE)"
    log_error "Fix pool issues before upgrading"
    exit 1
fi
log_info "✓ ZFS pool rpool is ONLINE"

# Check disk space
AVAILABLE_GB=$(df --output=avail -BG / | tail -n1 | tr -d 'G')
if [[ ${AVAILABLE_GB} -lt 10 ]]; then
    log_error "Insufficient disk space: ${AVAILABLE_GB}GB available (need 10GB minimum)"
    exit 1
fi
log_info "✓ Sufficient disk space: ${AVAILABLE_GB}GB available"

# Check for broken packages
if dpkg --audit 2>&1 | grep -q "^The following packages"; then
    log_error "Broken packages detected. Run: sudo dpkg --audit"
    exit 1
fi
log_info "✓ No broken packages"

echo ""

# ============================================================================
# STEP 2: ZFS Snapshots
# ============================================================================
log_step "Step 2: Creating ZFS snapshots..."

# Function to create snapshot with error handling
create_snapshot() {
    local dataset=$1
    local snapshot_name="${dataset}@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}"

    if zfs list -H -o name "${snapshot_name}" &>/dev/null; then
        log_warn "Snapshot already exists: ${snapshot_name}"
        return 0
    fi

    if zfs snapshot "${snapshot_name}"; then
        log_info "✓ Created snapshot: ${snapshot_name}"
        return 0
    else
        log_error "Failed to create snapshot: ${snapshot_name}"
        return 1
    fi
}

# Get all ZFS datasets in rpool
mapfile -t DATASETS < <(zfs list -H -o name -r rpool | grep -v "^rpool$")

if [[ ${#DATASETS[@]} -eq 0 ]]; then
    log_error "No ZFS datasets found in rpool"
    exit 1
fi

log_info "Found ${#DATASETS[@]} datasets to snapshot"

# Create snapshots for all datasets
SNAPSHOT_COUNT=0
for dataset in "${DATASETS[@]}"; do
    if create_snapshot "${dataset}"; then
        ((SNAPSHOT_COUNT++))
    fi
done

log_info "✓ Created ${SNAPSHOT_COUNT} snapshots"

# List all snapshots created
echo ""
log_info "Snapshots created:"
zfs list -t snapshot | grep "${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}" || true

echo ""

# ============================================================================
# STEP 3: Configuration Backup
# ============================================================================
log_step "Step 3: Backing up configuration files..."

# Create configuration backup directory
CONFIG_BACKUP="${BACKUP_DIR}/config"
mkdir -p "${CONFIG_BACKUP}"

# Backup critical directories
BACKUP_DIRS=(
    "/etc"
    "/root"
    "/usr/local/bin"
    "/var/spool/cron"
)

for dir in "${BACKUP_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
        log_info "Backing up ${dir}..."
        rsync -aAX "${dir}/" "${CONFIG_BACKUP}${dir}/" 2>&1 | grep -v "some files/attrs were not transferred" || true
    fi
done

log_info "✓ Configuration files backed up to: ${CONFIG_BACKUP}"

echo ""

# ============================================================================
# STEP 4: Package List Export
# ============================================================================
log_step "Step 4: Exporting package lists..."

PACKAGE_BACKUP="${BACKUP_DIR}/packages"
mkdir -p "${PACKAGE_BACKUP}"

# Export installed packages
dpkg -l > "${PACKAGE_BACKUP}/dpkg-list.txt"
log_info "✓ dpkg package list: ${PACKAGE_BACKUP}/dpkg-list.txt"

# Export manually installed packages
apt-mark showmanual > "${PACKAGE_BACKUP}/apt-manual.txt"
log_info "✓ Manually installed packages: ${PACKAGE_BACKUP}/apt-manual.txt"

# Export held packages
apt-mark showhold > "${PACKAGE_BACKUP}/apt-hold.txt"
log_info "✓ Held packages: ${PACKAGE_BACKUP}/apt-hold.txt"

# Export PPA and repository list
grep -r --include '*.list' '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ > "${PACKAGE_BACKUP}/apt-sources.txt" 2>/dev/null || true
log_info "✓ APT sources: ${PACKAGE_BACKUP}/apt-sources.txt"

echo ""

# ============================================================================
# STEP 5: System State Documentation
# ============================================================================
log_step "Step 5: Documenting system state..."

STATE_DIR="${BACKUP_DIR}/system-state"
mkdir -p "${STATE_DIR}"

# ZFS state
zfs list -o name,used,avail,refer,mountpoint > "${STATE_DIR}/zfs-list.txt"
zpool status -v > "${STATE_DIR}/zpool-status.txt"
zpool get all rpool > "${STATE_DIR}/zpool-properties.txt"
zfs get all > "${STATE_DIR}/zfs-properties.txt"
log_info "✓ ZFS state documented"

# Block devices
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT > "${STATE_DIR}/block-devices.txt"
blkid > "${STATE_DIR}/blkid.txt"
log_info "✓ Block device info saved"

# Boot configuration
efibootmgr -v > "${STATE_DIR}/efi-boot-entries.txt" 2>/dev/null || echo "efibootmgr not available" > "${STATE_DIR}/efi-boot-entries.txt"
cp /boot/grub/grub.cfg "${STATE_DIR}/grub.cfg.backup" 2>/dev/null || true
cp /etc/default/grub "${STATE_DIR}/grub-default.backup" 2>/dev/null || true
log_info "✓ Boot configuration backed up"

# Kernel and initramfs
uname -a > "${STATE_DIR}/kernel-version.txt"
ls -lh /boot/initrd.img-* > "${STATE_DIR}/initramfs-list.txt" 2>/dev/null || true
lsinitramfs /boot/initrd.img-$(uname -r) > "${STATE_DIR}/initramfs-contents.txt" 2>/dev/null || true
log_info "✓ Kernel and initramfs info saved"

# Network configuration
cp -r /etc/netplan "${STATE_DIR}/netplan-backup/" 2>/dev/null || true
ip addr show > "${STATE_DIR}/ip-addresses.txt"
ip route show > "${STATE_DIR}/ip-routes.txt"
log_info "✓ Network configuration backed up"

# System services
systemctl list-unit-files --state=enabled > "${STATE_DIR}/enabled-services.txt"
systemctl list-units --failed > "${STATE_DIR}/failed-services.txt"
log_info "✓ System services documented"

# Disk usage
df -h > "${STATE_DIR}/disk-usage.txt"
du -sh /var/log /var/cache /tmp > "${STATE_DIR}/var-usage.txt" 2>/dev/null || true
log_info "✓ Disk usage documented"

echo ""

# ============================================================================
# STEP 6: Create Recovery Information
# ============================================================================
log_step "Step 6: Creating recovery information..."

RECOVERY_INFO="${BACKUP_DIR}/RECOVERY-INFO.txt"

cat > "${RECOVERY_INFO}" << EOF
================================================================================
UBUNTU 24.04 → 25.10 UPGRADE - RECOVERY INFORMATION
================================================================================

Backup Date: $(date)
Hostname: $(hostname)
Ubuntu Version: $(lsb_release -ds)
Kernel: $(uname -r)
ZFS Pool: rpool (${POOL_HEALTH})

================================================================================
ZFS SNAPSHOTS CREATED
================================================================================

$(zfs list -t snapshot | grep "${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}")

================================================================================
ROLLBACK PROCEDURE
================================================================================

If upgrade fails, you can restore from ZFS snapshots:

1. Boot into recovery/rescue mode or from Ubuntu Live USB

2. Import the ZFS pool:
   sudo zpool import -f rpool

3. Rollback to pre-upgrade snapshot:
   sudo zfs rollback rpool/root@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}

4. Restore other datasets if needed:
$(for dataset in "${DATASETS[@]}"; do echo "   sudo zfs rollback ${dataset}@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}"; done)

5. Reboot:
   sudo reboot

================================================================================
BOOT FROM SNAPSHOT (ALTERNATIVE METHOD)
================================================================================

If system still boots but you want to use the snapshot:

1. At GRUB menu, press 'e' to edit boot entry
2. Find the line starting with 'linux'
3. Change: root=ZFS=rpool/root
   To:     root=ZFS=rpool/root@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}
4. Press Ctrl+X to boot

5. If successful, clone the snapshot to make it permanent:
   sudo zfs clone rpool/root@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP} rpool/root-restored
   # Then set it as the bootfs and reboot

================================================================================
CONFIGURATION RESTORE
================================================================================

Configuration backup location: ${CONFIG_BACKUP}

To restore specific configurations:
   sudo rsync -aAX ${CONFIG_BACKUP}/etc/ /etc/
   sudo rsync -aAX ${CONFIG_BACKUP}/root/ /root/

================================================================================
PACKAGE RESTORE
================================================================================

Package lists saved in: ${PACKAGE_BACKUP}

To reinstall exact package set:
   sudo dpkg --set-selections < ${PACKAGE_BACKUP}/dpkg-list.txt
   sudo apt-get dselect-upgrade

================================================================================
EMERGENCY CONTACTS
================================================================================

- ZFS Root Mirror Script: https://github.com/csmarshall/ubuntu-zfs-mirror
- OpenZFS Docs: https://openzfs.github.io/openzfs-docs/
- Ubuntu Forums: https://ubuntuforums.org/
- Your Notes: _______________________________________________

================================================================================
EOF

log_info "✓ Recovery information: ${RECOVERY_INFO}"

echo ""

# ============================================================================
# STEP 7: Verification and Summary
# ============================================================================
log_step "Step 7: Verifying backups..."

# Verify snapshots exist
SNAPSHOT_COUNT=$(zfs list -t snapshot | grep -c "${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}" || echo "0")
if [[ ${SNAPSHOT_COUNT} -eq 0 ]]; then
    log_error "No snapshots found! Backup may have failed"
    exit 1
fi
log_info "✓ Verified ${SNAPSHOT_COUNT} snapshots"

# Verify backup directory
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
log_info "✓ Backup directory size: ${BACKUP_SIZE}"

# Calculate snapshot space usage
SNAPSHOT_SPACE=$(zfs list -t snapshot -o used -H | grep "${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}" | awk '{sum+=$1} END {print sum}' || echo "0")
log_info "✓ Snapshot space used: ${SNAPSHOT_SPACE}"

echo ""
log_info "============================================================"
log_info "BACKUP SUMMARY"
log_info "============================================================"
echo ""
log_info "Backup completed successfully!"
echo ""
log_info "📁 Backup Location: ${BACKUP_DIR}"
log_info "📸 Snapshots Created: ${SNAPSHOT_COUNT}"
log_info "💾 Backup Size: ${BACKUP_SIZE}"
log_info "📋 Recovery Info: ${RECOVERY_INFO}"
log_info "📝 Log File: ${BACKUP_LOG}"
echo ""
log_info "============================================================"
log_info "NEXT STEPS"
log_info "============================================================"
echo ""
echo "1. Review the recovery information:"
echo "   cat ${RECOVERY_INFO}"
echo ""
echo "2. Verify snapshots were created:"
echo "   zfs list -t snapshot | grep ${SNAPSHOT_PREFIX}"
echo ""
echo "3. Test snapshot rollback (OPTIONAL):"
echo "   sudo zfs rollback -n rpool/root@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}"
echo "   (The -n flag does a dry-run)"
echo ""
echo "4. If everything looks good, proceed with upgrade:"
echo "   sudo ./03-upgrade-execution.sh"
echo ""
log_warn "⚠️  Keep this backup until you've verified 25.10 is stable!"
log_warn "⚠️  Snapshots can be deleted later with:"
log_warn "    zfs destroy -r rpool@${SNAPSHOT_PREFIX}-${BACKUP_TIMESTAMP}"
echo ""

# Save backup metadata
cat > "${BACKUP_DIR}/.backup-metadata.sh" << EOF
#!/bin/bash
# Backup metadata - source this to restore environment variables
export BACKUP_TIMESTAMP="${BACKUP_TIMESTAMP}"
export BACKUP_DIR="${BACKUP_DIR}"
export SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX}"
export SNAPSHOT_COUNT="${SNAPSHOT_COUNT}"
EOF

chmod +x "${BACKUP_DIR}/.backup-metadata.sh"

log_info "Backup completed: $(date)"
log_info "============================================================"

exit 0
