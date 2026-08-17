# Installing alongside Windows

Keeping Windows for gaming (Game Pass makes that non-optional), shrunk, with
NixOS taking the rest.

## Stop — you have a space problem, not a partitioning problem

From Disk Management:

| Disk | Size | Partition | Used | **Free** |
|---|---|---|---|---|
| Disk 0 | 931.50 GB | C: NTFS 930.17 GB | ~900 GB | **30.22 GB (3%)** |
| | | Recovery 931 MB | | |
| | | EFI 423 MB | | |
| Disk 1 | 1907.71 GB | D: NTFS 1858.88 GB | ~1841 GB | **17.87 GB (1%)** |
| | | "EFI System Partition" 48.83 GB | | — see below |

**Total free space across both disks: ~48 GB.**

You cannot shrink a partition below the data in it. Windows will let you
reclaim roughly the free space and usually less, because unmovable files
(pagefile, hibernation, shadow copies) sit wherever they like. Realistically
you could recover maybe 20 GB from C: and 15 GB from D:.

That is not enough to install NixOS onto, let alone run a NAS, a media library,
offline Wikipedia, or local models. This has to be solved before any of the
rest of the plan means anything.

### That 48.83 GB "EFI System Partition" is wrong

A real ESP is 100–500 MB. Yours on Disk 1 is 48.83 GB, which is not a thing
Windows or any installer creates on purpose. Most likely it's a leftover
partition — an old Linux install, a recovery image, or a vendor restore
partition — that got flagged `EF00` and is now being mislabelled.

**Investigate before deleting.** From the NixOS installer:

```
sudo fdisk -l /dev/disk/by-id/<disk1>
sudo mkdir -p /mnt/check
sudo mount /dev/disk/by-id/<disk1>-part3 /mnt/check
ls -la /mnt/check
```

If it holds nothing but an empty `EFI/` directory or an old distro's files,
that's ~49 GB back for free. Don't touch it until you've looked.

## Your options, in order of how much I'd recommend them

### 1. Buy a 2 TB NVMe — ~$100

This is the answer. Your board is LGA1700 for the 12700KF and will have at
least two M.2 slots, very likely three.

- Windows is **never touched**. No shrinking, no risk, no BitLocker drama.
- NixOS gets a whole disk to itself.
- The NAS gets actual room, which is the entire point of building one.
- Zero destructive operations anywhere in the process.

Every other option on this list is you spending hours to avoid spending $100,
and ending up with less. Given that you're planning to store a media library,
a Wikipedia dump, and local models, 2 TB is the floor rather than a luxury.

### 2. Free up real space first

If the money isn't there right now: you have ~2.8 TB of data across two disks
and no idea what it is. Find out.

```powershell
winget install WinDirStat
```

Then decide what moves to the new NAS later and what deletes now. Game
installs are the usual answer — modern titles are 100–150 GB each and you
probably have several you haven't launched in a year. Steam re-downloads them
on demand.

Aim to free 500 GB minimum before installing.

### 3. Reclaim the mystery 48.83 GB

Do this regardless of which option you pick, once you've confirmed what it is.

---

## Layout, assuming you buy the disk

```
Disk 0  (1TB)   Windows, untouched          ← C:, Recovery, ESP 423MB
Disk 1  (2TB)   existing data, untouched    ← D: (+ 48GB to investigate)
Disk 2  (NEW)   ┌──────────────────────────┐
                │ ESP        1 GB          │
                │ NixOS root + nix store   │
                │ data pool                │
                └──────────────────────────┘
```

Nothing destructive happens to a disk with your data on it. That alone is
worth the hundred dollars.

**Why NixOS gets its own 1 GB ESP** rather than sharing Windows' 423 MB one:
each generation puts a kernel and initrd there and you're keeping 20 of them.
423 MB fills up, and the failure mode is a rebuild that half-succeeds.
systemd-boot still finds Windows on the other disk and offers it in the menu.

## Before you touch anything, in Windows

Three things, all annoying to discover later.

**Disable Fast Startup.**
```
Control Panel > Power Options > Choose what the power buttons do
  > Change settings that are currently unavailable
  > uncheck "Turn on fast startup"
```
"Shut down" actually hibernates otherwise. A hibernated Windows leaves its
filesystems in a state where anything else touching them causes corruption.
This is the most common way people lose data in a dual boot.

**Disable BitLocker, or save the recovery key somewhere off this machine.**
Changing partition layout or boot configuration can trip its tamper detection
and lock you out at next boot.

**Back up anything irreplaceable.** With both disks at 97%+ full, there is no
room for a mistake to be recoverable in place.

## Install

Boot the NixOS ISO, then confirm what you're looking at:

```
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,MOUNTPOINT
```

Write down `/dev/disk/by-id/` paths. Never use `/dev/sda`-style names for
anything permanent — they reorder between boots.

Since the new disk is empty, `disks.nix` is safe to point at it. Edit the
device path there, then:

```
sudo nix run github:nix-community/disko -- --mode disko ./hosts/vault/disks.nix
sudo nixos-generate-config --no-filesystems --root /mnt
```

Copy the generated `hardware-configuration.nix` over the placeholder in this
repo — it's currently failing the build on purpose. Set `networking.hostId`:

```
head -c4 /dev/urandom | od -A none -t x4
```

Then:

```
sudo nixos-install --flake /mnt/path/to/nixserver#vault
```

## Boot menu

systemd-boot auto-detects Windows if it can see the Windows ESP. If it doesn't
appear, mount Disk 0's 423 MB ESP and confirm `EFI/Microsoft/Boot/bootmgfw.efi`
exists — that's exactly what it looks for. The firmware boot menu (F12/F11/Esc)
always works regardless and needs no configuration.

Set a visible timeout so you can actually choose:

```nix
boot.loader.timeout = 10;
```

## Ongoing annoyances

**Windows updates sometimes reset the boot order.** Fix with `efibootmgr -o`
from NixOS or from the firmware menu. Nuisance, not damage.

**Clock skew.** Windows writes local time to the hardware clock, Linux writes
UTC, so your clock jumps by your timezone offset each time you switch. Already
handled — `time.hardwareClockInLocalTime = true` is set in the config.

**A server booted into Windows is a server that's offline.** DNS is the part
that hurts: every device pointed at this box stops resolving anything. Set a
secondary DNS on your devices, or in the Tailscale admin console, so name
resolution survives. See [GAMING-ARCHITECTURE.md](GAMING-ARCHITECTURE.md) for
how to stop rebooting entirely.
