#!/bin/bash
#
# Ubuntu 24.04 → 25.10 Upgrade Execution Script
#
# This script performs the distribution upgrade from Noble to Questing.
# It follows Ubuntu's official upgrade process with additional safety checks
# for ZFS root mirror systems.
#
# PREREQUISITES:
# - Run 02-pre-upgrade-backup.sh first
# - Review 01-pre-upgrade-checklist.md
# - Ensure stable internet connection
# - Have console access available
#
# USAGE: sudo ./03-upgrade-execution.sh
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

# Configuration
UPGRADE_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$(dirname "$(readlink -f "$0")")/logs"
mkdir -p "${LOG_DIR}"

# Set up logging
UPGRADE_LOG="${LOG_DIR}/03-upgrade-${UPGRADE_TIMESTAMP}.log"
exec > >(tee -a "${UPGRADE_LOG}") 2>&1

# Detect current version
CURRENT_VERSION=$(lsb_release -rs)
CURRENT_CODENAME=$(lsb_release -cs)

log_info "Detecting available Ubuntu releases..."

# Query what upgrade is available
AVAILABLE_UPGRADE=$(do-release-upgrade --check-dist-upgrade-only 2>&1 | grep "New release" | grep -oP "'\K[0-9.]+(?=')" || echo "")

if [[ -z "${AVAILABLE_UPGRADE}" ]]; then
    log_error "No upgrade available from ${CURRENT_VERSION}"
    log_error "You may already be on the latest release or upgrade path is unavailable"
    exit 1
fi

TARGET_VERSION="${AVAILABLE_UPGRADE}"

# Get codename for target version
case "${TARGET_VERSION}" in
    "25.04") TARGET_CODENAME="plucky" ;;
    "25.10") TARGET_CODENAME="questing" ;;
    "26.04") TARGET_CODENAME="zesty" ;;  # Example - actual codename TBD
    *) TARGET_CODENAME="unknown" ;;
esac

SNAPSHOT_SUFFIX="before-upgrade-to-${TARGET_CODENAME}"

# Determine if more upgrades will be needed
log_info "Checking full upgrade path to latest stable release..."
# Get latest non-LTS release from Ubuntu releases
LATEST_RELEASE=$(curl -s http://releases.ubuntu.com/ | grep -o 'href="[0-9]\{2\}\.[0-9]\{2\}/"' | grep -oP '\K[0-9.]+(?=/)' | sort -V | tail -1 || echo "")

if [[ -n "${LATEST_RELEASE}" ]] && [[ "${TARGET_VERSION}" != "${LATEST_RELEASE}" ]]; then
    UPGRADE_STEP="Step 1 of multiple"
    NEXT_STEP_MSG="After this upgrade to ${TARGET_VERSION} completes, you'll need to upgrade again to reach ${LATEST_RELEASE}"
    FULL_PATH="${CURRENT_VERSION} → ${TARGET_VERSION} → ... → ${LATEST_RELEASE}"
else
    UPGRADE_STEP="Final step"
    NEXT_STEP_MSG="This upgrade will bring you to the latest stable release"
    FULL_PATH="${CURRENT_VERSION} → ${TARGET_VERSION} (latest)"
fi

log_info "============================================================"
log_info "Ubuntu Distribution Upgrade Script (${UPGRADE_STEP})"
log_info "Current: ${CURRENT_VERSION} (${CURRENT_CODENAME})"
log_info "Target:  ${TARGET_VERSION} (${TARGET_CODENAME})"
log_info "Full upgrade path: ${FULL_PATH}"
log_info "Started: $(date)"
log_info "============================================================"
echo ""
log_info "${NEXT_STEP_MSG}"
echo ""

# ============================================================================
# Kernel Version Check (Critical for ZFS systems)
# ============================================================================
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo "${KERNEL_VERSION}" | cut -d. -f1)
KERNEL_MINOR=$(echo "${KERNEL_VERSION}" | cut -d. -f2)

log_info "Checking kernel version for ZFS upgrade compatibility..."
log_info "Current kernel: ${KERNEL_VERSION}"

