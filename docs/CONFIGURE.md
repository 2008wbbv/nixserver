# Configuring each service

What to do **after** a service builds and starts. Most need a first-run step
that can't be declared in Nix — an admin account, an API key, a library path.

Every service is at `https://<name>.lab.internal`, tailnet only.

**Convention throughout:** anything you set in the web UI is *mutable state*,
not in this repo, and is only preserved by backups. Anything in a `.nix` file
survives a reinstall. Where you have a choice, prefer the `.nix` file.

**Order matters once:** turn on `backups` before `vaultwarden`. Don't put your
only copy of a password into something that isn't backed up yet.

---

# Tier 1 — network

## Tailscale

```bash
sudo tailscale up --ssh --advertise-exit-node
```

Then in the [admin console](https://login.tailscale.com/admin/machines):

1. **Approve the exit node** — it's advertised but unusable until you do.
2. **Disable key expiry** for this machine. Otherwise it silently drops off the
   tailnet in ~6 months and you'll have no idea why nothing resolves.
3. **DNS → global nameserver** = this box's tailnet IP (`tailscale ip -4`),
   and turn on **Override local DNS**.

That last step is what gives every device filtered DNS everywhere, including
on cellular. It's the piece that replaces owning a router.

## AdGuard Home — `https://dns.lab.internal:3000`

First visit walks you through creating an admin account.

**The config in `modules/services/dns.nix` is authoritative** —
`mutableSettings = false` means anything you change in the web UI is
overwritten on the next rebuild. Change filters and upstreams in the Nix file,
not the UI. Use the UI for the query log and stats, which are the parts worth
having.

**Must do:** edit the two `rewrites` entries in `dns.nix`. They're
`127.0.0.1` placeholders; replace with your tailnet IP or `*.lab.internal`
won't resolve for anything but this machine.

Blocklists are OISD Big + AdGuard's own + phishing. That's a deliberate
middle ground — enough to matter, not so aggressive that sites break.

## unbound

Nothing to configure. It's a recursive resolver on `127.0.0.1:5335` that only
AdGuard talks to. Verify it's actually resolving recursively:

```bash
dig +dnssec nixos.org @127.0.0.1 -p 5335 | grep -i flags
```

Look for `ad` in the flags — that's DNSSEC validation working.

## Caddy

No manual configuration. Routes come from `homelab.proxy.routes`, which each
service module populates.

**One-time client step:** Caddy issues certs from its own CA, so every device
shows a warning. Fix it properly by installing the root cert:

```bash
sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

Install that on your laptop and phone once and every `*.lab.internal` name is
trusted. Alternatively buy a domain and switch to DNS-01 (see the comment in
`proxy.nix`) — that gets publicly-trusted certs with still no open ports.

## Grafana — `https://grafana.lab.internal`

Default login `admin` / `admin`; it forces a change on first login.

Prometheus and Loki are already wired up as data sources. Dashboards are not —
import these by ID under **Dashboards → New → Import**:

| ID | What |
|---|---|
| `1860` | Node Exporter Full — the one you'll actually use |
| `13639` | Loki logs |

Alert rules live in `monitoring.nix`, not the UI. They fire into ntfy.

---

# Tier 2 — storage and daily use

## ZFS storage

Before enabling, create the pool. `storage.nix` assumes it's called `tank`:

```bash
# Single disk (no redundancy — backups are doing that job)
sudo zpool create -o ashift=12 -O compression=zstd -O acltype=posixacl \
  -O xattr=sa -O mountpoint=none tank /dev/disk/by-id/<disk>

sudo zfs create -o mountpoint=/srv/media   tank/media
sudo zfs create -o mountpoint=/srv/files   tank/files
sudo zfs create -o mountpoint=/srv/backups tank/backups
```

Then `homelab.storage.enable = true` and rebuild.

**Check it survived reboot** before putting data on it: `zpool status`.

Adding a second disk later turns it into a mirror with no downtime and no
rebuild: `zpool attach tank <existing> <new>`.

## restic backups

Set the repository in `backups.nix` first — it's `CHANGE-ME` and will fail
loudly. Options:

```
b2:bucket-name:vault        Backblaze B2, ~$6/TB/month
sftp:user@rsync.net:vault   rsync.net
/mnt/usb-backup             external disk you rotate
```

Add `restic/password` and `restic/env` to sops (see `secrets/README.md`), set
`homelab.secrets.enable = true`, then enable backups.

**Then do the restore drill, before you rely on it:**

```bash
sudo restic-offsite snapshots
sudo restic-offsite restore latest --target /tmp/restore-test \
  --include /var/lib/vaultwarden
ls -la /tmp/restore-test/var/lib/vaultwarden
```

An unverified backup is a rumour. Ten minutes now, versus finding out during an
actual restore.

## Samba

Samba keeps its own password database, separate from your Linux account:

```bash
sudo smbpasswd -a <your-username>
```

Shares: `\\vault\files` (read-write) and `\\vault\media` (read-only — the
download stack writes there).

**Connect over the tailnet name**, not the LAN IP — SMB is bound to
`tailscale0` only. On macOS: `smb://vault`. On Windows: `\\vault`.

## Syncthing — `https://sync.lab.internal`

The Nix config sets `overrideDevices` and `overrideFolders` to **true**, which
means devices and folders added through the web UI are **wiped on the next
rebuild**. That's deliberate — it keeps the topology in the repo — but it
surprises people.

So add devices in `files.nix`, not the UI:

```nix
settings.devices.laptop.id = "XXXXXXX-XXXXXXX-...";
settings.folders.documents = {
  path = "/srv/files/documents";
  devices = [ "laptop" ];
  versioning = { type = "simple"; params.keep = "10"; };
};
```

Get each device's ID from its own Syncthing UI under **Actions → Show ID**.

Global discovery and relays are **off** — devices find each other over the
tailnet. That means a device not on your tailnet won't sync.

## Vaultwarden — `https://vault.lab.internal`

`SIGNUPS_ALLOWED = false`, so create your account differently: temporarily set
it to `true`, rebuild, register, set it back to `false`, rebuild. Two rebuilds
but no window where anyone else could register.

**Do backups first.** This is the one service whose loss is unrecoverable.

Clients: the official Bitwarden apps and browser extensions all work — set the
server URL to `https://vault.lab.internal` in the app's settings before
logging in. **Your phone must be on the tailnet** for the vault to sync.

`ADMIN_TOKEN` in sops unlocks `/admin` for user management and diagnostics.

## Jellyfin — `https://jellyfin.lab.internal`

Setup wizard on first visit. Point libraries at:

```
/srv/media/movies
/srv/media/tv
/srv/media/music
```

**Then enable hardware transcoding** — it's off by default and the whole
reason the GPU is in the machine:

Dashboard → Playback → Transcoding → **VAAPI**, device `/dev/dri/renderD128`.

Enable H.264 and HEVC. **Do not enable AV1 encode** — your RDNA2 card can't do
it (decode only, encode landed with RDNA3) and Jellyfin will silently fall back
to CPU while looking like it's working.

Verify it's actually using the GPU during a transcode:

```bash
radeontop
```

## Audiobookshelf — `https://audiobooks.lab.internal`

First visit creates the root account. Libraries at `/srv/media/books`. Podcasts
are a separate library type — add both if you want them.

---

# Tier 3

## SearXNG — `https://search.lab.internal`

Generate the secret and put it in sops as `searx/env`:

```bash
echo "SEARXNG_SECRET=$(openssl rand -hex 32)"
```

No account, no per-user state. Set it as your browser's default search engine —
in Firefox, visit it once, then right-click the address bar → **Add search
engine**.

It has a JSON API, which makes it more useful than it looks:

```bash
curl 'https://search.lab.internal/search?q=test&format=json'
```

## FreshRSS — `https://rss.lab.internal`

Admin user comes from `homelab.admin.name` with the password in sops as
`freshrss/password`.

Import an OPML from your current reader under **Subscription management →
Import/Export**. Mobile clients speaking the Fever or Google Reader API work —
enable that under **Profile → API management** first.

## Kiwix — `https://wiki.lab.internal`

**Download content first** — the service has nothing to serve otherwise. From
<https://download.kiwix.org/zim/> into `/srv/files/zim/`:

| File | Size |
|---|---|
| `wikipedia_en_simple_all_maxi` | ~10 GB — good starting point |
| `wikipedia_en_all_nopic` | ~50 GB — full text, no images |
| `wikipedia_en_all_maxi` | ~110 GB — everything |

Also worth having: Wiktionary, Project Gutenberg, Stack Exchange, iFixit,
WikiMed.

**kiwix-serve does not scan a directory** — each file has to be listed. Add
them in `hosts/vault/default.nix`:

```nix
homelab.knowledge.zimFiles = {
  wikipedia  = "/srv/files/zim/wikipedia_en_simple_all_maxi.zim";
  wiktionary = "/srv/files/zim/wiktionary_en_all_nopic.zim";
};
```

The attribute name becomes the URL segment. For a big collection, build a
`library.xml` with `kiwix-manage` and set `services.kiwix-serve.libraryPath`
instead.

## Calibre-Web — `https://library.lab.internal`

Needs an **existing Calibre library** — it reads `metadata.db`, it doesn't
create one. Make it first with desktop Calibre, or:

```bash
calibredb add --with-library /srv/media/books /path/to/book.epub
```

Default login is `admin` / `admin123`. Change it immediately.

## Maps — `https://maps.lab.internal`

```bash
# Set your state's bbox in hosts/vault/default.nix first
sudo -u caddy maps-fetch
```

Get the bbox from [bboxfinder.com](http://bboxfinder.com) — draw a box, read
off `west,south,east,north`. Pad past the border; a map that stops where you
were driving is worse than useless.

You also need a `style.json` — grab one from
[protomaps/basemaps](https://github.com/protomaps/basemaps) and drop it in
`/srv/files/maps/`.

## Ollama + Open WebUI — `https://chat.lab.internal`

First visit creates the admin account. **The first account created is the
admin**, so do this before anyone else can reach it.

Models are pulled at activation. Add more:

```bash
ollama pull qwen3:14b
ollama list
```

Stay at or under 14B at Q4 — that's ~9 GB and fits in the 6750 XT's 12 GB. A
32B needs ~18 GB and will spill into system RAM, dropping to single-digit
tokens/sec.

**On the Vulkan backend** (the default), Ollama itself is unaccelerated and
llama.cpp does the GPU work:

```bash
llama-server -m ~/models/model.gguf -ngl 99 --host 127.0.0.1 --port 8090
```

`-ngl 99` offloads every layer. See the note in `amdgpu.nix` for why ROCm isn't
the default.

## Torrenting

The WireGuard config from your VPN provider goes into sops as
`wireguard/torrent`, whole file including the `[Interface]` block.

**Verify the confinement before using it. Do not skip this:**

```bash
just check-vpn
```

The two addresses must differ. If they match, traffic is leaking and the
namespace isn't doing its job.

Transmission's password: set `rpc-password` to plaintext once, start it, then
copy the salted hash it writes into `settings.json` back into `downloads.nix`,
or every rebuild resets it.

## Tor + I2P

```bash
tor-route on      # transparent routing for the `torified` group
tor-route test    # the two IPs must differ
tor-route off
```

Opt a process in by running it as that group:

```bash
sg torified -c 'curl https://check.torproject.org'
```

Your SSH onion address, after first boot:

```bash
sudo cat /var/lib/tor/onion/ssh/hostname
```

Write it down somewhere offline. It's how you get back in if Tailscale breaks
and you're behind hostile NAT.

I2P console at `https://i2p.lab.internal`. Give it 10–20 minutes to integrate
into the network on first start — it looks broken before then and isn't.

## OSINT

**There is no SpiderFoot here.** It has no NixOS module and no nixpkgs package
on any branch — an earlier version of this repo assumed both and was wrong. If
you want its web UI, run it in a container or a `uv`/`pipx` venv and add a
`homelab.proxy.routes` entry by hand.

The CLI tools cover most of what it's actually used for. Run them torified so queries aren't attributable to your house:

```bash
tor-route on
sg torified -c 'maigret someusername'
```

Many sites block Tor exits, so the VPN namespace is often the better middle
ground. And treat every result as a lead — username collisions across platforms
are the dominant false positive.

## Matrix + XMPP

Create your Matrix user after first boot:

```bash
sudo -u matrix-synapse register_new_matrix_user \
  -c /var/lib/matrix-synapse/homeserver.yaml http://127.0.0.1:8008
```

Point Element (or any client) at `https://matrix.lab.internal`.

**Federation is off.** Only people on your tailnet can use this. Turning it on
means a publicly reachable server, which is a different architecture — see the
note in `comms.nix`.

Prosody (XMPP) users:

```bash
sudo prosodyctl adduser you@lab.internal
```

Prosody needs a TLS cert; the paths in `comms.nix` point at Caddy's internal CA
and are marked TODO. Verify them after Caddy's first run.

---

# Desktop and gaming

## Steam

Nothing to configure — it's installed and Remote Play is on, so the TV's Steam
Link app works immediately.

For a game that misbehaves: **Properties → Compatibility → Force Proton-GE**.
Manage GE versions with `protonup-qt`.

Check ProtonDB before assuming a title works. Anything with kernel-level
anti-cheat that hasn't opted into Proton won't run, ever.

## Roblox (Sober)

Native Roblox does not run on Linux and won't. Hyperion (Byfron) anti-cheat
has actively blocked Wine and Proton since February 2024 — this isn't a
Proton version problem and no launch option fixes it.

Sober runs the **Android** build instead, sidestepping Hyperion. After the
rebuild that enables it:

```bash
flatpak install flathub org.vinegarhq.Sober
```

Then launch it from your app menu and log in normally.

**The catch:** it's the mobile client, so you can only join experiences that
allow cross-platform/mobile play. PC-exclusive ones won't show up. That's
inherent to the approach, not a bug in the setup.

FFlags, if you want them, live at
`~/.var/app/org.vinegarhq.Sober/config/sober/config.json`.

## Sunshine — `https://sunshine.lab.internal`

**Plug in the dummy HDMI adapter first.** Sunshine captures a display, and the
GPU won't initialise an output with nothing attached.

First visit sets a username and password. Then on the TV, open Moonlight, add
this host, and enter the PIN Moonlight shows into Sunshine's **PIN** tab.

Wire the TV with ethernet. 4K60 is 40–50 Mbps sustained with no tolerance for
jitter — precisely what WiFi can't provide.

## 3D printer

`printer.cfg` is printer-specific and can't be guessed. Start from the sample
for your machine in the
[Klipper config repo](https://github.com/Klipper3d/klipper/tree/master/config),
then set the MCU serial:

```bash
ls /dev/serial/by-id/
```

Mainsail at `https://printer.lab.internal`.

**The klipper user is firewalled off from the internet**, so Moonraker's update
manager can't work — that's intentional. Updates come from rebuilding this
flake.

---

# Where state lives

Anything not in this repo. Which is why backups cover these paths:

| Service | State |
|---|---|
| Vaultwarden | `/var/lib/vaultwarden` — **irreplaceable** |
| Jellyfin | `/var/lib/jellyfin` — watch history, users |
| AdGuard | `/var/lib/AdGuardHome` — query log only; config is in Nix |
| Syncthing | `/var/lib/syncthing` — device keys |
| Grafana | `/var/lib/grafana` — dashboards you imported |
| Forgejo | `/var/lib/forgejo` |
| Matrix | `/var/lib/matrix-synapse` + postgres |
| Media | `/srv/media` — re-downloadable, deliberately not backed up |

# When something's wrong

```bash
doctor                      # failed units, network, disk, backups, boot entry
just logs <service>         # last 100 lines
just failed                 # everything that errored since boot
stack                       # what's running
systemctl status <unit>
```

Nine times out of ten the answer is in `just logs`. The tenth is DNS.
