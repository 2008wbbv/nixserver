# nixserver

One desktop PC, converted into a self-hosted server. Reachable over Tailscale
and nothing else.

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
flake.nix                    inputs + the single host output
.sops.yaml                   which keys can decrypt secrets
hosts/vault/
  default.nix                the manifest: what's on, what's off
  hardware-configuration.nix  PLACEHOLDER — generate on the real machine
  disks.nix                  declarative partitioning (destructive, opt-in)
modules/
  options.nix                shared settings (domain, dataDir, admin)
  profiles/                  base, hardening, amdgpu, storage
  services/                  one file per capability, each `homelab.<x>.enable`
secrets/README.md            how to set up sops
```

Turning a service on is one line in `hosts/vault/default.nix`. That file is
meant to read as the inventory of the box.

## Build order

Do not try to bring this up all at once. Each tier should be green and
committed before you start the next.

**Tier 0 — install.**
Follow [docs/INSTALL-DUALBOOT.md](docs/INSTALL-DUALBOOT.md) — Windows stays,
shrunk, and there are three things to do in Windows *first* that are painful to
discover later. Replace `hosts/vault/hardware-configuration.nix` with the
generated one, set `networking.hostId`, add your SSH key.

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
`printer` (USB), `gaming` (dummy HDMI plug + a Moonlight client at the TV).

## Deploying

Single box, so build on the box:

```
sudo nixos-rebuild switch --flake .#vault
```

Safer, for anything that might break networking — reverts automatically if you
don't confirm within the timeout:

```
sudo nixos-rebuild test --flake .#vault
```

Rollback is a reboot and a different boot menu entry. That safety net is the
main reason to run NixOS for this rather than Debian and a pile of containers.

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

## Hardware

| | |
|---|---|
| GPU | RX 6750 XT — RDNA2, gfx1031, 12GB. ROCm needs `HSA_OVERRIDE_GFX_VERSION=10.3.0`, wired up in `profiles/amdgpu.nix`. H.264/HEVC encode; **no AV1 encode** (RDNA3+ only). |
| RAM | 33GB. ZFS ARC capped at 8GB so it doesn't fight Ollama for what spills out of VRAM. |
| Disks | 2. One for root, one for a single-vdev data pool — a mirror needs a third disk. Backups are carrying the redundancy load until then. |
| Boot | Dual-boots Windows (shrunk, kept for gaming). Disk 1 partitioned by hand; `disks.nix` is only safe to point at disk 2. See [docs/INSTALL-DUALBOOT.md](docs/INSTALL-DUALBOOT.md). |

Model sizing for 12GB: 8B at Q4 (~5GB) and 14B at Q4 (~9GB) stay GPU-resident.
32B needs ~18GB and will spill to system RAM, where it drops to single-digit
tokens/sec.

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

## Open questions

- **Which state?** `homelab.maps.bbox` still defaults to the whole continental
  US, which is ~10x more than you asked for. Draw the box at bboxfinder.com.
- **"Crypto"** — full node (`nix-bitcoin` is the strong answer), Monero, or
  just wallet storage? The only item from the original list still unaddressed.
- **Does your Proton library actually work?** Check protondb.com. If it does,
  drop the dual-boot and the server stops going down when you game.
- **Disk sizes** — needed to say how much to leave Windows and whether the data
  pool is worth ZFS at all.
