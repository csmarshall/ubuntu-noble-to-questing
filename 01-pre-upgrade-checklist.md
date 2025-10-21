# Pre-Upgrade Checklist for Ubuntu 24.04 → 25.10

## Critical Requirements

Before proceeding with the upgrade, verify ALL items in this checklist.

### System Health Requirements

#### ✅ ZFS Pool Health
```bash
# Check pool status - must show ONLINE for all drives
sudo zpool status rpool

# Expected output:
#   state: ONLINE
#   scan: scrub repaired 0B in XX:XX:XX with 0 errors
#   config:
#     rpool        ONLINE       0     0     0
#       mirror-0   ONLINE       0     0     0
#         disk1    ONLINE       0     0     0
#         disk2    ONLINE       0     0     0
```

**Requirements**:
- [ ] Pool state: ONLINE (not DEGRADED, FAULTED, or UNAVAIL)
- [ ] No checksum errors
- [ ] No read/write errors
- [ ] Recent scrub completed successfully (within last 7 days)
- [ ] Both mirror drives showing ONLINE

#### ✅ Disk Space
```bash
# Check available space on rpool
df -h /

# Check ZFS pool capacity
zpool list rpool
```

**Requirements**:
- [ ] At least 10GB free space on root filesystem
- [ ] Pool capacity less than 80%
- [ ] No datasets at 100% quota

#### ✅ System Uptime and Stability
```bash
# Check system uptime
uptime

# Check for kernel panics
sudo journalctl -k | grep -i panic

# Check for failed services
systemctl --failed
```

**Requirements**:
- [ ] System running stable for at least 24 hours
- [ ] No kernel panics in recent history
- [ ] No failed critical services
- [ ] No pending reboots required (check /var/run/reboot-required)

#### ✅ Current Ubuntu Version
```bash
# Verify you're on Ubuntu 24.04
lsb_release -a

# Expected output:
#   Distributor ID: Ubuntu
#   Description:    Ubuntu 24.04.x LTS
#   Release:        24.04
#   Codename:       noble
```

**Requirements**:
- [ ] Running Ubuntu 24.04 LTS (Noble Numbat)
- [ ] All 24.04 updates installed (`sudo apt update && sudo apt upgrade`)
- [ ] No held packages (`dpkg --get-selections | grep hold`)

### Boot Configuration Verification

#### ✅ GRUB and Boot Redundancy
```bash
# Check GRUB is installed on both drives
sudo grub-install --version

# List EFI boot entries
sudo efibootmgr -v

# Check for sync-mirror-boot script
ls -lh /usr/local/bin/sync-mirror-boot
ls -lh /usr/local/bin/sync-grub-to-mirror-drives
```

**Requirements**:
- [ ] GRUB installed and working
- [ ] Three EFI boot entries (Ubuntu - Rotating, Ubuntu - Drive1, Ubuntu - Drive2)
- [ ] sync-mirror-boot script exists and is executable
- [ ] sync-grub-to-mirror-drives script exists and is executable

#### ✅ Kernel and Initramfs
```bash
# Check current kernel
uname -r

# Verify initramfs exists
ls -lh /boot/initrd.img-$(uname -r)

# Check initramfs was built with initramfs-tools
lsinitramfs /boot/initrd.img-$(uname -r) | grep -i zfs | head -5
```

**Requirements**:
- [ ] Kernel version 6.8.x (Ubuntu 24.04 kernel)
- [ ] Initramfs exists for current kernel
- [ ] initramfs-tools is installed (`dpkg -l | grep initramfs-tools`)
- [ ] zfs-initramfs is installed (`dpkg -l | grep zfs-initramfs`)

### Network and Connectivity

#### ✅ Network Configuration
```bash
# Check network connectivity
ping -c 4 8.8.8.8

# Check DNS resolution
nslookup archive.ubuntu.com

# Check access to Ubuntu repos
curl -I http://archive.ubuntu.com/ubuntu/dists/noble/Release
```

**Requirements**:
- [ ] Network connectivity working
- [ ] DNS resolution working
- [ ] Can reach Ubuntu package repositories
- [ ] Stable internet connection (not cellular/metered)

#### ✅ SSH Access (if remote system)
```bash
# Check SSH service
sudo systemctl status ssh

# Verify SSH access from another machine
# (test from your workstation)
```

**Requirements**:
- [ ] SSH service running
- [ ] Can login via SSH
- [ ] SSH keys configured (not just password auth)
- [ ] Have out-of-band access (IPMI, console, etc.) in case SSH fails

### Backup Requirements

#### ✅ ZFS Snapshots
```bash
# List existing snapshots
sudo zfs list -t snapshot

# Check snapshot creation works
sudo zfs snapshot rpool/ROOT/ubuntu@pre-upgrade-test
sudo zfs list -t snapshot | grep pre-upgrade-test
sudo zfs destroy rpool/ROOT/ubuntu@pre-upgrade-test
```

**Requirements**:
- [ ] ZFS snapshot creation works
- [ ] Enough space for new snapshots (at least 5GB free)
- [ ] Previous snapshots are manageable (not consuming excessive space)

#### ✅ External Backup (Strongly Recommended)
```bash
# Send ZFS filesystem to external backup
sudo zfs send rpool/ROOT/ubuntu@backup | ssh backup-server "zfs receive tank/backups/ubuntu-noble-$(date +%F)"

# OR: Use rsync to backup important data
sudo rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /mnt/external-backup/
```

**Requirements**:
- [ ] Recent backup of critical data (within last 7 days)
- [ ] Backup stored on separate physical device/system
- [ ] Backup verified and restorable
- [ ] Configuration files backed up (`/etc`, `/home`)

### Package and Repository Status

