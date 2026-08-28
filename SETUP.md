# Setup — start here

Six phases. **Do them in order and don't skip ahead** — each one assumes the
previous is finished. Phases 0–2 are the ones with real risk; after that it's
just flipping flags.

Expect the whole thing to take a weekend, most of it waiting on downloads and
Steam uninstalls.

---

# Phase 0 — Free up space (Windows)

**Nothing else can start until this is done.** You have ~48 GB free across two
disks and need ~600 GB.

### 0.1 — See what's eating it

```powershell
cd <this repo>\scripts
.\disk-report.ps1 -TargetGB 600
```

Read the Steam table top-down, watch the **Cumulative** column, stop when it
passes 600 GB. It also flags "not played in over a year" and "never played",
which is usually most of the way there on its own.

Uninstall through **Steam → Library → right-click → Manage → Uninstall**, not
by deleting folders. Saves are in Steam Cloud for most titles — check the cloud
icon before removing anything with a lot of progress.

### 0.2 — Export your program list

Do this **now, while you're still in Windows**. It's tedious to get later.

```powershell
.\export-windows-programs.ps1
```

Copy the resulting folder somewhere you'll still have it — a USB stick, your
phone, cloud storage. Not just the desktop of the machine you're about to
repartition.

### 0.3 — The three Windows prerequisites

```powershell
# Run PowerShell as Administrator
powercfg /hibernate off
Disable-ComputerRestore -Drive "C:\", "D:\"
vssadmin delete shadows /all /quiet
```

Then:
- **Disable Fast Startup** — Control Panel → Power Options → "Choose what the
  power buttons do" → "Change settings that are currently unavailable" →
  uncheck "Turn on fast startup". *Skipping this is the most common way people
  corrupt a dual-boot.*
- **Disable BitLocker**, or save the recovery key somewhere off this machine.
- **Set the pagefile to none**: System Properties → Advanced → Performance →
  Settings → Advanced → Virtual Memory → uncheck automatic → No paging file.
- **Reboot.**

### 0.4 — Shrink D:

Disk Management → right-click D: → Shrink Volume. Take ~600 GB.

If it offers far less than you freed, the pagefile or a shadow copy is still
sitting near the end of the volume — recheck 0.3. Last resort is a GParted live
USB, which can move what Windows won't.

Afterwards, put the pagefile back (System managed). Leave hibernation off.

> ✅ **Checkpoint:** ~600 GB of unallocated space on Disk 1, Fast Startup off,
> program list exported and copied somewhere safe.

---

# Phase 1 — Install NixOS

### 1.1 — Make the installer USB

Download the **minimal ISO** from <https://nixos.org/download> (not the
graphical one — you're installing from a config, not a wizard).

