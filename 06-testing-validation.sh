#!/bin/bash
#
# Comprehensive Testing and Validation Script for Ubuntu 25.10 Upgrade
#
# This script performs extensive testing to verify that the upgrade from
# Ubuntu 24.04 to 25.10 was successful and all ZFS root mirror functionality
# is working correctly with dracut.
#
# PREREQUISITES:
# - System upgraded to Ubuntu 25.10
# - Dracut migration completed
# - Boot optimization completed
# - System rebooted successfully
#
# USAGE: sudo ./06-testing-validation.sh
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

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

test_pass() {
    echo -e "${GREEN}  ✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}  ✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

test_warn() {
    echo -e "${YELLOW}  ⚠ WARN${NC}: $1"
    ((TESTS_WARNED++))
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Configuration
VALIDATION_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$(dirname "$(readlink -f "$0")")/logs"
mkdir -p "${LOG_DIR}"

# Set up logging
VALIDATION_LOG="${LOG_DIR}/06-validation-${VALIDATION_TIMESTAMP}.log"
exec > >(tee -a "${VALIDATION_LOG}") 2>&1

log_info "============================================================"
log_info "Ubuntu 25.10 Upgrade Validation and Testing Script"
log_info "Started: $(date)"
log_info "============================================================"
echo ""

# ============================================================================
# TEST SUITE 1: System Version and Components
# ============================================================================
log_step "Test Suite 1: System Version and Components"
echo ""

log_test "1.1: Ubuntu version"
if grep -q "VERSION_ID=\"25.10\"" /etc/os-release; then
    VERSION=$(lsb_release -ds)
    test_pass "Ubuntu 25.10 detected: ${VERSION}"
else
    test_fail "Not running Ubuntu 25.10"
fi

log_test "1.2: Kernel version"
KERNEL_VERSION=$(uname -r)
if [[ "${KERNEL_VERSION}" =~ ^6\.17 ]]; then
    test_pass "Kernel 6.17 detected: ${KERNEL_VERSION}"
else
    test_warn "Expected kernel 6.17, got: ${KERNEL_VERSION}"
fi

log_test "1.3: Dracut installation"
if command -v dracut &>/dev/null; then
    DRACUT_VERSION=$(dracut --version 2>&1 | head -1 || echo "unknown")
    test_pass "Dracut installed: ${DRACUT_VERSION}"
else
    test_fail "Dracut not installed"
fi

log_test "1.4: ZFS-dracut module"
if dpkg -l | grep -q "^ii.*zfs-dracut"; then
    ZFS_DRACUT_VERSION=$(dpkg -l | grep zfs-dracut | awk '{print $3}')
    test_pass "zfs-dracut installed: ${ZFS_DRACUT_VERSION}"
else
    test_fail "zfs-dracut not installed"
fi

log_test "1.5: initramfs-tools removed"
if dpkg -l | grep -q "^ii.*initramfs-tools"; then
    test_warn "initramfs-tools still installed (optional)"
else
    test_pass "initramfs-tools removed"
fi

log_test "1.6: OpenZFS version"
if command -v zfs &>/dev/null; then
    ZFS_VERSION=$(zfs version 2>&1 | grep "zfs-" | head -1 || echo "unknown")
    test_pass "OpenZFS installed: ${ZFS_VERSION}"
else
    test_fail "ZFS not available"
fi

echo ""

# ============================================================================
# TEST SUITE 2: ZFS Pool Health
# ============================================================================
log_step "Test Suite 2: ZFS Pool Health and Status"
echo ""

log_test "2.1: ZFS pool exists"
if zpool list rpool &>/dev/null; then
    test_pass "ZFS pool 'rpool' exists"
else
    test_fail "ZFS pool 'rpool' not found"
fi

log_test "2.2: Pool health status"
POOL_HEALTH=$(zpool list -H -o health rpool 2>/dev/null || echo "UNKNOWN")
if [[ "${POOL_HEALTH}" == "ONLINE" ]]; then
    test_pass "Pool health: ONLINE"
elif [[ "${POOL_HEALTH}" == "DEGRADED" ]]; then
    test_warn "Pool health: DEGRADED (one drive may have failed)"
else
    test_fail "Pool health: ${POOL_HEALTH}"
fi

log_test "2.3: Pool mirror status"
MIRROR_COUNT=$(zpool status rpool | grep -c "mirror-" || echo "0")
if [[ ${MIRROR_COUNT} -ge 1 ]]; then
    test_pass "Mirror configuration detected (${MIRROR_COUNT} mirror vdev)"
else
    test_fail "No mirror configuration found"
fi

log_test "2.4: Drive status"
ONLINE_DRIVES=$(zpool status rpool | grep -c "ONLINE" || echo "0")
if [[ ${ONLINE_DRIVES} -ge 3 ]]; then
    # 3+ means: pool + mirror + 2 drives
    test_pass "All drives ONLINE (${ONLINE_DRIVES} devices)"
else
    test_warn "Expected 3+ ONLINE devices, found: ${ONLINE_DRIVES}"
fi

log_test "2.5: Pool errors"
READ_ERRORS=$(zpool status rpool | grep "errors:" | awk '{print $2}' || echo "0")
if [[ "${READ_ERRORS}" == "No" ]] || [[ "${READ_ERRORS}" == "0" ]]; then
    test_pass "No pool errors"
else
    test_warn "Pool errors detected: ${READ_ERRORS}"
fi

log_test "2.6: Pool capacity"
POOL_CAPACITY=$(zpool list -H -o capacity rpool | tr -d '%')
if [[ ${POOL_CAPACITY} -lt 80 ]]; then
    test_pass "Pool capacity: ${POOL_CAPACITY}%"
elif [[ ${POOL_CAPACITY} -lt 90 ]]; then
    test_warn "Pool capacity: ${POOL_CAPACITY}% (getting full)"
else
    test_warn "Pool capacity: ${POOL_CAPACITY}% (critically full)"
fi

echo ""

# ============================================================================
# TEST SUITE 3: Boot Configuration
# ============================================================================
log_step "Test Suite 3: Boot Configuration and Initramfs"
echo ""

log_test "3.1: Current initramfs exists"
CURRENT_KERNEL=$(uname -r)
if [[ -f "/boot/initrd.img-${CURRENT_KERNEL}" ]]; then
    INITRD_SIZE=$(du -h "/boot/initrd.img-${CURRENT_KERNEL}" | cut -f1)
    test_pass "Initramfs exists for ${CURRENT_KERNEL} (${INITRD_SIZE})"
else
    test_fail "Initramfs missing for ${CURRENT_KERNEL}"
fi

log_test "3.2: Initramfs built with dracut"
if lsinitrd "/boot/initrd.img-${CURRENT_KERNEL}" &>/dev/null; then
    if lsinitrd "/boot/initrd.img-${CURRENT_KERNEL}" 2>/dev/null | head -20 | grep -q "dracut"; then
        test_pass "Initramfs built with dracut"
    else
        test_warn "Could not verify dracut in initramfs"
    fi
else
    test_fail "Cannot inspect initramfs with lsinitrd"
fi

log_test "3.3: Dracut ZFS module present"
if lsinitrd "/boot/initrd.img-${CURRENT_KERNEL}" 2>/dev/null | grep -q "zfs"; then
    test_pass "ZFS modules present in initramfs"
else
    test_warn "Could not verify ZFS in initramfs"
fi

log_test "3.4: GRUB configuration"
if [[ -f /boot/grub/grub.cfg ]]; then
    test_pass "GRUB configuration exists"
else
    test_fail "GRUB configuration missing"
fi

log_test "3.5: No zfs_force in GRUB (after first boot)"
if grep -q "zfs_force=1" /boot/grub/grub.cfg 2>/dev/null; then
    test_warn "zfs_force=1 found in GRUB (should only be on first boot)"
else
    test_pass "No zfs_force=1 in GRUB configuration"
fi

log_test "3.6: EFI boot entries"
if command -v efibootmgr &>/dev/null; then
    BOOT_ENTRIES=$(efibootmgr | grep -c "Ubuntu" || echo "0")
    if [[ ${BOOT_ENTRIES} -ge 3 ]]; then
        test_pass "Found ${BOOT_ENTRIES} Ubuntu boot entries (expected 3)"
    elif [[ ${BOOT_ENTRIES} -ge 1 ]]; then
        test_warn "Found ${BOOT_ENTRIES} Ubuntu boot entries (expected 3)"
    else
        test_fail "No Ubuntu boot entries found"
    fi
else
    test_warn "efibootmgr not available"
fi

echo ""

# ============================================================================
# TEST SUITE 4: Boot Synchronization Hooks
# ============================================================================
log_step "Test Suite 4: Boot Synchronization Hooks"
echo ""

log_test "4.1: sync-mirror-boot script exists"
if [[ -x /usr/local/bin/sync-mirror-boot ]]; then
    test_pass "sync-mirror-boot script exists and is executable"
else
    test_fail "sync-mirror-boot script missing or not executable"
fi

log_test "4.2: sync-grub-to-mirror-drives script exists"
if [[ -x /usr/local/bin/sync-grub-to-mirror-drives ]]; then
    test_pass "sync-grub-to-mirror-drives script exists and is executable"
else
    test_fail "sync-grub-to-mirror-drives script missing or not executable"
fi

log_test "4.3: Kernel postinst hook"
if [[ -L /etc/kernel/postinst.d/zz-sync-mirror-boot ]]; then
    TARGET=$(readlink -f /etc/kernel/postinst.d/zz-sync-mirror-boot)
    if [[ "${TARGET}" == "/usr/local/bin/sync-mirror-boot" ]]; then
        test_pass "Kernel postinst hook correctly configured"
    else
        test_warn "Kernel postinst hook points to: ${TARGET}"
    fi
else
    test_fail "Kernel postinst hook missing"
fi

log_test "4.4: Kernel postrm hook"
if [[ -L /etc/kernel/postrm.d/zz-sync-mirror-boot ]]; then
    test_pass "Kernel postrm hook exists"
else
    test_fail "Kernel postrm hook missing"
fi

log_test "4.5: initramfs-tools post-update hook (should be removed)"
if [[ -e /etc/initramfs/post-update.d/zz-sync-mirror-boot ]]; then
    test_warn "initramfs-tools hook still present (no longer needed with dracut)"
else
    test_pass "initramfs-tools post-update hook removed (correct for dracut)"
fi

log_test "4.6: GRUB hook"
if [[ -x /etc/grub.d/99-zfs-mirror-sync ]]; then
    test_pass "GRUB sync hook exists"
else
    test_warn "GRUB sync hook missing or not executable"
fi

log_test "4.7: Shutdown sync service"
if systemctl is-enabled zfs-mirror-shutdown-sync.service &>/dev/null; then
    test_pass "Shutdown sync service enabled"
else
    test_warn "Shutdown sync service not enabled"
fi

echo ""

# ============================================================================
# TEST SUITE 5: System Services
# ============================================================================
log_step "Test Suite 5: System Services"
echo ""

ZFS_SERVICES=(
    "zfs-import-cache.service"
    "zfs-import.target"
    "zfs-mount.service"
    "zfs.target"
)

SERVICE_NUM=1
for service in "${ZFS_SERVICES[@]}"; do
    log_test "5.${SERVICE_NUM}: ${service}"
    if systemctl is-active "${service}" &>/dev/null; then
        test_pass "${service} is active"
    else
        test_warn "${service} not active"
    fi
    ((SERVICE_NUM++))
done

log_test "5.${SERVICE_NUM}: SSH service"
if systemctl is-active ssh.service &>/dev/null; then
    test_pass "SSH service is active"
else
    test_warn "SSH service not active"
fi

echo ""

# ============================================================================
# TEST SUITE 6: Kernel and Boot Parameters
# ============================================================================
log_step "Test Suite 6: Kernel and Boot Parameters"
echo ""

log_test "6.1: Root filesystem type"
CMDLINE=$(cat /proc/cmdline)
if echo "${CMDLINE}" | grep -q "root=ZFS="; then
    test_pass "Root filesystem specified as ZFS"
elif echo "${CMDLINE}" | grep -q "root=zfs:"; then
    test_pass "Root filesystem specified as ZFS (alternate format)"
else
    test_warn "Root filesystem type unclear in kernel cmdline"
fi

log_test "6.2: Root filesystem mounted"
ROOT_FS=$(df / | tail -1 | awk '{print $1}')
if echo "${ROOT_FS}" | grep -q "rpool"; then
    test_pass "Root filesystem is on rpool: ${ROOT_FS}"
else
    test_warn "Root filesystem: ${ROOT_FS} (expected rpool)"
fi

log_test "6.3: Root filesystem type (mount)"
ROOT_TYPE=$(df -T / | tail -1 | awk '{print $2}')
if [[ "${ROOT_TYPE}" == "zfs" ]]; then
    test_pass "Root filesystem type: zfs"
else
    test_fail "Root filesystem type: ${ROOT_TYPE} (expected zfs)"
fi

echo ""

# ============================================================================
# TEST SUITE 7: Performance and Functionality
# ============================================================================
log_step "Test Suite 7: Performance and Functionality Tests"
echo ""

log_test "7.1: Boot time analysis"
if command -v systemd-analyze &>/dev/null; then
    BOOT_TIME=$(systemd-analyze 2>/dev/null | grep "Startup finished" | grep -oP '\d+\.\d+s \(kernel\).*' || echo "unknown")
    if [[ "${BOOT_TIME}" != "unknown" ]]; then
        test_pass "Boot time: ${BOOT_TIME}"
    else
        test_warn "Could not determine boot time"
    fi
else
    test_warn "systemd-analyze not available"
fi

log_test "7.2: ZFS pool read performance"
TEST_FILE="/tmp/zfs-read-test-$$"
if dd if=/dev/zero of="${TEST_FILE}" bs=1M count=100 &>/dev/null; then
    if dd if="${TEST_FILE}" of=/dev/null bs=1M &>/dev/null 2>&1; then
        test_pass "ZFS read operations working"
    else
        test_fail "ZFS read test failed"
    fi
    rm -f "${TEST_FILE}"
else
    test_warn "Could not create test file"
fi

log_test "7.3: ZFS snapshot creation"
TEST_SNAPSHOT="rpool/root@validation-test-${VALIDATION_TIMESTAMP}"
if zfs snapshot "${TEST_SNAPSHOT}"; then
    test_pass "ZFS snapshot creation successful"
    # Clean up test snapshot
    zfs destroy "${TEST_SNAPSHOT}" &>/dev/null || true
else
    test_fail "ZFS snapshot creation failed"
fi

log_test "7.4: Package manager functionality"
if apt-get update &>/dev/null; then
    test_pass "APT package manager working"
else
    test_fail "APT package manager has issues"
fi

echo ""

# ============================================================================
# TEST SUITE 8: Security and Configuration
# ============================================================================
log_step "Test Suite 8: Security and Configuration"
echo ""

log_test "8.1: Root account locked"
if passwd -S root | grep -q "L"; then
    test_pass "Root account is locked"
else
    test_warn "Root account not locked"
fi

log_test "8.2: Firewall status"
if command -v ufw &>/dev/null; then
    if ufw status | grep -q "Status: active"; then
        test_pass "UFW firewall is active"
    else
        test_warn "UFW firewall not active"
    fi
else
    test_warn "UFW not installed"
fi

log_test "8.3: AppArmor status"
if command -v aa-status &>/dev/null; then
    if aa-status 2>/dev/null | grep -q "apparmor module is loaded"; then
        test_pass "AppArmor is loaded"
    else
        test_warn "AppArmor not loaded"
    fi
else
    test_warn "AppArmor not available"
fi

echo ""

# ============================================================================
# TEST SUITE 9: Dracut Configuration
# ============================================================================
log_step "Test Suite 9: Dracut Configuration"
echo ""

log_test "9.1: Dracut ZFS configuration exists"
if [[ -f /etc/dracut.conf.d/zfs.conf ]]; then
    test_pass "/etc/dracut.conf.d/zfs.conf exists"
else
    test_warn "ZFS dracut configuration missing"
fi

log_test "9.2: Dracut optimization configuration"
if [[ -f /etc/dracut.conf.d/90-zfs-optimization.conf ]]; then
    test_pass "Dracut optimization configuration exists"
else
    test_warn "Dracut optimization configuration missing"
fi

log_test "9.3: Dracut can list modules"
if dracut --list-modules 2>/dev/null | grep -q "zfs"; then
    test_pass "Dracut ZFS module available"
else
    test_fail "Dracut ZFS module not available"
fi

echo ""

# ============================================================================
# TEST SUITE 10: Mirror Drive Status
# ============================================================================
log_step "Test Suite 10: Mirror Drive Status and Boot Redundancy"
echo ""

log_test "10.1: Identify mirror drives"
RPOOL_DRIVES=$(zpool status rpool 2>/dev/null | grep -E "^\s+.*-part3\s+ONLINE" | awk '{print $1}' | sed 's/-part3$//' | sed 's|^|/dev/disk/by-id/|' || true)
DRIVE_COUNT=$(echo "${RPOOL_DRIVES}" | wc -l)

if [[ ${DRIVE_COUNT} -eq 2 ]]; then
    test_pass "Found 2 mirror drives"
else
    test_warn "Expected 2 mirror drives, found: ${DRIVE_COUNT}"
fi

log_test "10.2: EFI partitions on both drives"
EFI_COUNT=$(blkid | grep -c "TYPE=\"vfat\"" || echo "0")
if [[ ${EFI_COUNT} -ge 2 ]]; then
    test_pass "Found ${EFI_COUNT} EFI partitions"
else
    test_warn "Expected 2+ EFI partitions, found: ${EFI_COUNT}"
fi

log_test "10.3: GRUB installed on all drives"
# This is a best-effort check
if [[ -d /boot/efi/EFI ]] && ls /boot/efi/EFI/ | grep -q "Ubuntu-"; then
    UBUNTU_EFI_DIRS=$(ls /boot/efi/EFI/ | grep -c "Ubuntu-" || echo "0")
    test_pass "Found ${UBUNTU_EFI_DIRS} Ubuntu EFI directories"
else
    test_warn "Could not verify GRUB installation on all drives"
fi

echo ""

# ============================================================================
# FINAL REPORT
# ============================================================================

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED))

