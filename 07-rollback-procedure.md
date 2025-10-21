# Rollback Procedure for Ubuntu 25.10 → 24.04

This document provides detailed procedures for rolling back from Ubuntu 25.10 to Ubuntu 24.04 LTS if the upgrade encounters critical issues.

## ⚠️ Important Notes

1. **Ubuntu does not support downgrades via package manager**
2. **Rollback relies on ZFS snapshots created during upgrade process**
3. **The best rollback window is immediately after upgrade, before making significant changes**
4. **Complete rollback requires restoring from snapshot or fresh installation**

---

## Rollback Decision Matrix

### When to Rollback

Consider rollback if you encounter:

- ✗ System fails to boot after upgrade
- ✗ ZFS pool becomes DEGRADED or FAULTED post-upgrade
- ✗ Critical services fail to start (SSH, network, etc.)
- ✗ Kernel panics or system instability
- ✗ Data corruption or unexplained file system errors
- ✗ Unable to complete dracut migration successfully

### When NOT to Rollback

Minor issues that can be fixed:

- ⚠️ Single service configuration issue
- ⚠️ Network configuration needs adjustment
- ⚠️ Package conflicts that can be resolved
- ⚠️ Cosmetic or non-critical application issues

**Rule of Thumb**: If the system boots and ZFS is healthy, try fixing issues before rollback.

---

## Rollback Methods

There are three primary rollback methods, listed from easiest to most involved:

1. **Method 1**: ZFS Snapshot Rollback (System Bootable)
2. **Method 2**: ZFS Snapshot Rollback (System Non-Bootable, via Live USB)
3. **Method 3**: Fresh Installation of Ubuntu 24.04 LTS

---

## Method 1: ZFS Snapshot Rollback (System Bootable)

**Prerequisites**:
- System can boot (even if with issues)
- ZFS pool is accessible
- Snapshots exist from pre-upgrade backup

### Step 1: Identify Available Snapshots

```bash
# List all snapshots
sudo zfs list -t snapshot

# Look for snapshots with these patterns:
# - pre-questing-upgrade-YYYYMMDD-HHMMSS
# - before-upgrade-to-questing-YYYYMMDD-HHMMSS
# - before-dracut-migration-YYYYMMDD-HHMMSS
```

### Step 2: Verify Snapshot Integrity

```bash
# Check snapshot details
sudo zfs list -t snapshot -o name,used,referenced | grep "before-upgrade"

# Verify snapshot is complete
sudo zfs get all rpool/ROOT/ubuntu@SNAPSHOT_NAME
```

### Step 3: Create Emergency Snapshot (Optional but Recommended)

```bash
# Create snapshot of current state (in case rollback needs reversal)
sudo zfs snapshot -r rpool@emergency-before-rollback-$(date +%Y%m%d-%H%M%S)
```

### Step 4: Rollback Root Dataset

```bash
# WARNING: This will destroy all changes made after the snapshot
# Rollback root filesystem
sudo zfs rollback rpool/ROOT/ubuntu@SNAPSHOT_NAME

# Example:
# sudo zfs rollback rpool/ROOT/ubuntu@before-upgrade-to-questing-20250115-140530
```

### Step 5: Rollback Other Datasets

```bash
# List all datasets
zfs list -r rpool

# Rollback each dataset (adjust names as needed)
sudo zfs rollback rpool/ROOT/ubuntu/var@SNAPSHOT_NAME
sudo zfs rollback rpool/ROOT/ubuntu/srv@SNAPSHOT_NAME
# ... repeat for all datasets
```

Or rollback recursively (if snapshot name is consistent):

```bash
# Rollback all datasets recursively
# Note: Use with caution, cannot be undone without another snapshot
sudo zfs rollback -r rpool/ROOT/ubuntu@SNAPSHOT_NAME
```

### Step 6: Update Boot Configuration

```bash
# Regenerate initramfs (will use initramfs-tools from rolled-back system)
sudo update-initramfs -u -k all

# Update GRUB
sudo update-grub

# Sync to all mirror drives
sudo /usr/local/bin/sync-mirror-boot
```

### Step 7: Reboot

```bash
# Reboot to Ubuntu 24.04
sudo reboot
```

### Step 8: Verify Rollback Success

After reboot:

```bash
# Verify Ubuntu version
lsb_release -a
# Should show: Ubuntu 24.04.x LTS

# Check ZFS pool
sudo zpool status

# Check system services
systemctl --failed

# Verify initramfs-tools is back
dpkg -l | grep initramfs-tools
```

