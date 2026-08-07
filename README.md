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
Boot the NixOS installer, partition (by hand, or with `disks.nix` if you're
wiping the disk), install, reboot. Replace
`hosts/vault/hardware-configuration.nix` with the generated one. Set
`networking.hostId`. Add your SSH key to `hosts/vault/default.nix`.

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
`downloads`, `anonymity`, `llm`, `amdgpu`. Verify the VPN namespace actually
confines traffic (commands are in `modules/services/downloads.nix`) before
you use it for anything.

**Tier 4 — hardware you don't own yet.**
`printer`, `ups`, `comms`.

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
- **Email is deferred** by your call — it's the one item that can eat a whole
  weekend on its own. Nothing here blocks adding it later.
- **Matrix federation is off**, because federating contradicts "nothing
  public". See the note in `modules/services/comms.nix` for the three ways out.

## Open questions

Still unresolved from the original list:

- **"Radar"** — assumed Radarr. If you meant ADS-B aircraft tracking
  (`readsb`/`tar1090` + an RTL-SDR dongle), that's a separate module.
- **"Land chad"** — landchad.net-style self-hosting, or LanCache?
- **"Crypto"** — full node (`nix-bitcoin` is the strong answer), Monero, or
  just wallet storage?
- **"OSINT networking map"** — inventory of your own gear (NetBox), or OSINT
  tooling (SpiderFoot etc.)?
- **TAK** — no native module; FreeTAKServer or `taky` in a container. Also
  worth deciding whether it needs to be reachable from outside the tailnet,
  because that changes the exposure model.
- **Hardware specifics** — GPU model (determines the ROCm gfx override), disk
  count and sizes (determines whether ZFS is worth it), RAM, and whether this
  machine is staying dual-boot with Windows.