log_info "============================================================"
log_info "VALIDATION TEST RESULTS"
log_info "============================================================"
echo ""
log_info "Total Tests: ${TOTAL_TESTS}"
log_info "  ${GREEN}✓ Passed: ${TESTS_PASSED}${NC}"
log_info "  ${RED}✗ Failed: ${TESTS_FAILED}${NC}"
log_info "  ${YELLOW}⚠ Warnings: ${TESTS_WARNED}${NC}"
echo ""

# Determine overall status
if [[ ${TESTS_FAILED} -eq 0 ]]; then
    if [[ ${TESTS_WARNED} -eq 0 ]]; then
        log_info "Overall Status: ${GREEN}EXCELLENT${NC}"
        log_info "All tests passed! Upgrade is fully successful."
    else
        log_info "Overall Status: ${GREEN}GOOD${NC}"
        log_info "All critical tests passed. Some warnings present (review recommended)."
    fi
else
    if [[ ${TESTS_FAILED} -le 2 ]]; then
        log_info "Overall Status: ${YELLOW}MARGINAL${NC}"
        log_warn "Some tests failed. Review failures and consider remediation."
    else
        log_info "Overall Status: ${RED}POOR${NC}"
        log_error "Multiple test failures. System may not be fully functional."
    fi
fi

