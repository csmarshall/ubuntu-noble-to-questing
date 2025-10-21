# Ubuntu 24.04 (Noble) to 25.10 (Questing) Upgrade Guide for ZFS Root Mirror Systems

This guide provides a comprehensive, phase-by-phase upgrade path for Ubuntu systems with ZFS root mirrors installed via the [ubuntu-zfs-mirror](https://github.com/csmarshall/ubuntu-zfs-mirror) script.

## Overview

This upgrade transitions your system from:
- **Ubuntu 24.04 LTS (Noble Numbat)** → **Ubuntu 25.10 (Questing Quokka)**
- **initramfs-tools** → **dracut** (new initramfs generator)
- **Linux kernel 6.8** → **Linux kernel 6.17**
- **OpenZFS 2.2.2** → **OpenZFS 2.3.4**

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

This upgrade follows a **phased, reversible approach** with validation at each step:

### Phase 1: Pre-Upgrade Preparation
- System health verification
- ZFS pool scrub and snapshot
- Configuration backup
- Create recovery snapshots
- Document current system state

### Phase 2: System Upgrade Execution
- Enable interim release upgrades
- Download and verify packages
- Perform distribution upgrade
- Handle package conflicts

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

### Step 2: Execute Upgrade
```bash
# This will take 30-60 minutes depending on connection speed
sudo ./03-upgrade-execution.sh
```

### Step 3: Migrate to Dracut
```bash
# After reboot on 25.10, migrate initramfs to dracut
sudo ./04-post-upgrade-dracut.sh
```

### Step 4: Optimize Boot Configuration
```bash
# Optimize dracut and boot settings for 25.10
sudo ./05-boot-optimization.sh
```

### Step 5: Test and Validate
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
| Download packages | 15-30 minutes (depends on connection) |
| Upgrade execution | 30-45 minutes |
| Dracut migration | 10-15 minutes |
| Boot optimization | 5-10 minutes |
| Testing and validation | 20-30 minutes |
| **Total** | **2-3 hours** |

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

If the upgrade fails:

1. **During upgrade**: Press Ctrl+C and restore from ZFS snapshot
2. **After upgrade, before dracut migration**: Downgrade packages (see rollback guide)
3. **After dracut migration**: Restore from ZFS snapshot and fresh install 24.04

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
