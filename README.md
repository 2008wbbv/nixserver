# nixserver

One desktop PC, converted into a self-hosted server. Reachable over Tailscale
and nothing else.

**→ [SETUP.md](SETUP.md) is the step-by-step walkthrough. Start there.**

**Status: scaffold.** None of this has been built or evaluated — there is no
Nix toolchain in the environment it was written in. Expect to fix option names
and typos on the first `nixos-rebuild`. Everything marked `TODO` or `CHANGE-ME`
is a real blocker, not a nicety.

## Design, in one paragraph

There is no router, no managed switch, and no VLANs, so isolation is enforced
at the host instead: a default-deny firewall where `tailscale0` is the only
trusted interface, services bound to `127.0.0.1` with Caddy as the single
fan-out point, network namespaces for anything that talks to strangers, and
systemd sandboxing per unit. Nothing is exposed to the public internet and
nothing is exposed to the LAN. When you eventually buy a router and a managed
switch, VLANs slot in underneath all of this and none of it gets thrown away.

## Layout

```
SETUP.md                     the walkthrough — start here
flake.nix                    inputs + the single host output
.sops.yaml                   which keys can decrypt secrets
hosts/vault/
  default.nix                the manifest: what's on, what's off
  hardware-configuration.nix  PLACEHOLDER — generate on the real machine
  disks.nix                  declarative partitioning (destructive, opt-in)
modules/
  options.nix                shared settings (domain, dataDir, admin)
  profiles/                  base, hardening, amdgpu, storage, desktop,
                             resilience, apps, yubikey, power, shell
  services/                  one file per capability, each `homelab.<x>.enable`
secrets/README.md            how to set up sops
docs/
  INSTALL-DUALBOOT.md        disk space, partitioning, the Windows footguns
  GAMING-ARCHITECTURE.md     server + PC + Game Pass on one box
  MIGRATING-FROM-WINDOWS.md  exporting your program list, nixpkgs equivalents
  SERVICES.md                every service and app, what it is, what port
justfile                     `just` — every command you'll need
scripts/
  bootstrap.sh                 automates the install; run from the installer
  disk-report.ps1              what's eating your disks, and what to delete
  export-windows-programs.ps1  run this in Windows first
  match-nixpkgs.sh             then this against the CSV it produces
```

Turning a service on is one line in `hosts/vault/default.nix`. That file is
meant to read as the inventory of the box.

## Build order

Do not try to bring this up all at once. Each tier should be green and
committed before you start the next.

**Tier 0 — make room, then install.**
Read [docs/INSTALL-DUALBOOT.md](docs/INSTALL-DUALBOOT.md) first: both disks are
~98% full and nothing else can start until that's solved. It also covers the
three things to do in Windows *before* touching partitions. While you're still
booted into Windows, run `scripts/export-windows-programs.ps1` — it's much more
annoying to get that list afterwards. Then replace
`hosts/vault/hardware-configuration.nix` with the generated one, set
`networking.hostId`, add your SSH key.

**Tier 1 — get on the tailnet.**
`tailscale`, `dns`, `proxy`, `monitoring`. After this the box is reachable from
anywhere, resolving DNS through your own recursive resolver, with graphs.
Set up sops before this — Tailscale needs its auth key.

Then, in the Tailscale admin console: set this host's tailnet IP as the global
nameserver with **Override local DNS** on. That is how you get filtered DNS on
every device without owning a router — and it works away from home too, which
the router approach never would.

**Tier 2 — storage and daily use.**
`storage`, `files`, `vaultwarden`, `media`, `knowledge`. Turn on `backups`
before you put anything in Vaultwarden you can't afford to lose.

**Tier 3 — the rest.**
`downloads`, `anonymity`, `maps`, `osint`, `llm`, `comms`. Verify the VPN
namespace actually confines traffic, and that `tor-route test` shows two
different IPs, before relying on either.

**Tier 3b — landchad-flavoured extras.**
`selfhost.forgejo`, `selfhost.nextcloud`, `selfhost.website`.