echo ""
log_info "Log file: ${VALIDATION_LOG}"
echo ""

# Generate detailed report
REPORT_FILE="/root/upgrade-validation-report-${VALIDATION_TIMESTAMP}.txt"

cat > "${REPORT_FILE}" << EOF
================================================================================
UBUNTU 25.10 UPGRADE VALIDATION REPORT
================================================================================

Test Date: $(date)
Hostname: $(hostname)
Ubuntu Version: $(lsb_release -ds)
Kernel: $(uname -r)
ZFS Version: $(zfs version 2>&1 | head -1)

================================================================================
TEST SUMMARY
================================================================================

Total Tests: ${TOTAL_TESTS}
Passed: ${TESTS_PASSED}
Failed: ${TESTS_FAILED}
Warnings: ${TESTS_WARNED}

Overall Status: $(if [[ ${TESTS_FAILED} -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi)

================================================================================
ZFS POOL STATUS
================================================================================

$(zpool status rpool)

================================================================================
ZFS DATASET LIST
================================================================================

$(zfs list)

================================================================================
SYSTEM INFORMATION
================================================================================

Uptime: $(uptime)
Memory: $(free -h | grep "Mem:" || echo "N/A")
Disk Usage: $(df -h / | tail -1)
Boot Time: $(systemd-analyze 2>/dev/null || echo "N/A")

================================================================================
KERNEL PARAMETERS
================================================================================

$(cat /proc/cmdline)

================================================================================
EFI BOOT ENTRIES
================================================================================

$(efibootmgr 2>/dev/null || echo "efibootmgr not available")

================================================================================
DRACUT CONFIGURATION
================================================================================

$(ls -lh /etc/dracut.conf.d/)

$(if [[ -f /etc/dracut.conf.d/zfs.conf ]]; then
    echo "=== zfs.conf ==="
    cat /etc/dracut.conf.d/zfs.conf
fi)

$(if [[ -f /etc/dracut.conf.d/90-zfs-optimization.conf ]]; then
    echo ""
    echo "=== 90-zfs-optimization.conf ==="
    cat /etc/dracut.conf.d/90-zfs-optimization.conf
fi)

================================================================================
RECOMMENDATIONS
================================================================================

$(if [[ ${TESTS_FAILED} -eq 0 ]] && [[ ${TESTS_WARNED} -eq 0 ]]; then
    echo "✓ Upgrade completed successfully with no issues"
    echo "✓ System is fully operational on Ubuntu 25.10"
    echo "✓ All ZFS root mirror functionality working correctly"
    echo "✓ Dracut migration successful"
    echo ""
    echo "Next steps:"
    echo "  - Monitor system for 24-48 hours"
    echo "  - Test kernel updates when available"
    echo "  - Plan for Ubuntu 26.04 LTS upgrade in April 2026"
elif [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo "✓ Upgrade mostly successful with minor warnings"
    echo "⚠ Review warnings in validation log"
    echo ""
    echo "Recommended actions:"
    echo "  - Review warning items in detail"
    echo "  - Monitor system stability"
    echo "  - Consider addressing non-critical warnings"
else
    echo "✗ Upgrade completed with test failures"
    echo "⚠ System may not be fully functional"
    echo ""
    echo "Required actions:"
    echo "  - Review failed tests immediately"
    echo "  - Consult 08-troubleshooting.md"
    echo "  - Consider rollback if critical failures persist"
    echo "  - Contact support if needed"
fi)

================================================================================
FULL TEST LOG
================================================================================

See: ${VALIDATION_LOG}

================================================================================
EOF

log_info "Detailed report: ${REPORT_FILE}"
echo ""

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    log_warn "Some tests failed. Review the log and consider consulting:"
    echo "  - 08-troubleshooting.md for common issues"
    echo "  - 07-rollback-procedure.md if problems persist"
    echo ""
fi

log_info "Validation completed: $(date)"
log_info "============================================================"

# Exit with appropriate status
if [[ ${TESTS_FAILED} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
