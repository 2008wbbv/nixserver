# Installing alongside Windows

Keeping Windows for gaming, shrinking it, and giving NixOS the rest. Two disks.

## The layout

```
Disk 1  ┌─────────────────────────────────────────────┐
        │ ESP (Windows, ~100MB)  ← leave alone        │
        │ Windows C:  (shrunk)                        │
        │ NixOS ESP   (1GB, NEW)                      │
        │ NixOS root  (rest)                          │
        └─────────────────────────────────────────────┘

Disk 2  ┌─────────────────────────────────────────────┐
        │ ZFS data pool  (whole disk)                 │
        └─────────────────────────────────────────────┘
```

**Why a second ESP rather than sharing Windows':** the ESP Windows creates is
usually 100MB. Each NixOS generation puts a kernel and initrd there, and you're
keeping 20 generations. You will fill 100MB and the failure mode is a rebuild
that half-succeeds. A separate 1GB ESP costs nothing and sidesteps it entirely.
systemd-boot still finds Windows and offers it in the menu.

## Order of operations

### 1. In Windows, first

Three things, all of which are annoying to discover later:

```
Disable Fast Startup:
  Control Panel > Power Options > Choose what the power buttons do
  > Change settings that are currently unavailable
  > uncheck "Turn on fast startup"
```

Fast Startup means "shut down" actually hibernates. A hibernated Windows leaves
its filesystems in a state where anything else touching them causes corruption.
This is the single most common way people lose data in a dual boot.

```
Disable BitLocker, or save your recovery key somewhere off this machine.
```
Changing the partition layout or boot configuration can trip BitLocker's
tamper detection and lock you out at next boot.

```
Shrink the partition from Windows, not from Linux:
  Disk Management > right-click C: > Shrink Volume
```
Windows' own tool understands its filesystem and moves files out of the way.
If it won't shrink as far as you want, it's because unmovable files
(pagefile, hibernation, shadow copies) are sitting near the end — disable
those temporarily and retry.

**How much to leave Windows:** modern games are 100-150GB each. 500GB is
comfortable for a handful; 250GB gets tight fast. Decide by how many you keep
installed at once, not by how many you own.

### 2. Confirm both disks in the installer

Boot the NixOS ISO, then:

```
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,MOUNTPOINT
```

Write down the `/dev/disk/by-id/` paths for both. Never use `/dev/sda` style
names for anything permanent — they reorder between boots.

### 3. Partition disk 1 by hand

`hosts/vault/disks.nix` is **destructive to the whole disk** and must not be
pointed at disk 1 while Windows is on it. Do this one manually:

```
sudo cgdisk /dev/disk/by-id/<disk1>
```

In the free space you created:
- new partition, 1GB, type `EF00` (EFI system partition)
- new partition, rest of free space, type `8300`

Then:

```
sudo mkfs.fat -F32 -n NIXBOOT /dev/disk/by-id/<disk1>-partN
sudo mkfs.btrfs -L nixos      /dev/disk/by-id/<disk1>-partM
```

### 4. Disk 2 can use disko

Disk 2 has nothing on it, so declarative partitioning is safe there. Uncomment
the `zpool.tank` block in `hosts/vault/disks.nix`, point it at disk 2, then:

```
sudo nix run github:nix-community/disko -- --mode disko ./hosts/vault/disks.nix
```

### 5. Mount and install

```
sudo mount /dev/disk/by-id/<disk1>-partM /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-id/<disk1>-partN /mnt/boot

sudo nixos-generate-config --root /mnt
```

Copy the generated `/mnt/etc/nixos/hardware-configuration.nix` over
`hosts/vault/hardware-configuration.nix` in this repo — that replaces the
placeholder, which is currently failing the build on purpose.

Set `networking.hostId` in `hosts/vault/default.nix` (ZFS requires it):

```
head -c4 /dev/urandom | od -A none -t x4
```

Then:

```
sudo nixos-install --flake /mnt/path/to/nixserver#vault
```

## Making the boot menu work

systemd-boot auto-detects Windows if it can see the Windows ESP. Since we made
a separate one, help it along in `hosts/vault/default.nix`:

```nix
boot.loader.systemd-boot = {
  enable = true;
  configurationLimit = 20;
  # Show the menu long enough to actually choose.
  # (set boot.loader.timeout = 10; alongside this)
};
boot.loader.efi.canTouchEfiVariables = true;
```

If Windows doesn't appear, mount the Windows ESP somewhere and check that
`EFI/Microsoft/Boot/bootmgfw.efi` exists; systemd-boot looks for exactly that.
Worst case, the firmware boot menu (F12 / F11 / Esc, vendor-dependent) always
works and needs no configuration at all.

## Ongoing annoyances, so they don't surprise you

**Windows updates sometimes reset the boot order** to put Windows Boot Manager
first. Fix with `efibootmgr -o` from NixOS, or from the firmware menu. It's a
nuisance, not damage.

**Clock skew.** Windows writes local time to the hardware clock, Linux writes
UTC, and they'll fight — your clock will jump by your timezone offset each time
you switch. Fix it on the Linux side:

```nix
time.hardwareClockInLocalTime = true;
```

**A server that reboots into Windows is a server that's offline.** This is the
real cost of the arrangement: every gaming session takes down Jellyfin, DNS
(so *your whole network's* name resolution), Vaultwarden, and everything else.

That's worth sitting with before you commit to it. DNS in particular is
load-bearing — if this box is your resolver and it's booted into Windows, every
device configured to use it stops resolving anything.

Ways out, cheapest first:
- **Set a secondary DNS** on your devices so DNS survives the box being down.
  Costs nothing, removes the worst of the pain.
- **Game on a different machine** and let this one stay up. Obviously.
- **GPU passthrough to a Windows VM** — the server never reboots, Windows runs
  in a VM with the 6750 XT passed through, near-native gaming performance.
  This genuinely works and is the "right" answer, but it needs a second GPU
  (or an iGPU) for the host, IOMMU groups that cooperate, and a weekend. Worth
  knowing it exists; not worth doing on day one.
