# Ubuntu 24.04 (Noble) to 25.10 (Questing) Upgrade Guide for ZFS Root Mirror Systems

This guide provides a comprehensive, phase-by-phase upgrade path for Ubuntu systems with ZFS root mirrors installed via the [ubuntu-zfs-mirror](https://github.com/csmarshall/ubuntu-zfs-mirror) script.

## Overview

This upgrade transitions your system from:
- **Ubuntu 24.04 LTS (Noble Numbat)** → **Ubuntu 25.10 (Questing Quokka)**
- **initramfs-tools** → **dracut** (new initramfs generator)
- **Linux kernel 6.8** → **Linux kernel 6.17**
- **OpenZFS 2.2.2** → **OpenZFS 2.3.4**

### ⚠️ Two-Step Upgrade Process

**Important:** Ubuntu does not support skipping interim releases. The upgrade path is:

1. **Step 1:** Ubuntu 24.04 → Ubuntu 25.04 (Plucky Puffin)
2. **Step 2:** Ubuntu 25.04 → Ubuntu 25.10 (Questing Quokka)

**The upgrade script automatically detects this** and guides you through each step. After completing the first upgrade to 25.04 and rebooting, simply run the same script again to upgrade to 25.10.

**Why two steps?** Ubuntu 24.10 reached end-of-life in July 2025. The upgrade tool automatically skips EOL releases, jumping from 24.04 directly to 25.04, but cannot skip multiple releases to reach 25.10 in one step.

### 🚨 CRITICAL: HWE Kernel 6.14+ Required

**ZFS Upgrade Block:** Ubuntu blocked all ZFS upgrades to 25.04 due to a critical bug ([GitHub #17337](https://github.com/openzfs/zfs/issues/17337)) where systems would **freeze completely** when `update-grub` tried to list ZFS snapshots. This bug affects **older kernels only**.

**Solution:** The upgrade script uses `--proposed` to access a newer release upgrader that handles systems on HWE kernel 6.14+ correctly.

**⚠️ KERNEL REQUIREMENT:**

Check your kernel version **before** starting:
```bash
uname -r
```

- **✅ Safe to proceed:** `6.14.0-XX-generic` or newer (HWE kernel)
- **❌ DO NOT PROCEED:** `6.8.0-XX-generic` (standard kernel) - **HIGH RISK OF SYSTEM FREEZE**

**If you're on kernel 6.8:**
1. Upgrade to HWE kernel first: `sudo apt install linux-generic-hwe-24.04`
2. Reboot to new kernel
3. Verify with `uname -r` before proceeding

Or wait for Ubuntu 26.04 LTS (April 2026).

## Critical Considerations

### ⚠️ Important Warnings

1. **OpenZFS 2.3.4 + Kernel 6.17 Compatibility**
   - OpenZFS 2.3.4 officially supports kernel 6.16 maximum
   - Ubuntu 25.10 ships kernel 6.17 with patched OpenZFS (unverified)
   - This is experimental territory

2. **Dracut Encrypted ZFS Issues**
   - Known issues with encrypted ZFS root on dracut
   - This guide assumes **non-encrypted** ZFS root (as per original installer)

3. **Support Timeline**
   - Ubuntu 24.04 LTS: Supported until April 2029
   - Ubuntu 25.10: Supported until July 2026 (9 months only)
   - Ubuntu 26.04 LTS: April 2026 release (next LTS)

4. **One-Way Process**
   - Downgrades from 25.10 to 24.04 are **not supported**
   - Requires fresh installation to go back
   - Comprehensive backups are mandatory

### Why Upgrade to 25.10?

- Access to latest kernel 6.17 features and hardware support
- OpenZFS 2.3.4 with RAIDZ expansion and fast dedup
- Dracut for more modern boot infrastructure
- Practice run for Ubuntu 26.04 LTS migration

### Why Stay on 24.04 LTS?

- Long-term support until 2029
- Proven stability with initramfs-tools
- Well-tested OpenZFS 2.2.2 + kernel 6.8 combination
- No risk of experimental kernel/ZFS compatibility issues

## Upgrade Strategy

This upgrade follows a **phased, reversible approach** with validation at each step.

**Note:** The upgrade happens in **two sequential runs** of the upgrade script:
- **First run:** 24.04 → 25.04 (with reboot)
- **Second run:** 25.04 → 25.10 (with reboot)

The script automatically detects which step you're on and guides you appropriately.

### Phase 1: Pre-Upgrade Preparation
- System health verification
- ZFS pool scrub and snapshot
- Configuration backup
- Create recovery snapshots
- Document current system state

### Phase 2: System Upgrade Execution (24.04 → 25.04)
- Auto-detect current version and available upgrades
- Calculate full upgrade path to latest release
- Enable interim release upgrades
- Download and verify packages
- Perform distribution upgrade to 25.04
- Handle package conflicts
- Reboot to 25.04

### Phase 2b: System Upgrade Execution (25.04 → 25.10)
- Re-run same upgrade script after reboot
- Auto-detect you're on 25.04
- Upgrade to 25.10 (final step)
- Reboot to 25.10

### Phase 3: Post-Upgrade Dracut Migration
- Install dracut and zfs-dracut
- Remove initramfs-tools
- Update boot synchronization hooks
- Configure dracut for ZFS
- Regenerate initramfs with dracut

### Phase 4: Boot Configuration Optimization
- Verify GRUB configuration
- Test boot redundancy
- Optimize dracut modules
- Configure systemd boot integration

### Phase 5: Testing and Validation
- Boot test from both mirror drives
- Verify ZFS pool health
- Test kernel update triggers
- Validate boot synchronization
- Performance testing

### Phase 6: Cleanup and Hardening
- Remove obsolete packages
- Update documentation
- Configure monitoring
- Set up for 26.04 LTS migration path

## File Structure

```
ubuntu-noble-to-questing/
├── README.md                           # This file
├── 01-pre-upgrade-checklist.md         # Pre-upgrade requirements and checks
├── 02-pre-upgrade-backup.sh            # Automated backup script
├── 03-upgrade-execution.sh             # Main upgrade script
├── 04-post-upgrade-dracut.sh           # Dracut migration script
├── 05-boot-optimization.sh             # Boot configuration optimization
├── 06-testing-validation.sh            # Comprehensive testing script
├── 07-rollback-procedure.md            # Emergency rollback guide
├── 08-troubleshooting.md               # Common issues and solutions
├── 99-rollback-from-upgrade.sh         # Automated rollback script
└── logs/                               # Upgrade logs directory
```

## Quick Start

### Step 0: Review and Understand
```bash
# Read all documentation before starting
cd ~/work/personal/ubuntu-noble-to-questing
cat 01-pre-upgrade-checklist.md
cat 07-rollback-procedure.md
cat 08-troubleshooting.md
```

### Step 1: Pre-Upgrade Preparation
```bash
# Run pre-upgrade checks and backup
sudo ./02-pre-upgrade-backup.sh
```

### Step 2: Execute Upgrade to 25.04
```bash
# First upgrade: 24.04 → 25.04 (30-45 minutes)
# Script auto-detects you're on 24.04 and will upgrade to 25.04
sudo ./03-upgrade-execution.sh

# System will reboot to 25.04
```

### Step 3: Execute Upgrade to 25.10
```bash
# After reboot on 25.04, run the same script again
# Second upgrade: 25.04 → 25.10 (30-45 minutes)
# Script auto-detects you're on 25.04 and will upgrade to 25.10
sudo ./03-upgrade-execution.sh

# System will reboot to 25.10
```

### Step 4: Migrate to Dracut
```bash
# After reboot on 25.10, migrate initramfs to dracut
sudo ./04-post-upgrade-dracut.sh
```

### Step 5: Optimize Boot Configuration
```bash
# Optimize dracut and boot settings for 25.10
sudo ./05-boot-optimization.sh
```

### Step 6: Test and Validate
```bash
# Run comprehensive validation tests
sudo ./06-testing-validation.sh
```

## Prerequisites

- Ubuntu 24.04 LTS installed via ubuntu-zfs-mirror script
- ZFS root mirror on two drives (healthy ONLINE status)
- Minimum 10GB free space on root filesystem
- Stable internet connection
- Physical or remote console access (in case of boot issues)
- Recent ZFS snapshots (script creates them automatically)

## Time Estimates

| Phase | Estimated Time |
|-------|----------------|
| Pre-upgrade preparation | 30 minutes |
| **First upgrade** (24.04 → 25.04) | **45-60 minutes** |
| Reboot to 25.04 | 2-5 minutes |
| **Second upgrade** (25.04 → 25.10) | **45-60 minutes** |
| Reboot to 25.10 | 2-5 minutes |
| Dracut migration | 10-15 minutes |
| Boot optimization | 5-10 minutes |
| Testing and validation | 20-30 minutes |
| **Total** | **3-4 hours** |

**Note:** The upgrade happens in two sequential runs of the upgrade script with reboots in between.

## Support and Resources

- **Original ZFS Mirror Script**: https://github.com/csmarshall/ubuntu-zfs-mirror
- **OpenZFS Documentation**: https://openzfs.github.io/openzfs-docs/
- **Ubuntu Release Notes**: https://discourse.ubuntu.com/t/questing-quokka-release-notes/59220
- **Dracut ZFS Module**: https://manpages.ubuntu.com/manpages/questing/man7/dracut.zfs.7.html

## Success Criteria

After upgrade completion, your system should have:

- ✅ Ubuntu 25.10 (kernel 6.17)
- ✅ OpenZFS 2.3.4
- ✅ Dracut as initramfs generator
- ✅ ZFS pool healthy (no DEGRADED status)
- ✅ Both mirror drives bootable
- ✅ Boot synchronization hooks working
- ✅ All system services operational

## Recovery Plan

If the upgrade fails or you need to rollback:

### Automated Rollback (Recommended)

If the system can still boot:

```bash
sudo ./99-rollback-from-upgrade.sh
```

This script will:
- Auto-detect upgrade snapshots
- Create safety snapshots before rollback
- Rollback all ZFS datasets
- Regenerate initramfs and GRUB configuration
- Sync boot configuration to all mirror drives
- Safely reboot to Ubuntu 24.04

### Manual Rollback Methods

1. **During upgrade**: Press Ctrl+C and restore from ZFS snapshot
2. **After upgrade, system boots**: Use automated rollback script (99-rollback-from-upgrade.sh)
3. **System won't boot**: Boot from Live USB and manually rollback (see 07-rollback-procedure.md)

**Remember**: Always maintain bootable 24.04 LTS backups until confident in 25.10 stability.

## Path to Ubuntu 26.04 LTS

This upgrade serves as preparation for Ubuntu 26.04 LTS (April 2026):
- Dracut will be mature and stable
- OpenZFS will have full kernel compatibility
- All lessons learned from 25.10 will apply
- Upgrade from 25.10 → 26.04 will be supported and straightforward

## License

This upgrade guide is released under MIT License, consistent with the original ubuntu-zfs-mirror project.

## Author

Created as part of the ubuntu-zfs-mirror project evolution.
