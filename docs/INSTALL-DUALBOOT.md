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

## How much do you actually need to free?

Concrete targets, so you know when to stop deleting:

| For | Space | Notes |
|---|---|---|
| NixOS root + nix store | **150 GB** | 50 GB works; 150 is comfortable. The store grows — 20 bootable generations of a system with GNOME, Steam and emulators is not small. |
| Swap | 16 GB | |
| Local models | 50 GB | 8B ≈ 5 GB, 14B ≈ 9 GB, and you'll collect a few |
| Offline Wikipedia | 10–110 GB | simple-English 10 GB, text-only 50 GB, full-with-images 110 GB |
| Maps (one state) | < 1 GB | genuinely trivial |
| Media / NAS | whatever you have | the open-ended one |

**Minimum viable: ~250 GB. Comfortable: ~600 GB.**

Below 250 GB you'll be managing space instead of using the machine, which
defeats the point.

## Option 1 — Delete games (free)

You said you have a lot installed, which makes this the obvious first move.

```powershell
cd path\to\nixserver\scripts
.\disk-report.ps1 -TargetGB 600
```

It reports Steam games sorted by size with **last-played dates and a running
cumulative total** — read down until Cumulative passes your target and stop.
It also measures Xbox/Game Pass installs, which hide in an ACL-protected
folder that Explorer misreports, and lists the biggest directories on every
drive for everything that isn't a game.

It calls out two easy categories: games not played in over a year, and games
installed but never played at all. That is usually most of the way to 600 GB
on its own.

Uninstall through Steam (Library → right-click → Manage → Uninstall) rather
than deleting folders, or Steam keeps the manifest and gets confused. Nothing
is permanent — Steam re-downloads on demand, and saves are in Steam Cloud for
most titles. Check the cloud icon before removing anything you have a lot of
progress in.

### The gotcha that will otherwise waste your evening

**Deleting files does not make a partition shrinkable.** Windows can only
shrink a volume up to the last *unmovable* file, and if a pagefile or a shadow
copy sits near the end of the disk, Disk Management will offer you 40 GB after
you just freed 600.

Turn the immovable things off first, shrink, then turn them back on:

```powershell
# Run as Administrator.
powercfg /hibernate off                        # deletes hiberfil.sys
Disable-ComputerRestore -Drive "C:\", "D:\"    # drops shadow copies
vssadmin delete shadows /all /quiet
```

Then set the pagefile to none: System Properties → Advanced → Performance →
Settings → Advanced → Virtual Memory → Uncheck automatic → No paging file →
**reboot**.

Now shrink in Disk Management. You should get nearly all of it.

Afterwards, put the pagefile back (System managed) and re-enable restore.
Leave hibernation off — you disabled Fast Startup anyway, and it just consumes
32 GB matching your RAM.

If it *still* won't shrink far enough, the free tool that handles this
properly is a GParted live USB, which can move unmovable-to-Windows files
because Windows isn't running. Back up first.

## Option 2 — Buy a 2 TB NVMe (~$100)

Still worth considering even though you can free space, because it buys things
deleting doesn't:

- Windows is **never touched** — no shrinking, no BitLocker risk, no chance of
  a partition operation going wrong on a 97%-full disk with no room to recover
- You keep the games
- The NAS gets real room rather than leftovers

Your board is LGA1700 for the 12700KF and will have at least two M.2 slots.

**Do both if you can**: delete the games you don't play regardless (they're
dead weight), and add the disk when convenient.

## Option 3 — Reclaim the mystery 48.83 GB

Do this either way, once you've confirmed what it is.

---

## Layout

**If you free space on D: (no purchase):**

```
Disk 0  (1TB)   Windows, untouched           ← C:, Recovery, ESP 423MB
Disk 1  (2TB)   ┌───────────────────────────┐
                │ D: NTFS  (shrunk, ~1.2TB) │  games stay here
                │ ESP           1 GB   NEW  │
                │ NixOS root + data  ~600GB │  NEW
                │ (48.83GB mystery partition — investigate)
                └───────────────────────────┘
```

**If you buy the NVMe:**

```
Disk 0  (1TB)   Windows, untouched
Disk 1  (2TB)   existing data, untouched
Disk 2  (NEW)   ESP 1GB + NixOS root + data pool
```

The second costs $100 and touches nothing. The first is free and requires a
partition operation on a nearly-full disk holding all your data. Both work;
they trade money against risk.

### Don't share a Steam library between Windows and Linux

Tempting, since you'd have games on both sides. Don't. Proton on an NTFS
partition is a known source of misery — case sensitivity, permissions, and
file-locking semantics all differ, and the failures are intermittent rather
than obvious. Keep separate libraries and accept the duplication.

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

**If you bought a new disk**, it's empty, so `disks.nix` is safe to point at
it. Edit the device path there, then:

```
sudo nix run github:nix-community/disko -- --mode disko ./hosts/vault/disks.nix
sudo nixos-generate-config --no-filesystems --root /mnt
```

**If you freed space on Disk 1 instead**, do NOT use `disks.nix` — it wipes
the whole device, D: included. Partition the free space by hand:

```
sudo cgdisk /dev/disk/by-id/<disk1>
```

In the unallocated space, create:
- 1 GB, type `EF00` — the NixOS ESP
- the rest, type `8300`

Then format and mount:

```
sudo mkfs.fat -F32 -n NIXBOOT /dev/disk/by-id/<disk1>-partN
sudo mkfs.btrfs -L nixos      /dev/disk/by-id/<disk1>-partM
sudo mount /dev/disk/by-id/<disk1>-partM /mnt
sudo mkdir -p /mnt/boot && sudo mount /dev/disk/by-id/<disk1>-partN /mnt/boot
sudo nixos-generate-config --root /mnt
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
