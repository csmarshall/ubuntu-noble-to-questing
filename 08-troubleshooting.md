# Troubleshooting Guide for Ubuntu 24.04 → 25.10 Upgrade

This guide covers common issues encountered during the upgrade from Ubuntu 24.04 to 25.10 with ZFS root mirror and dracut migration.

---

## Table of Contents

1. [Pre-Upgrade Issues](#pre-upgrade-issues)
2. [Upgrade Execution Issues](#upgrade-execution-issues)
3. [Post-Upgrade Boot Issues](#post-upgrade-boot-issues)
4. [Dracut Migration Issues](#dracut-migration-issues)
5. [ZFS Pool Issues](#zfs-pool-issues)
6. [Boot Mirror Synchronization Issues](#boot-mirror-synchronization-issues)
7. [Kernel and Initramfs Issues](#kernel-and-initramfs-issues)
8. [Network and Service Issues](#network-and-service-issues)
9. [Performance Issues](#performance-issues)
10. [Recovery Procedures](#recovery-procedures)

---

## Pre-Upgrade Issues

### Issue: Insufficient Disk Space

**Symptoms**:
- `df -h /` shows less than 10GB free
- Backup script fails with "No space left on device"

**Solutions**:

1. Clean package cache:
```bash
sudo apt clean
sudo apt autoclean
```

2. Remove old kernels (keep current and one previous):
```bash
# List installed kernels
dpkg -l | grep linux-image

# Remove old kernels (NOT the current one!)
sudo apt remove linux-image-X.X.X-XX-generic
sudo apt autoremove
```

3. Clean ZFS snapshots:
```bash
# List snapshots and their size
sudo zfs list -t snapshot -o name,used

# Remove old snapshots
sudo zfs destroy rpool/root@old-snapshot-name
```

4. Clean system logs:
```bash
sudo journalctl --vacuum-time=7d
sudo rm /var/log/*.gz
```

---

### Issue: ZFS Pool in DEGRADED State

**Symptoms**:
- `zpool status` shows DEGRADED
- One drive showing OFFLINE or FAULTED

**Solutions**:

1. Check drive status:
```bash
sudo zpool status -v rpool
```

2. If drive is temporarily offline, try online-ing it:
```bash
sudo zpool online rpool /dev/disk/by-id/DRIVE_ID
```

3. If drive has failed, replace it BEFORE upgrading:
```bash
# Replace failed drive
sudo zpool replace rpool /dev/disk/by-id/OLD_DRIVE /dev/disk/by-id/NEW_DRIVE

# Wait for resilver to complete
sudo zpool status -v rpool
```

**Do NOT upgrade with DEGRADED pool**. Fix pool health first.

---

### Issue: Held Packages Blocking Upgrade

**Symptoms**:
- `apt-mark showhold` shows held packages
- Pre-upgrade script warns about held packages

**Solutions**:

```bash
# List held packages
apt-mark showhold

# Unhold packages
sudo apt-mark unhold PACKAGE_NAME

# Or unhold all
sudo apt-mark unhold $(apt-mark showhold)
```

---

## Configuration File Conflicts During Upgrade

During the upgrade, you'll be prompted about configuration file conflicts. Here's what to choose:

### Files to KEEP (Choose N - Keep your current version):

- **`/etc/default/grub`** - Contains ZFS-specific boot parameters configured by ubuntu-zfs-mirror
- **`/etc/netplan/*`** - Your network configuration (unless you want DHCP reset)
- **`/usr/local/bin/*`** - Custom scripts (like sync-mirror-boot)
- **`/etc/fstab`** - ZFS mount points (though ZFS usually doesn't use fstab)
- **`/etc/ssh/sshd_config`** - Your SSH customizations
- **Any files you've customized** - If you recognize it and customized it, keep it

### Files to REPLACE (Choose Y - Install package maintainer's version):

- **`/etc/update-manager/release-upgrades`** - The script re-configures this anyway
- **System service files** you haven't modified
- **Default configs** you haven't customized

### When In Doubt:

1. Choose **`D`** to see the differences
2. If the diff shows settings you added/changed, choose **`N`** (keep yours)
3. If the diff shows only package maintainer changes, choose **`Y`** (use new)

---

## Upgrade Execution Issues

### Issue: Script Shows "No upgrade available"

**Symptoms**:
- Script exits with "No upgrade available from X.XX"
- `do-release-upgrade --check-dist-upgrade-only` shows no new release

**Cause**:
- You may already be on the latest available release
- Network connectivity issues preventing upgrade detection
- Repository configuration problems

**Solutions**:

1. **Check current version**:
   ```bash
   lsb_release -a
   # If you're already on 25.10, you're done!
   ```

2. **Verify network and repos**:
   ```bash
   sudo apt update
   do-release-upgrade --check-dist-upgrade-only
   ```

3. **Check if on intermediate version**:
   ```bash
   # If on 25.04, the script should detect 25.10 as next step
   # Just re-run: sudo ./03-upgrade-execution.sh
   ```

---

### Issue: "Sorry, cannot upgrade this system to 25.04 right now" (ZFS Block)

**Symptoms**:
- Upgrade fails with: "Sorry, cannot upgrade this system to 25.04 right now"
- Error mentions: "System freezes have been observed on upgrades to 25.04 with ZFS enabled"
- References: https://wiki.ubuntu.com/PluckyPuffin/ReleaseNotes

**Cause**:
Ubuntu 25.04 had a bug where `update-grub` would freeze when listing ZFS snapshots during upgrade (GitHub issue #17337). This affected systems on older kernels with mismatched ZFS kernel/userspace modules. Ubuntu implemented a blanket block on all ZFS upgrades.

**Solution**:
The upgrade script uses `--proposed` flag to get a newer release upgrader that:
- Either has the ZFS freeze bug fixed, or
- Skips the block for systems on HWE kernel 6.14+ (which don't have the issue)

If you're running the script and still see this error:
```bash
# Use --proposed flag manually
sudo do-release-upgrade --proposed
```

**Note**: Systems on Ubuntu 24.04 HWE kernel 6.14+ are not affected by the original freeze bug, which only affected older kernel versions during 24.10 → 25.04 upgrades.

---

### Issue: "There is no development version of an LTS available"

**Symptoms**:
- `do-release-upgrade` says "There is no development version of an LTS available"
- Script exits with "To upgrade to the latest non-LTS development release set Prompt=normal"
- Happens after choosing [Y] for `/etc/update-manager/release-upgrades` conflict

**Cause**:
When you choose [Y] to install the package maintainer's version of `/etc/update-manager/release-upgrades`, it resets `Prompt=lts`. This prevents upgrading from 24.04 LTS to 25.04/25.10 (non-LTS interim releases).

**Solutions**:

1. **Automatic fix** (if using latest script):
   ```bash
   # The script now automatically fixes this
   # Just re-run the upgrade script
   sudo ./03-upgrade-execution.sh
   ```

2. **Manual fix**:
   ```bash
   # Set Prompt=normal to allow interim release upgrades
   sudo sed -i 's/^Prompt=.*/Prompt=normal/' /etc/update-manager/release-upgrades

   # Verify the change
   grep Prompt /etc/update-manager/release-upgrades
   # Should show: Prompt=normal

   # Retry upgrade
   sudo ./03-upgrade-execution.sh
   ```

**Prevention**:
- When prompted for `/etc/update-manager/release-upgrades` conflict, choose [Y]
- The script will automatically reconfigure it after package installation
- For other config files, generally choose [N] to keep your customizations

---

### Issue: "Repository not found" or Mirror Errors

**Symptoms**:
- `do-release-upgrade` fails with repository errors
- Cannot download packages

**Solutions**:

1. Check network connectivity:
```bash
ping -c 4 archive.ubuntu.com
```

2. Try different Ubuntu mirror:
```bash
sudo sed -i 's|http://archive.ubuntu.com|http://us.archive.ubuntu.com|g' /etc/apt/sources.list
sudo apt update
```

3. Retry upgrade:
```bash
sudo do-release-upgrade -d
```

---

### Issue: Package Conflicts During Upgrade

**Symptoms**:
- Upgrade stops with package conflict errors
- Cannot install certain packages

**Solutions**:

1. Note the conflicting package name
2. Remove conflicting package (if not critical):
```bash
sudo apt remove CONFLICTING_PACKAGE
```

3. Retry upgrade:
```bash
sudo do-release-upgrade -d
```

4. Reinstall removed package after upgrade (if needed):
```bash
sudo apt install PACKAGE_NAME
```

---

### Issue: Upgrade Interrupted (Network/Power Loss)

**Symptoms**:
- Upgrade process was interrupted
- System in inconsistent state
- Some packages upgraded, others not

**Solutions**:

1. First, check system state:
```bash
lsb_release -a
dpkg -l | grep ^iU
```

2. Reconfigure partially installed packages:
```bash
sudo dpkg --configure -a
```

3. Fix broken dependencies:
```bash
sudo apt-get -f install
```

4. Complete the upgrade:
```bash
sudo do-release-upgrade -d
```

5. If upgrade won't continue, restore from snapshot:
```bash
sudo zfs rollback rpool/root@before-upgrade-to-questing-TIMESTAMP
```

---

## Post-Upgrade Boot Issues

### Issue: System Won't Boot After Upgrade

**Symptoms**:
- Black screen after GRUB
- Drops to emergency shell
- "Failed to mount root filesystem"

**Solutions**:

**Method 1: Boot from snapshot**

1. At GRUB menu, press `e` to edit boot entry
2. Find line starting with `linux`
3. Change `root=ZFS=rpool/root` to include snapshot:
   `root=ZFS=rpool/root@before-upgrade-to-questing-TIMESTAMP`
4. Press `Ctrl+X` to boot

If successful, perform full rollback (see 07-rollback-procedure.md)

**Method 2: Force pool import**

1. At emergency shell, try manual import:
```bash
zpool import -f rpool
zfs mount rpool/root
exit
```

2. If system boots, fix permanently:
```bash
sudo update-initramfs -u -k all
sudo update-grub
sudo reboot
```

**Method 3: Boot from older kernel**

1. Reboot and access GRUB menu (hold Shift during boot)
2. Select "Advanced options for Ubuntu"
3. Choose older kernel (6.8.x for Ubuntu 24.04)
4. If boots, perform rollback

---

### Issue: Dracut Emergency Shell on Boot

**Symptoms**:
- System drops to dracut emergency shell
- "Failed to mount /sysroot"
- "Waiting for ZFS pool import"

**Solutions**:

**At dracut emergency shell**:

1. Try manual pool import:
```bash
zpool import -f rpool
```

2. If import fails, check pool status:
```bash
zpool import
# Look for pool ID and state
```

3. Mount and boot:
```bash
zpool import -f rpool
mount -t zfs rpool/root /sysroot
exit
```

**After booting**:

1. Regenerate initramfs with correct settings:
```bash
sudo dracut --force --kver $(uname -r)
```

2. Ensure ZFS modules are included:
```bash
# Check dracut ZFS configuration
cat /etc/dracut.conf.d/zfs.conf

# Verify ZFS module is in initramfs
lsinitrd /boot/initrd.img-$(uname -r) | grep zfs
```

3. Update GRUB:
```bash
sudo update-grub
sudo /usr/local/bin/sync-mirror-boot
```

---

### Issue: GRUB Shows Only One Boot Entry

**Symptoms**:
- Missing "Ubuntu - Rotating" boot entry
- Cannot boot from secondary drive

**Solutions**:

```bash
# Recreate boot entries
sudo /usr/local/bin/sync-mirror-boot --shutdown

# Verify entries created
sudo efibootmgr -v

# If missing, manually create:
sudo efibootmgr --create --gpt --disk /dev/disk/by-id/DRIVE1 --part 1 --loader \\EFI\\Ubuntu-LABEL\\shimx64.efi --label "Ubuntu - Drive1"
```

---

## Dracut Migration Issues

### Issue: Dracut Not Generating Initramfs

**Symptoms**:
- `dracut --force` fails
- No initramfs files in /boot/
- Error: "dracut: command not found"

**Solutions**:

1. Verify dracut is installed:
```bash
sudo apt install dracut zfs-dracut
```

2. Check dracut can find modules:
```bash
dracut --list-modules | grep zfs
```

3. Manually generate initramfs:
```bash
sudo dracut --force --kver $(uname -r)
```

4. If still fails, check for errors:
```bash
sudo dracut --force --verbose --kver $(uname -r)
```

---

### Issue: Dracut Initramfs Missing ZFS Modules

**Symptoms**:
- System boots to emergency shell
- `lsinitrd` shows no ZFS modules
- "zpool: command not found" in initramfs

**Solutions**:

1. Verify zfs-dracut is installed:
```bash
dpkg -l | grep zfs-dracut
sudo apt install zfs-dracut
```

2. Create/verify dracut ZFS configuration:
```bash
cat > /etc/dracut.conf.d/zfs.conf << 'EOF'
add_dracutmodules+=" zfs "
install_optional_items+=" /etc/zfs/zpool.cache "
EOF
```

3. Regenerate initramfs:
```bash
sudo dracut --force --add zfs --kver $(uname -r)
```

4. Verify ZFS is included:
```bash
lsinitrd /boot/initrd.img-$(uname -r) | grep -i zfs
```

---

### Issue: Both initramfs-tools and Dracut Present

**Symptoms**:
- Both packages installed simultaneously
- Unclear which is generating initramfs
- Conflicts during updates

**Solutions**:

1. Check which is installed:
```bash
dpkg -l | grep -E "initramfs-tools|dracut"
```

2. Choose one and remove the other:
```bash
# Keep dracut (recommended for 25.10)
sudo apt remove initramfs-tools zfs-initramfs

# OR keep initramfs-tools (if reverting to 24.04)
sudo apt remove dracut zfs-dracut
```

3. Regenerate initramfs with chosen tool:
```bash
# If using dracut
sudo dracut --force --regenerate-all

# If using initramfs-tools
sudo update-initramfs -c -k all
```

---

## ZFS Pool Issues

### Issue: Pool Not Importing Automatically

**Symptoms**:
- Manual `zpool import rpool` works
- But pool doesn't import on boot

**Solutions**:

1. Check zfs-import services:
```bash
sudo systemctl status zfs-import-cache.service
sudo systemctl status zfs-import.target
```

2. Enable services:
```bash
sudo systemctl enable zfs-import-cache.service
sudo systemctl enable zfs-import.target
sudo systemctl enable zfs-mount.service
sudo systemctl enable zfs.target
```

3. Update pool cache:
```bash
sudo zpool set cachefile=/etc/zfs/zpool.cache rpool
```

4. Rebuild initramfs:
```bash
sudo dracut --force --kver $(uname -r)
```

---

### Issue: OpenZFS 2.3.4 + Kernel 6.17 Compatibility Problems

**Symptoms**:
- ZFS kernel module fails to load
- "Unknown symbol" errors in dmesg
- Pool import fails

**Solutions**:

1. Check ZFS module status:
```bash
sudo modprobe zfs
dmesg | grep -i zfs | tail -20
```

2. If module won't load, boot older kernel:
```bash
# Reboot, select 6.8.x kernel from GRUB
# This kernel should have working ZFS
```

3. Consider staying on Ubuntu 24.04 until OpenZFS adds full 6.17 support

4. Or wait for updated zfs-dkms package:
```bash
sudo apt update
sudo apt upgrade zfs-dkms
```

---

## Boot Mirror Synchronization Issues

### Issue: sync-mirror-boot Script Fails

**Symptoms**:
- `/usr/local/bin/sync-mirror-boot` returns errors
- GRUB not syncing to second drive
- Boot entries not created

**Solutions**:

1. Check script exists and is executable:
```bash
ls -lh /usr/local/bin/sync-mirror-boot
sudo chmod +x /usr/local/bin/sync-mirror-boot
```

2. Run manually with verbose output:
```bash
sudo bash -x /usr/local/bin/sync-mirror-boot
```

3. Check sync-grub-to-mirror-drives:
```bash
sudo /usr/local/bin/sync-grub-to-mirror-drives
```

4. Verify drives are accessible:
```bash
sudo zpool status rpool
lsblk
```

---

### Issue: Kernel Hooks Not Triggering

**Symptoms**:
- Kernel updates don't regenerate initramfs
- GRUB not syncing after kernel update
- Hooks in `/etc/kernel/` not running

**Solutions**:

1. Verify hooks exist:
```bash
ls -lh /etc/kernel/postinst.d/zz-sync-mirror-boot
ls -lh /etc/kernel/postrm.d/zz-sync-mirror-boot
```

2. Recreate hooks if missing:
```bash
sudo ln -sf /usr/local/bin/sync-mirror-boot /etc/kernel/postinst.d/zz-sync-mirror-boot
sudo ln -sf /usr/local/bin/sync-mirror-boot /etc/kernel/postrm.d/zz-sync-mirror-boot
```

3. Ensure hooks are executable:
```bash
sudo chmod +x /etc/kernel/postinst.d/zz-sync-mirror-boot
sudo chmod +x /etc/kernel/postrm.d/zz-sync-mirror-boot
```

4. Test hooks manually:
```bash
sudo run-parts --verbose /etc/kernel/postinst.d
```

---

## Kernel and Initramfs Issues

### Issue: Kernel Panic on Boot

**Symptoms**:
- "Kernel panic - not syncing"
- System freezes during boot
- Unable to mount root filesystem

**Solutions**:

1. Boot older kernel from GRUB menu
2. Regenerate initramfs for current kernel:
```bash
sudo dracut --force --kver KERNEL_VERSION
```

3. Check kernel command line parameters:
```bash
cat /proc/cmdline
# Should include: root=ZFS=rpool/root
```

4. Verify in /etc/default/grub:
```bash
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
```

5. Update and sync:
```bash
sudo update-grub
sudo /usr/local/bin/sync-mirror-boot
```

---

### Issue: Multiple Kernels, Unsure Which is Current

**Symptoms**:
- Many kernels installed
- Dracut fails on some kernels
- Boot menu cluttered

**Solutions**:

1. Identify current kernel:
```bash
uname -r
```

2. List all installed kernels:
```bash
dpkg -l | grep linux-image
ls /lib/modules/
```

3. Remove old kernels (keep current + one backup):
```bash
# Remove specific old kernel
sudo apt remove linux-image-X.X.X-XX-generic

# Or use autoremove to clean old kernels
sudo apt autoremove
```

4. Regenerate initramfs for remaining kernels:
```bash
sudo dracut --force --regenerate-all
```

---

## Network and Service Issues

### Issue: Network Not Working After Upgrade

**Symptoms**:
- No internet connectivity
- `ip addr` shows no IP address
- Network interfaces down

**Solutions**:

1. Check interface names (may have changed):
```bash
ip link show
```

2. Check netplan configuration:
```bash
ls /etc/netplan/
cat /etc/netplan/*.yaml
```

3. Reconfigure network:
```bash
sudo netplan apply
```

4. If using NetworkManager:
```bash
sudo systemctl restart NetworkManager
```

5. Check for errors:
```bash
sudo journalctl -u systemd-networkd
sudo journalctl -u NetworkManager
```

---

### Issue: SSH Not Working

**Symptoms**:
- Cannot SSH to server
- Connection refused or timeout
- SSH service not running

**Solutions**:

1. Check SSH service status:
```bash
sudo systemctl status ssh
```

2. Start/restart SSH:
```bash
sudo systemctl start ssh
sudo systemctl enable ssh
```

3. Check SSH is listening:
```bash
sudo ss -tlnp | grep 22
```

4. Check firewall:
```bash
sudo ufw status
sudo ufw allow 22/tcp
```

---

### Issue: Failed Services After Upgrade

**Symptoms**:
- `systemctl --failed` shows failed services
- Some applications not starting

**Solutions**:

1. Identify failed services:
```bash
systemctl --failed
```

2. Check service logs:
```bash
sudo journalctl -u SERVICE_NAME -n 50
```

3. Restart failed services:
```bash
sudo systemctl restart SERVICE_NAME
```

4. If service consistently fails, check compatibility:
```bash
# May need to reconfigure or update service
sudo apt upgrade SERVICE_PACKAGE
```

---

## Performance Issues

### Issue: Slow Boot After Upgrade

**Symptoms**:
- Boot takes much longer than before
- System hangs during boot

**Solutions**:

1. Analyze boot time:
```bash
systemd-analyze
systemd-analyze blame
```

2. Check for slow services:
```bash
systemd-analyze critical-chain
```

3. Optimize dracut:
```bash
# Use hostonly mode
cat > /etc/dracut.conf.d/90-optimization.conf << 'EOF'
hostonly="yes"
compress="zstd"
EOF

# Regenerate
sudo dracut --force --kver $(uname -r)
```

4. Disable unnecessary services:
```bash
sudo systemctl disable SLOW_SERVICE
```

---

### Issue: High Memory Usage

**Symptoms**:
- System using more RAM than before
- OOM killer activating

**Solutions**:

1. Check memory usage:
```bash
free -h
top
```

2. Check for memory leaks:
```bash
sudo journalctl | grep -i "out of memory"
```

3. Check ZFS ARC usage:
```bash
arc_summary | grep "ARC size"
```

4. Limit ZFS ARC if needed:
```bash
# Limit ARC to 50% of RAM (example for 16GB system = 8GB)
echo "options zfs zfs_arc_max=8589934592" | sudo tee /etc/modprobe.d/zfs.conf
sudo update-initramfs -u -k all
sudo reboot
```

---

## Recovery Procedures

### Full System Recovery from Live USB

If all else fails, boot from Live USB and recover:

1. **Boot Ubuntu 24.04 (or later) Live USB**

2. **Install ZFS tools**:
```bash
sudo apt update
sudo apt install -y zfsutils-linux
sudo modprobe zfs
```

3. **Import pool**:
```bash
sudo zpool import -f rpool
```

4. **List snapshots**:
```bash
sudo zfs list -t snapshot -r rpool
```

5. **Rollback or mount**:
```bash
# Option A: Rollback to pre-upgrade snapshot
sudo zfs rollback rpool/root@before-upgrade-TIMESTAMP

# Option B: Mount and repair
sudo zfs set mountpoint=/mnt rpool/root
sudo zfs mount rpool/root
# Make repairs in /mnt
```

6. **Chroot and fix bootloader**:
```bash
for dir in dev proc sys run; do sudo mount --bind /$dir /mnt/$dir; done
sudo chroot /mnt
grub-install /dev/disk/by-id/DRIVE1
grub-install /dev/disk/by-id/DRIVE2
update-grub
exit
```

7. **Unmount and reboot**:
```bash
for dir in run sys proc dev; do sudo umount /mnt/$dir; done
sudo zfs unmount rpool/root
sudo zpool export rpool
sudo reboot
```

---

## Getting Help

If issues persist:

1. **Gather diagnostics**:
```bash
# Create diagnostics bundle
sudo zpool status -v > /tmp/zpool-status.txt
sudo dmesg > /tmp/dmesg.txt
sudo journalctl -b > /tmp/journal.txt
lsb_release -a > /tmp/version.txt
uname -a >> /tmp/version.txt
```

2. **Consult resources**:
   - Ubuntu Forums: https://ubuntuforums.org/
   - OpenZFS GitHub: https://github.com/openzfs/zfs/issues
   - Ubuntu ZFS Root Mirror: https://github.com/csmarshall/ubuntu-zfs-mirror/issues

3. **Consider rollback**:
   - See `07-rollback-procedure.md`
   - Ubuntu 24.04 LTS is supported until 2029

---

## Prevention

To avoid issues in future upgrades:

1. **Always backup before major changes**
2. **Test in VM first** if possible
3. **Read release notes** before upgrading
4. **Don't upgrade production systems immediately** - wait for community feedback
5. **Keep good documentation** of your configuration
6. **Maintain external backups** of critical data

---

Remember: **When in doubt, rollback and seek help** rather than risking data loss or extended downtime.