# Check if kernel is 6.14 or newer
if [[ "${KERNEL_MAJOR}" -lt 6 ]] || [[ "${KERNEL_MAJOR}" -eq 6 && "${KERNEL_MINOR}" -lt 14 ]]; then
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                      🚨 CRITICAL WARNING 🚨                     ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  KERNEL TOO OLD FOR ZFS UPGRADE!                              ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  Your kernel: ${KERNEL_VERSION}                                        ║${NC}"
    echo -e "${RED}║  Required: 6.14.0 or newer (HWE kernel)                       ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  Ubuntu 25.04 has a bug that causes SYSTEM FREEZE during      ║${NC}"
    echo -e "${RED}║  upgrade on older kernels with ZFS root.                      ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  GitHub Issue: openzfs/zfs#17337                              ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_error "To proceed, upgrade to HWE kernel first:"
    log_error "  sudo apt install linux-generic-hwe-24.04"
    log_error "  sudo reboot"
    log_error "Then re-run this script after booting to 6.14+"
    echo ""
    exit 1
else
    log_info "✓ Kernel ${KERNEL_VERSION} is compatible (6.14+)"
fi

echo ""

# ============================================================================
# Safety Confirmation
# ============================================================================

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                         ⚠️  WARNING ⚠️                          ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  This will upgrade: ${CURRENT_VERSION} → ${TARGET_VERSION}                                  ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  • This is a ONE-WAY process (no downgrade path)              ║${NC}"
echo -e "${RED}║  • ${TARGET_VERSION} is an interim release (9 month support)            ║${NC}"
echo -e "${RED}║  • Requires 30-60 minutes and stable internet                 ║${NC}"
echo -e "${RED}║  • System will REBOOT after upgrade                           ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_warn "Before proceeding, ensure you have:"
echo "  ✓ Run 02-pre-upgrade-backup.sh"
echo "  ✓ ZFS snapshots created"
echo "  ✓ External backups if desired"
echo "  ✓ Console access available"
echo "  ✓ Read 07-rollback-procedure.md"
echo ""

read -p "Have you completed all pre-upgrade steps? (type 'yes' to continue): " confirm
if [[ "${confirm}" != "yes" ]]; then
    log_error "Upgrade aborted by user"
    exit 1
fi

echo ""
read -p "Type the hostname '$(hostname)' to confirm upgrade: " hostname_confirm
if [[ "${hostname_confirm}" != "$(hostname)" ]]; then
    log_error "Hostname confirmation failed. Upgrade aborted."
    exit 1
fi

echo ""
log_info "User confirmed. Proceeding with upgrade..."
echo ""

# ============================================================================
# STEP 1: Pre-Upgrade Verification
# ============================================================================
log_step "Step 1: Verifying system prerequisites..."

# Verify Ubuntu version
if ! grep -q "VERSION_ID=\"24.04\"" /etc/os-release; then
    log_error "This script is for Ubuntu 24.04 only"
    log_error "Current version: $(lsb_release -rs)"
    exit 1
fi
log_info "✓ Ubuntu 24.04 detected: $(lsb_release -ds)"

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

# Check disk space
AVAILABLE_GB=$(df --output=avail -BG / | tail -n1 | tr -d 'G')
if [[ ${AVAILABLE_GB} -lt 10 ]]; then
    log_error "Insufficient disk space: ${AVAILABLE_GB}GB (need 10GB minimum)"
    exit 1
fi
log_info "✓ Disk space: ${AVAILABLE_GB}GB available"

# Check network connectivity
if ! ping -c 2 archive.ubuntu.com &>/dev/null; then
    log_error "Cannot reach archive.ubuntu.com - check network connection"
    exit 1
fi
log_info "✓ Network connectivity to Ubuntu archives"

# Check for broken packages
if dpkg --audit 2>&1 | grep -q "^The following packages"; then
    log_error "Broken packages detected"
    dpkg --audit
    exit 1
fi
log_info "✓ No broken packages"

# Verify recent snapshots exist
RECENT_SNAPSHOTS=$(zfs list -t snapshot -H | grep -c "$(date +%Y%m%d)" || echo "0")
if [[ ${RECENT_SNAPSHOTS} -eq 0 ]]; then
    log_warn "No snapshots created today. Did you run 02-pre-upgrade-backup.sh?"
    read -p "Continue anyway? (type 'yes'): " snapshot_confirm
    if [[ "${snapshot_confirm}" != "yes" ]]; then
        log_error "Upgrade aborted - create snapshots first"
        exit 1
    fi