Write it with [Rufus](https://rufus.ie) in **DD mode**, or Ventoy.

### 1.2 — Boot it

Mash F12 (or Del → boot menu; varies by board) and pick the USB. In BIOS while
you're there, set:

- **Restore on AC Power Loss → Power On** — so a blip brings the server back
- **Wake on LAN / ErP → enabled** — so you can power it on remotely
- **Secure Boot → off** — NixOS doesn't do Secure Boot without extra work

### 1.3 — Get networking and become root

```bash
sudo -i
# wifi only if you must — use ethernet:
# wpa_supplicant -B -i wlan0 -c <(wpa_passphrase 'SSID' 'password')
ping -c1 nixos.org
```

### 1.4 — Identify your disks. Carefully.

```bash
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,MOUNTPOINT
ls -l /dev/disk/by-id/
```

Write down the `by-id` path for **Disk 1** (the 2 TB one). Never use `/dev/sda`
style names — they reorder between boots.

### 1.5 — Check that mystery 48.83 GB partition

Before partitioning, find out what it is:

```bash
fdisk -l /dev/disk/by-id/<disk1>
mkdir -p /mnt/check
mount /dev/disk/by-id/<disk1>-part3 /mnt/check   # adjust part number
ls -la /mnt/check
umount /mnt/check
```

If it's an old distro's leftovers or an empty `EFI/`, delete it in the next
step for ~49 GB back. If you can't tell what it is, leave it alone.

### 1.6 — Partition the free space

**Do not use `disks.nix`.** It wipes the entire device — D: included.

```bash
cgdisk /dev/disk/by-id/<disk1>
```

In the unallocated space create two partitions:

| Size | Type | Purpose |
|---|---|---|
| 1 GB | `EF00` | NixOS ESP (Windows' 423 MB one is too small for 20 generations) |
| rest | `8300` | NixOS root |

Write, quit, then:

```bash
mkfs.fat -F32 -n NIXBOOT /dev/disk/by-id/<disk1>-partN   # the EF00 one
mkfs.btrfs -f -L nixos   /dev/disk/by-id/<disk1>-partM   # the 8300 one

mount /dev/disk/by-id/<disk1>-partM /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-id/<disk1>-partN /mnt/boot
```

### 1.7 — Run the bootstrap script

```bash
nix-shell -p git
git clone https://github.com/2008wbbv/nixserver /tmp/nixserver
cd /tmp/nixserver
git checkout claude/nix-server-config-lfykkt

sudo bash scripts/bootstrap.sh
```

It checks your mounts, generates the hardware config and drops it into place,
generates a `hostId`, prompts for your username / SSH key / timezone, copies
everything to `/mnt/etc/nixos`, and runs the install. It stops and asks before
anything irreversible.

If you'd rather do it by hand, the script is short and readable — every step is
a command you can run yourself.

**The install will probably fail the first time.** The config has never been
evaluated. See *When the build fails* at the bottom; it's almost always a
renamed option and the error names the line. Fix it in `/mnt/etc/nixos` and
re-run `nixos-install --flake /mnt/etc/nixos#vault`.

Set a root password when prompted, then `reboot`.

> ✅ **Checkpoint:** boot menu shows both NixOS and Windows, NixOS boots to a
> GNOME login screen, and you can log in.

---

# Phase 2 — Get on the tailnet

Tier 1 is already enabled in the config: Tailscale, DNS, Caddy, monitoring.

### 2.1 — Enrol in Tailscale

```bash
sudo tailscale up --ssh --advertise-exit-node
```

Open the URL it prints. Then in the [admin console](https://login.tailscale.com/admin/machines):
approve the exit node, and disable key expiry for this machine (otherwise it
drops off the tailnet in 6 months and you'll be confused).

Note the tailnet IP — `tailscale ip -4`, something like `100.x.y.z`.

### 2.2 — Point the tailnet at your DNS

In the admin console → **DNS**:
- Add a **global nameserver**: your tailnet IP
- Turn on **Override local DNS**

Every enrolled device now gets ad-blocked, recursively-resolved DNS — including
on cellular, away from home. This is the piece that makes not owning a router
a non-issue.

**Also set a secondary DNS** (1.1.1.1) on your devices, so name resolution
survives this box being in Windows.

### 2.3 — Fix the DNS rewrites

`modules/services/dns.nix` has `127.0.0.1` placeholders. Replace both with your
actual tailnet IP so `*.lab.internal` resolves for other devices, then:

```bash
cd /etc/nixos && just switch
```

### 2.4 — Check it works

From your laptop, on the tailnet:

```
https://grafana.lab.internal
```

You'll get a certificate warning — Caddy is using its own CA. Either accept it,
or install the root cert from
`/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`.

> ✅ **Checkpoint:** you can SSH in from anywhere over Tailscale, DNS filtering
> works on your phone, Grafana loads.

**Commit here.** `git add -A && git commit -m "working tier 1"`

---

# Phase 3 — Secrets

Only needed once you want services that hold credentials.

Follow `secrets/README.md` — the short version:

```bash
# On your laptop
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt        # your public key

# The server's key
nix shell nixpkgs#ssh-to-age -c sh -c 'ssh-keyscan vault | ssh-to-age'
```

Put both in `.sops.yaml`, then `sops secrets/secrets.yaml` and add what you
need. Finally set `homelab.secrets.enable = true` in `hosts/vault/default.nix`.

**Back up your age key somewhere off this machine.** Losing it means losing
every secret in the repo.

---

# Phase 4 — Storage and daily services

Turn these on **one at a time**, rebuilding after each. If something breaks you
want to know which flag did it.

```nix
homelab.storage.enable = true;      # read modules/profiles/storage.nix first
homelab.backups.enable = true;      # set a restic target before enabling
homelab.files.enable = true;
homelab.vaultwarden.enable = true;
homelab.media.enable = true;
homelab.knowledge.enable = true;
```

**Do `backups` before `vaultwarden`.** Don't put your only copy of a password
in something that isn't backed up yet.

After Samba comes up: `sudo smbpasswd -a <your-username>`.

---

# Phase 5 — Everything else

Same approach, one at a time:

```nix
homelab.downloads.enable = true;    # needs a WireGuard config in sops
homelab.anonymity.enable = true;
homelab.maps.enable = true;         # set your state's bbox first
homelab.osint.enable = true;
homelab.llm.enable = true;
homelab.comms.enable = true;
homelab.gaming.enable = true;       # needs a dummy HDMI plug
```

Two things to verify rather than assume:

```bash
# torrent traffic is actually confined to the VPN
sudo ip netns exec wg curl -s https://ifconfig.me   # VPN IP
curl -s https://ifconfig.me                          # your IP — must differ

# tor routing works
tor-route on && tor-route test
```

---

# When the build fails

It will, at least once. This config has never been evaluated.

**Read the error — it names the file and line.** The overwhelmingly likely
cause is an option that got renamed between nixpkgs versions.

```bash
# What is this option actually called now?
nixos-option services.foo.bar
man configuration.nix          # searchable, authoritative for your version

# Build without switching, to iterate fast
just build

# More detail on what blew up
just trace
```

`just` on its own lists every shortcut — `switch`, `test`, `status`, `logs`,
`failed`, `gc`, `check-vpn`, `check-tor`, `check-boot`.

**If nixpkgs 26.05 doesn't resolve**, edit `flake.nix` to use `nixos-25.11`.

**If a running system breaks:** reboot and pick an older generation from the
boot menu. That's the whole reason for `configurationLimit = 20`. Nothing you
do here is unrecoverable as long as you can reach that menu.

**Safer rebuild for anything touching networking** — reverts automatically if
you don't confirm:

```bash
sudo nixos-rebuild test --flake /etc/nixos#vault
```

Options I flagged as least certain, most likely to need adjusting:
`services.mainsail`, `services.kiwix-serve.zimPaths`, the `vpnNamespaces` API
in `downloads.nix`, and `services.spiderfoot`.

---

# Two things not in the config that matter

1. **NixOS must stay the default boot entry.** Check `bootctl status`. If
   Windows is default, an unattended reboot leaves the server down until you
   physically walk over to it.
2. **Secondary DNS on your devices.** Everything else degrades gracefully when
   the box is in Windows; DNS takes the whole network with it.