**Tier 4 — needs hardware attached.**
`printer` (USB), `gaming` (dummy HDMI plug; the TV already has Moonlight and
Steam Link).

## Deploying

```
just switch     # rebuild and activate
just test       # activate, but auto-revert if you don't confirm
just build      # build only — fast iteration on errors
just trace      # with --show-trace
just status     # what's running, what failed
just logs jellyfin
just gc         # reclaim disk
```

`just` on its own lists the rest. Rollback is a reboot and a different boot
menu entry — that safety net is the main reason to run NixOS for this.

## Deliberate choices worth knowing about

- **AdGuard Home, not Pi-hole.** Pi-hole is a Docker appliance with mutable
  web-UI-driven state — the exact thing NixOS is for avoiding. Same UX,
  fully declarative, and it points at a local recursive `unbound` so no third
  party sees your query stream.
- **Torrenting is VPN-confined, and never touches Tor.** Tor is for browsing
  and the SSH onion service. I2P is where anonymous torrenting belongs.
- **The 3D printer is air-gapped by USB, not by VLAN.** Klipper's split
  architecture means the printer mainboard has no network interface in play
  at all. Stronger than the VLAN plan, and available today.
- **Tor routing is a toggle**, scoped to a `torified` group rather than the
  whole host — `tor-route on|off|test`. Whole-host transparent routing on a
  headless box you reach over Tailscale is how people lock themselves out.
- **The Klipper user is firewalled off from the internet.** Most "isolated
  printer" setups isolate the printer and then leave the host software free to
  phone home. Inbound from the tailnet still works.
- **Maps, not TAK.** A single Protomaps `.pmtiles` file served as a static
  file, read directly by MapLibre in the browser. No PostGIS, no osm2pgsql,
  no renderer, no tile cache — and it works with the internet unplugged.
- **Email is deferred** by your call — it's the one item that can eat a whole
  weekend on its own. Nothing here blocks adding it later.
- **Matrix federation is off**, because federating contradicts "nothing
  public". See the note in `modules/services/comms.nix` for the three ways out.
- **Game streaming is the one deliberate firewall hole.** Sunshine's ports are
  opened on the LAN because that's the single workload where the tailnet's
  extra hop and WireGuard encryption actually cost you. Set
  `homelab.gaming.lanStreaming = false` to force it over the tailnet instead.
- **RomM is the only container.** Everything else is a native NixOS module.
- **GNOME, not dwm.** You use this machine occasionally, and occasional-use
  machines want discoverable UIs rather than memorised keybindings. GNOME is
  also the closest thing to the macOS feel you described. Switch with one line:
  `homelab.desktop.environment = "plasma"`.
- **Vulkan, not ROCm, for inference.** See below — this one is a correction.
- **Built for a box that reboots, not one that never does.** Dual boot is the
  accepted arrangement, so `profiles/resilience.nix` makes "was powered off"
  the normal case: persistent timers catch up on missed work, services retry
  instead of staying dead, a watchdog handles hangs, and logs survive reboots.
  Alerts fire on *degraded after boot*, not on the reboot itself.

## Hardware

| | |
|---|---|
| CPU | i7-12700KF — Alder Lake, 8P+4E / 20 threads. **No iGPU** (the `F` suffix), which decides the GPU-passthrough question. |
| GPU | RX 6750 XT — RDNA2, gfx1031, 12GB, and the only display device in the box. Graphics stack is excellent; compute is not — see below. H.264/HEVC encode, **no AV1 encode** (RDNA3+ only). |
| RAM | 32GB. ZFS ARC capped at 8GB so it doesn't fight local inference. |
| Disks | Disk 0: 1TB, Windows, **30GB free**. Disk 1: 2TB, data, **18GB free**. |
| Boot | Dual-boots Windows — Game Pass makes that non-optional. |