---

## Method 2: ZFS Snapshot Rollback (Non-Bootable System)

**Prerequisites**:
- Ubuntu Live USB (24.04 or later)
- Access to system console (physical or remote)
- ZFS snapshots exist

### Step 1: Boot from Ubuntu Live USB

1. Insert Ubuntu Live USB
2. Boot system and select "Try Ubuntu" (not "Install")
3. Wait for live environment to load

### Step 2: Install ZFS Support in Live Environment

```bash
# Update package lists
sudo apt update

# Install ZFS utilities
sudo apt install -y zfsutils-linux

# Load ZFS kernel module
sudo modprobe zfs
```

### Step 3: Import ZFS Pool

```bash
# List available pools
sudo zpool import

# Import rpool (use -f to force if necessary)
sudo zpool import -f rpool

# Verify pool is imported
sudo zpool status rpool
```

### Step 4: List Available Snapshots

```bash
# List all snapshots
sudo zfs list -t snapshot -r rpool

# Look for pre-upgrade snapshots
sudo zfs list -t snapshot | grep "before-upgrade"
```

### Step 5: Rollback to Snapshot

```bash
# Rollback root filesystem
sudo zfs rollback rpool/ROOT/ubuntu@SNAPSHOT_NAME

# If rolling back multiple datasets, do each one:
sudo zfs rollback rpool/ROOT/ubuntu/var@SNAPSHOT_NAME

# Or rollback recursively
sudo zfs rollback -r rpool/ROOT/ubuntu@SNAPSHOT_NAME
```

### Step 6: Mount Rolled-Back System

```bash
# Create mount point
sudo mkdir -p /mnt

# Mount root filesystem
sudo zfs set mountpoint=/mnt rpool/ROOT/ubuntu
sudo zfs mount rpool/ROOT/ubuntu

# Mount boot partition
sudo mount /dev/disk/by-label/EFI /mnt/boot/efi
```

### Step 7: Chroot and Reinstall Bootloader

```bash
# Bind mount system directories
for dir in dev proc sys run; do
    sudo mount --bind /$dir /mnt/$dir
done

# Chroot into system
sudo chroot /mnt

# Reinstall GRUB on both mirror drives
# (Find drive paths first)
zpool status rpool

# Install GRUB (example for two drives)
grub-install /dev/disk/by-id/DRIVE1
grub-install /dev/disk/by-id/DRIVE2

# Update GRUB configuration
update-grub

# Update initramfs
update-initramfs -u -k all

# Exit chroot
exit
```

### Step 8: Unmount and Export Pool

```bash
# Unmount everything
for dir in run sys proc dev; do
    sudo umount /mnt/$dir
done

sudo umount /mnt/boot/efi
sudo zfs unmount rpool/ROOT/ubuntu

# Export pool
sudo zpool export rpool
```

### Step 9: Reboot

```bash
# Remove Live USB
# Reboot system
sudo reboot
```

---

## Method 3: Fresh Installation of Ubuntu 24.04 LTS

If snapshot rollback is not possible or successful, perform a fresh installation.

### Prerequisites

- Ubuntu 24.04 LTS Live USB
- Backup of critical data (external drive or zfs send/receive)
- Original ZFS mirror installation script

### Data Backup (Before Wipe)

If possible, boot from Live USB and backup data:

```bash
# Boot Live USB
sudo apt update
sudo apt install -y zfsutils-linux
sudo modprobe zfs

# Import pool (read-only)
sudo zpool import -o readonly=on rpool

# Option 1: Backup via zfs send
sudo zfs send rpool/ROOT/ubuntu@latest | gzip > /media/backup/ubuntu-backup.zfs.gz

# Option 2: Backup via rsync
sudo mkdir /mnt/rpool
sudo zfs set mountpoint=/mnt/rpool rpool/ROOT/ubuntu
sudo zfs mount rpool/ROOT/ubuntu
rsync -aAXv /mnt/rpool/ /media/backup/ubuntu-files/

# Backup home directories and /etc
rsync -aAXv /mnt/rpool/home/ /media/backup/home/
rsync -aAXv /mnt/rpool/etc/ /media/backup/etc/

# Export pool
sudo zpool export rpool
```

### Fresh Installation

1. Boot from Ubuntu 24.04 LTS Live USB
2. Follow original installation procedure
3. Use the `ubuntu-zfs-mirror` installation script
4. Restore data from backups after installation

---

## Emergency Boot Options

If system won't boot normally, try these recovery methods:

### Boot from Older Kernel