else
    log_info "✓ Found ${RECENT_SNAPSHOTS} snapshots created today"
fi

echo ""

# ============================================================================
# STEP 2: System Preparation
# ============================================================================
log_step "Step 2: Preparing system for upgrade..."

# Update package lists and upgrade current system
log_info "Updating package lists..."
apt-get update

log_info "Upgrading packages on current release (24.04)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log_info "Performing full upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y

log_info "Removing unnecessary packages..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

log_info "✓ System updated on 24.04"

echo ""

# ============================================================================
# STEP 3: Disable Third-Party Repositories
# ============================================================================
log_step "Step 3: Disabling third-party repositories..."

# Backup sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.backup-${UPGRADE_TIMESTAMP}
log_info "✓ Backed up /etc/apt/sources.list"

# Disable PPAs and third-party repos
if ls /etc/apt/sources.list.d/*.list &>/dev/null; then
    log_info "Disabling third-party repositories..."
    mkdir -p /etc/apt/sources.list.d.disabled-${UPGRADE_TIMESTAMP}
    mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d.disabled-${UPGRADE_TIMESTAMP}/ 2>/dev/null || true
    log_info "✓ Third-party repos moved to: /etc/apt/sources.list.d.disabled-${UPGRADE_TIMESTAMP}/"
else
    log_info "✓ No third-party repositories to disable"
fi

echo ""

# ============================================================================
# STEP 4: Enable Interim Release Upgrades
# ============================================================================
log_step "Step 4: Configuring release upgrade settings..."

# Backup update-manager configuration
if [[ -f /etc/update-manager/release-upgrades ]]; then
    cp /etc/update-manager/release-upgrades /etc/update-manager/release-upgrades.backup-${UPGRADE_TIMESTAMP}
    log_info "✓ Backed up release-upgrades configuration"
fi

# Set to allow interim releases
if [[ -f /etc/update-manager/release-upgrades ]]; then
    sed -i 's/^Prompt=.*/Prompt=normal/' /etc/update-manager/release-upgrades
    log_info "✓ Set Prompt=normal in /etc/update-manager/release-upgrades"
else
    log_warn "release-upgrades file not found, creating it..."
    mkdir -p /etc/update-manager
    cat > /etc/update-manager/release-upgrades << 'EOF'
[DEFAULT]
Prompt=normal
EOF
    log_info "✓ Created /etc/update-manager/release-upgrades with Prompt=normal"
fi

echo ""

# ============================================================================
# STEP 5: Create Pre-Upgrade Snapshot
# ============================================================================
log_step "Step 5: Creating final pre-upgrade snapshot..."

FINAL_SNAPSHOT="rpool/root@${SNAPSHOT_SUFFIX}-${UPGRADE_TIMESTAMP}"
if zfs snapshot "${FINAL_SNAPSHOT}"; then
    log_info "✓ Created snapshot: ${FINAL_SNAPSHOT}"
else
    log_error "Failed to create pre-upgrade snapshot"
    exit 1
fi

# Snapshot all datasets
DATASETS=$(zfs list -H -o name -r rpool | grep -v "^rpool$" || true)
for dataset in ${DATASETS}; do
    zfs snapshot "${dataset}@${SNAPSHOT_SUFFIX}-${UPGRADE_TIMESTAMP}" 2>/dev/null || true
done

log_info "✓ All datasets snapshotted"

echo ""

# ============================================================================
# STEP 6: Distribution Upgrade Execution
# ============================================================================
log_step "Step 6: Executing distribution upgrade to ${TARGET_VERSION}..."

log_warn "This step will take 30-60 minutes depending on internet speed"
log_warn "DO NOT interrupt the process once it starts"
echo ""

sleep 3

# Install update-manager-core if not present
if ! dpkg -l | grep -q "^ii.*update-manager-core"; then
    log_info "Installing update-manager-core..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y update-manager-core
fi