> **Blocker: there is no room to install this yet.** ~48GB free across both
> disks, and you can't shrink a partition below its contents. Target ~600GB
> free (250GB is the bare minimum). Two ways there — delete unplayed games, or
> add a 2TB NVMe (~$100) so nothing existing gets touched. Run
> `scripts/disk-report.ps1` to see what's actually eating the space. There's
> also a suspicious 48.83GB partition mislabelled as an EFI System Partition on
> Disk 1 that's probably reclaimable.
> See [docs/INSTALL-DUALBOOT.md](docs/INSTALL-DUALBOOT.md).

Model sizing for 12GB: 8B at Q4 (~5GB) and 14B at Q4 (~9GB) stay GPU-resident.
32B needs ~18GB and will spill to system RAM, where it drops to single-digit
tokens/sec.

### GPU driver status — correcting an earlier claim

**Graphics: no caveats.** `amdgpu` is in-tree, Mesa RADV is mature on RDNA2,
and this is one of the best-supported cards on Linux for gaming and VAAPI
transcode.

**Compute: messier than I first said.** I described the
`HSA_OVERRIDE_GFX_VERSION=10.3.0` workaround as "standard and well-trodden,
not a hack that might break." That was overconfident. It *is* the standard
workaround — gfx1031 was never officially supported and the override borrows
gfx1030's code path — but there's an active regression: **ROCm 6.4.3 and later
segfault on gfx1031 the moment a model receives a prompt.** The reported fix is
pinning to ROCm 6.4.1.

So `homelab.amdgpu.computeBackend` now defaults to **`"vulkan"`**. llama.cpp's
Vulkan backend needs no ROCm, rides the same Mesa stack that's already there
for gaming, and doesn't care about AMD's support matrix. Slower than a working
ROCm setup; considerably faster than one that crashes. Set it to `"rocm"` if
you want to try — just verify with an actual prompt before building on it.

## On landchad.net

Good site; the service *selection* is worth mining. Two structural mismatches
to know about before following any of it literally:

- It targets a **public VPS with a real domain and open ports**. You chose
  tailnet-only, so the nginx/certbot/DNS half of most guides doesn't apply —
  Caddy and Tailscale cover it, with nothing exposed.
- It's **imperative** (`apt install`, edit `/etc/…`, `systemctl enable`).
  Doing that on NixOS fights the machine: your changes vanish on the next
  rebuild. Read the guides for *what* to run and why; take the *how* from the
  NixOS module.

Coverage against its list: RSS, SearXNG, Vaultwarden, Syncthing, Matrix, XMPP,
Tor hidden services and WireGuard were already here. Forgejo, Nextcloud and a
static site are now in `modules/services/selfhost.nix`. Email stays deferred.
Fediverse and PeerTube are skipped — both only make sense federated and public.

## Coming back from a reboot

The machine gets shut down into Windows regularly, so recovery is a design
requirement rather than an afterthought. What handles it:

| Concern | Handled by |
|---|---|
| Scheduled work missed while off | `Persistent = true` on every timer — runs shortly after next boot instead of silently skipping |
| Service fails once and stays dead | `Restart = on-failure` with backoff and a start limit |
| Started before the network was ready | ordering on `network-online.target` |
| Kernel hang with nobody present | hardware watchdog, 30s runtime / 10min reboot |
| "Why didn't it come up?" | persistent journald + a `boot-health-check` unit that logs failed units 2 min after boot |
| Powering it on remotely | Wake-on-LAN configured; enable it in BIOS too |
| Power blip leaves it off | BIOS "Restore on AC Power Loss" |

**The important one is not in the config:** make sure NixOS stays the default
systemd-boot entry. If Windows is default, any unattended reboot leaves the
server down until you walk over to it. Verify with `bootctl status`, and don't
press `d` in the boot menu with Windows selected.

**And set a secondary DNS** on your devices or in the Tailscale admin console.
DNS is the one service whose absence breaks the whole network rather than
degrading gracefully.

## Open questions

- **Which state?** `homelab.maps.bbox` still defaults to the whole continental
  US, which is ~10x more than you asked for. Draw the box at bboxfinder.com.
- **"Crypto"** — full node (`nix-bitcoin` is the strong answer), Monero, or
  just wallet storage? The only item from the original list still unaddressed.
- **Which state?** for `homelab.maps.bbox`.