1. Reboot and press `Shift` or `Esc` during boot to show GRUB menu
2. Select "Advanced options for Ubuntu"
3. Choose an older kernel (Ubuntu 24.04 kernel is 6.8.x)
4. If system boots, use Method 1 for rollback

### Boot from Snapshot Directly

1. At GRUB menu, press `e` to edit boot entry
2. Find line starting with `linux` (kernel line)
3. Change `root=ZFS=rpool/ROOT/ubuntu` to `root=ZFS=rpool/ROOT/ubuntu@SNAPSHOT_NAME`
4. Press `Ctrl+X` to boot

Example:
```
Before: root=ZFS=rpool/ROOT/ubuntu
After:  root=ZFS=rpool/ROOT/ubuntu@before-upgrade-to-questing-20250115-140530
```

If successful:
5. System boots from snapshot (read-only by default)
6. Clone snapshot to make it permanent:
```bash
sudo zfs clone rpool/ROOT/ubuntu@SNAPSHOT_NAME rpool/ROOT/ubuntu-restored
sudo zfs set bootfs=rpool/ROOT/ubuntu-restored rpool
sudo reboot
```

---

## Post-Rollback Cleanup

After successful rollback to Ubuntu 24.04:

### 1. Verify System Integrity

```bash
# Check Ubuntu version
lsb_release -a

# Verify ZFS pool
sudo zpool status
sudo zpool scrub rpool

# Check for errors
dpkg --audit
apt-get check

# Verify critical services
systemctl --failed
```

### 2. Remove 25.10 Snapshots (Optional)

After verifying 24.04 is stable:

```bash
# List 25.10-related snapshots
sudo zfs list -t snapshot | grep "before-upgrade\|emergency"

# Remove snapshots (careful!)
sudo zfs destroy rpool/ROOT/ubuntu@SNAPSHOT_NAME
```

### 3. Update System

```bash
# Update Ubuntu 24.04
sudo apt update
sudo apt upgrade -y

# Regenerate initramfs
sudo update-initramfs -u -k all

# Update GRUB
sudo update-grub
```

### 4. Verify Boot Redundancy

```bash
# Sync boot to all mirrors
sudo /usr/local/bin/sync-mirror-boot

# Verify EFI entries
sudo efibootmgr
```

---

## Troubleshooting Rollback Issues

### Issue: "Cannot rollback, dataset has been modified"

**Cause**: Changes were made after snapshot

**Solution**:
```bash
# Create new snapshot of current state
sudo zfs snapshot rpool/ROOT/ubuntu@current-state

# Force rollback (destroys current state)
sudo zfs rollback -r rpool/ROOT/ubuntu@SNAPSHOT_NAME
```

### Issue: "Pool cannot be imported"

**Cause**: Pool cache or hostid mismatch

**Solution**:
```bash
# Force import
sudo zpool import -f rpool

# If still fails, try by pool ID
sudo zpool import -f POOL_ID rpool
```

### Issue: "Boot fails after rollback"

**Cause**: Bootloader not properly restored

**Solution**:
1. Boot from Live USB
2. Follow Method 2, Step 7 (Reinstall bootloader)
3. Ensure both mirror drives have GRUB installed

---

## Prevention for Future Upgrades

Lessons learned from this rollback:

1. **Always create snapshots before major changes**
   ```bash
   sudo zfs snapshot -r rpool@before-$(date +%Y%m%d-%H%M%S)
   ```

2. **Test in VM first** if possible

3. **Keep Ubuntu 24.04 LTS** until Ubuntu 26.04 LTS is available
   - 24.04 LTS is supported until 2029
   - 25.10 is only supported until July 2026

4. **Have recovery USB ready** before starting upgrade

5. **Document system state** before upgrade

---

## Support Resources

- **Ubuntu Forums**: https://ubuntuforums.org/
- **OpenZFS Docs**: https://openzfs.github.io/openzfs-docs/
- **ZFS on Linux**: https://github.com/openzfs/zfs
- **Ubuntu ZFS Root Mirror**: https://github.com/csmarshall/ubuntu-zfs-mirror

---

## Conclusion

Rolling back from Ubuntu 25.10 to 24.04 is possible thanks to ZFS snapshots, but requires careful execution. Always prefer fixing issues over rollback when possible, but don't hesitate to rollback if system stability is compromised.

**Remember**: Ubuntu 24.04 LTS is a solid, well-tested release with long-term support. Staying on 24.04 until 26.04 LTS is released is a perfectly valid strategy.