# Ensure Prompt=normal is set (in case user chose package maintainer's version)
log_info "Ensuring Prompt=normal for interim release upgrade..."
sed -i 's/^Prompt=.*/Prompt=normal/' /etc/update-manager/release-upgrades
log_info "✓ Set Prompt=normal in /etc/update-manager/release-upgrades"

log_info "Starting do-release-upgrade..."
echo ""
echo "============================================================"
echo "IMPORTANT: During the upgrade you will be prompted:"
echo ""
echo "  - /etc/update-manager/release-upgrades conflict:"
echo "    Choose [Y]es (install maintainer's version)"
echo "    Script will re-configure it automatically after"
echo ""
echo "  - Other config file conflicts:"
echo "    Generally choose [N]o to keep your customizations"
echo ""
echo "  - Restart services: Choose [Yes]"
echo "  - Remove obsolete packages: Choose [Yes]"
echo "  - Reboot: Choose [Yes] or let this script handle it"
echo "============================================================"
echo ""

sleep 5

# Run the upgrade
# Note: Do NOT use -d flag (that targets development releases)
# With Prompt=normal, this will upgrade to next available interim release
# Using --proposed to get newer release upgrader
# Running in INTERACTIVE mode because non-interactive mode blocks ZFS systems
# even though HWE kernel 6.14+ doesn't have the freeze bug
if do-release-upgrade --proposed; then
    log_info "✓ Distribution upgrade to ${TARGET_VERSION} completed successfully"
    log_info "${NEXT_STEP_MSG}"
else
    UPGRADE_EXIT_CODE=$?
    log_error "Distribution upgrade failed with exit code: ${UPGRADE_EXIT_CODE}"
    log_error "Check logs at: ${UPGRADE_LOG}"
    log_error "You may need to fix issues and re-run, or restore from snapshot"
    exit ${UPGRADE_EXIT_CODE}
fi

echo ""

# ============================================================================
# STEP 7: Post-Upgrade Verification (if not rebooted)
# ============================================================================
# Note: do-release-upgrade typically reboots automatically
# This section runs if we somehow didn't reboot

if grep -q "VERSION_ID=\"${TARGET_VERSION}\"" /etc/os-release 2>/dev/null; then
    log_step "Step 7: Post-upgrade verification..."

    log_info "Upgrade to Ubuntu ${TARGET_VERSION} successful!"
    log_info "Current version: $(lsb_release -ds)"

    # Check ZFS pool after upgrade
    if zpool list rpool &>/dev/null; then
        log_info "✓ ZFS pool still accessible"
    else
        log_warn "ZFS pool not accessible after upgrade - may need reboot"
    fi

    # Check kernel version
    log_info "Current kernel: $(uname -r)"

    echo ""
    log_info "============================================================"
    log_info "${UPGRADE_STEP} COMPLETE"
    log_info "============================================================"
    echo ""

    if [[ "${TARGET_VERSION}" == "25.04" ]]; then
        log_warn "⚠️  After reboot, run this script again to complete upgrade to 25.10"
        log_warn "    sudo ./03-upgrade-execution.sh"
    fi
    log_info "The distribution upgrade is complete, but the system needs"
    log_info "to be rebooted and dracut migration must be performed."
    echo ""
    log_warn "Next steps after reboot:"
    echo "  1. Verify system boots successfully on 25.10"
    echo "  2. Run: sudo ./04-post-upgrade-dracut.sh"
    echo "  3. Continue with testing and validation"
    echo ""

    read -p "Reboot now? (yes/no): " reboot_confirm
    if [[ "${reboot_confirm}" == "yes" ]]; then
        log_info "Rebooting in 10 seconds..."
        log_info "After reboot, run: sudo ./04-post-upgrade-dracut.sh"
        sleep 10
        reboot
    else
        log_warn "Please reboot manually when ready"
        log_warn "After reboot, run: sudo ./04-post-upgrade-dracut.sh"
    fi
else
    log_warn "System appears to still be on 24.04 after upgrade attempt"
    log_warn "This may indicate upgrade was interrupted or needs reboot"
    log_warn "Check: ${UPGRADE_LOG}"
fi

log_info "Upgrade execution script completed: $(date)"
log_info "============================================================"

exit 0