#### ✅ Package Manager Health
```bash
# Check for broken packages
sudo dpkg --audit

# Check for packages in half-installed state
dpkg -l | grep ^iU

# Check for unmet dependencies
sudo apt-get check

# List manually held packages
apt-mark showhold
```

**Requirements**:
- [ ] No broken packages
- [ ] No half-installed packages
- [ ] No unmet dependencies
- [ ] No manually held packages (or document why they're held)

#### ✅ Third-Party Repositories
```bash
# List all repositories
grep -r --include '*.list' '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/

# Check for PPA repositories
ls -lh /etc/apt/sources.list.d/
```

**Requirements**:
- [ ] Document all third-party repositories
- [ ] Plan to disable PPAs before upgrade (re-enable after)
- [ ] No repositories causing conflicts

### Custom Configuration Review

#### ✅ Kernel Parameters
```bash
# Check custom kernel parameters
cat /proc/cmdline

# Check GRUB customizations
grep -v '^#' /etc/default/grub | grep -v '^$'
```

**Requirements**:
- [ ] Document any custom kernel parameters
- [ ] Verify they're compatible with kernel 6.17
- [ ] No zfs_force=1 (should only appear on first boot, then be removed)

#### ✅ Boot Synchronization Hooks
```bash
# Check kernel hooks
ls -lh /etc/kernel/postinst.d/zz-sync-mirror-boot
ls -lh /etc/kernel/postrm.d/zz-sync-mirror-boot

# Check initramfs hooks (initramfs-tools specific)
ls -lh /etc/initramfs/post-update.d/zz-sync-mirror-boot

# Check GRUB hooks
ls -lh /etc/grub.d/99-zfs-mirror-sync
```

**Requirements**:
- [ ] All hooks are symlinks to /usr/local/bin/sync-mirror-boot
- [ ] sync-mirror-boot script is executable
- [ ] Hooks have `zz-` prefix (run last)

### System Services and Daemons

#### ✅ Critical Services Status
```bash
# Check ZFS services
sudo systemctl status zfs-import-cache.service
sudo systemctl status zfs-import-scan.service
sudo systemctl status zfs-mount.service
sudo systemctl status zfs.target

# Check any custom services
sudo systemctl list-unit-files --state=enabled | grep -v '^UNIT'
```

**Requirements**:
- [ ] All ZFS services enabled and working
- [ ] Document any custom systemd services
- [ ] No services in failed state

### Documentation and Planning

#### ✅ System Documentation
```bash
# Create system state snapshot
sudo zfs list -o name,used,avail,refer,mountpoint > ~/pre-upgrade-zfs-state.txt
sudo zpool status -v > ~/pre-upgrade-pool-status.txt
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT > ~/pre-upgrade-block-devices.txt
dpkg -l > ~/pre-upgrade-package-list.txt
```

**Requirements**:
- [ ] System state documented
- [ ] Know how to access console (physical or remote)
- [ ] Have phone number for datacenter/hosting provider (if applicable)
- [ ] Maintenance window scheduled (2-3 hours)

#### ✅ Rollback Plan Reviewed
```bash
# Review rollback procedure
cat 07-rollback-procedure.md
```

**Requirements**:
- [ ] Read and understand rollback procedure
- [ ] Know how to boot from ZFS snapshot
- [ ] Know how to restore from external backup
- [ ] Have verified recovery USB/ISO available

### Final Pre-Flight Check

#### ✅ Mental Preparation
**Requirements**:
- [ ] Read entire upgrade guide
- [ ] Read troubleshooting guide (08-troubleshooting.md)
- [ ] Understand this is a one-way upgrade (no downgrade path)
- [ ] Have 2-3 hours of uninterrupted time
- [ ] Not under time pressure
- [ ] Have tested in VM first (optional but recommended)

#### ✅ Communication
**Requirements**:
- [ ] Informed stakeholders of maintenance window
- [ ] Have backup communication channel (phone, chat)
- [ ] Know who to contact if problems arise

## Pre-Upgrade Commands Summary

Run these commands to verify system readiness:

```bash
#!/bin/bash
# Quick pre-upgrade verification script

echo "=== System Version ==="
lsb_release -a
echo ""

echo "=== ZFS Pool Status ==="
sudo zpool status rpool
echo ""

echo "=== Disk Space ==="
df -h /
sudo zpool list rpool
echo ""

echo "=== Kernel Version ==="
uname -r
echo ""

echo "=== Package Manager Health ==="
sudo dpkg --audit
sudo apt-get check
echo ""

echo "=== Boot Configuration ==="
ls -lh /usr/local/bin/sync-mirror-boot
ls -lh /etc/kernel/postinst.d/zz-sync-mirror-boot
echo ""

echo "=== EFI Boot Entries ==="
sudo efibootmgr -v
echo ""

echo "=== Network Connectivity ==="
ping -c 2 8.8.8.8
echo ""

echo "If all checks pass, proceed with: sudo ./02-pre-upgrade-backup.sh"
```

## Next Steps

Once ALL checklist items are verified:

1. Run pre-upgrade backup script: `sudo ./02-pre-upgrade-backup.sh`
2. Review backup logs and verify snapshots created
3. Proceed to upgrade execution: `sudo ./03-upgrade-execution.sh`

## Abort Conditions

**DO NOT PROCEED** if any of the following are true:

- ❌ ZFS pool is DEGRADED or FAULTED
- ❌ Less than 10GB free disk space
- ❌ Failed system services
- ❌ Cannot reach Ubuntu package repositories
- ❌ No recent backups
- ❌ Under time pressure or lacking console access
- ❌ Haven't read rollback procedure

**Remember**: Ubuntu 24.04 LTS is supported until 2029. There's no rush to upgrade unless you specifically need features from 25.10.
