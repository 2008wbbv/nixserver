# What actually runs on this box

Two different questions, so two lists: **services** (daemons running in the
background, reachable over the tailnet) and **apps** (things you launch when
sitting at the machine).

All service URLs are `https://<name>.lab.internal`, reachable **only from the
tailnet**. Nothing is exposed to the internet or even to your LAN.

This page is *what exists*. For *how to set each one up* after it starts, see
[CONFIGURE.md](CONFIGURE.md).

---

## Services

### Tier 1 — on from the start

| Service | URL | Port | What it does |
|---|---|---|---|
| **Tailscale** | — | 41641/udp | The only way in. Mesh VPN, exit node, subnet router. |
| **AdGuard Home** | — | 53 | Network-wide ad/tracker/malware blocking. Replaces Pi-hole. |
| **unbound** | — | 5335 | Recursive DNS resolver. Queries root servers directly so no third party sees your browsing. |
| **Caddy** | (all of them) | 80/443 | Reverse proxy. The single front door; everything else binds to loopback behind it. |
| **Prometheus** | `prometheus.` | 9090 | Metrics + alerting. |
| **Grafana** | `grafana.` | 3001 | Dashboards. |
| **Loki + Promtail** | — | 3100 | Searchable logs. Answers "why did that fail last Tuesday". |
| **sshd** | — | 22 | Tailnet-only. Key auth, no passwords. |

### Tier 2 — storage and daily use

| Service | URL | Port | What it does |
|---|---|---|---|
| **restic** | — | — | Encrypted offsite backups, nightly. **Do this before Vaultwarden.** |
| **Samba** | `\\vault\files` | 445 | SMB shares, tailnet-only, SMB3 minimum. |
| **Syncthing** | `sync.` | 8384 | Continuous file sync to laptop and phone. |
| **Vaultwarden** | `vault.` | 8222 | Bitwarden-compatible password manager. |
| **Jellyfin** | `jellyfin.` | 8096 | Movies, TV, **and music** — hardware transcode via the 6750 XT. |
| **Audiobookshelf** | `audiobooks.` | 8000 | Audiobooks and podcasts. |
| **Navidrome** *(off)* | `music.` | 4533 | Only if Jellyfin's music apps annoy you. |
| **SearXNG** | `search.` | 8888 | Metasearch, no logging, no profile. |
| **FreshRSS** | `rss.` | 8090 | RSS reader. |
| **Kiwix** | `wiki.` | 8081 | Offline Wikipedia and friends. |
| **Calibre-Web** | `library.` | 8083 | Ebook library. |

### Tier 3 — the rest

| Service | URL | Port | What it does |
|---|---|---|---|
| **Transmission** | `torrent.` | 9091 | Torrent client, locked inside a VPN network namespace. |
| **Tor** | — | 9050 | SOCKS proxy + `tor-route on/off` + SSH onion service. |
| **i2pd** | `i2p.` | 7070 | I2P router. Where anonymous torrenting belongs. |
| **Ollama** | — | 11434 | Local LLM inference. |
| **Open WebUI** | `chat.` | 8088 | ChatGPT-style frontend for it. |
| **Maps** | `maps.` | — | Offline OpenStreetMap of your state, served as one file. |
| **Synapse** | `matrix.` | 8008 | Matrix homeserver, federation off. |
| **Prosody** | — | 5222 | XMPP server. |
| **Forgejo** *(off)* | `git.` | 3002 | Self-hosted git — worth it to own this repo. |
| **Nextcloud** *(off)* | `cloud.` | 8091 | Only for CalDAV/CardDAV; Syncthing beats it for files. |
| **RomM** *(off)* | `roms.` | 8097 | Browser-playable ROM library. The only container here. |
| **Sunshine** *(off)* | `sunshine.` | 47989 | Game streaming to the TV's Moonlight client. |
| **Klipper + Moonraker + Mainsail** *(off)* | `printer.` | 7126 | 3D printer over USB, firewalled off the internet. |

### Always running, no UI

`systemd`, `nftables` (firewall), `fail2ban`, `smartd` (disk health),
`pcscd` (YubiKey smartcard), `zed` (ZFS event daemon), `pipewire` (audio),
`gdm` (login), `sops-nix` (secret decryption at boot).

---

## Desktop apps

Enabled via `homelab.apps.enable`.

| You wanted | You get | Notes |
|---|---|---|
| Apple Music | **Cider** | In nixpkgs. Cider Classic (1.x) — open source, uses Apple's real API. Needs your subscription. Cider 2.x is a separate paid product; start with this one. |
| Helium browser | **helium** *(off by default)* | **Not in nixpkgs** — the PR is still open and upstream ships only .deb. Comes from a community flake, so it updates on a stranger's schedule. Flip `homelab.apps.helium = true` if you want it; keep Firefox as the one you rely on. |
| Firefox | **firefox** | |
| — | **google-chrome** | Added deliberately: it bundles **Widevine**, which plain Chromium in nixpkgs doesn't. You need it for Apple Music's web player, Netflix, and Xbox Cloud Gaming. |
| Steam | **steam + Proton-GE** | Plus `protonup-qt`, `mangohud`, `gamescope`, `lutris`, `heroic`. Steam Remote Play is on, so your TV's Steam Link app works immediately with no Sunshine setup. |
| Roblox | **Sober** (Flatpak) | Native Roblox is **permanently blocked on Linux** — Hyperion/Byfron anti-cheat has detected and refused Wine/Proton since Feb 2024, and no Proton build fixes it. Sober runs the *Android* client instead, which sidesteps it. Only joins experiences that allow mobile/cross-platform play. The one Flatpak in this config. |
| Elegoo slicer | **orca-slicer** | ElegooSlicer isn't packaged. It's a *fork of OrcaSlicer*, which already ships Elegoo printer profiles — so this is the same program a generation upstream. If you need Elegoo's specific fork, `programs.appimage` is enabled: download their AppImage and run it directly. |
| Minecraft | **prismlauncher** | Microsoft accounts, instances, Fabric/Forge/NeoForge, one-click Modrinth and CurseForge modpacks. The maintained MultiMC/PolyMC continuation. |
| YubiKey | **full stack** | See below. |
| — | VLC, OBS, LibreOffice, Thunderbird, Signal, Discord, KeePassXC, VSCodium | |

### YubiKey specifically

It does four unrelated jobs and they fail independently:

| Job | Package | Note |
|---|---|---|
| Smartcard (PIV, OpenPGP) | `pcscd` service | **Without pcscd running, the key looks broken.** Most common Linux YubiKey problem. |
| Management | `yubikey-manager` (`ykman`) | `ykman info` is your first debugging command. |
| TOTP codes | `yubioath-flutter` | Codes stored on the key itself. |
| FIDO2 / WebAuthn | `libfido2` + udev rules | Website logins, and SSH keys that can't be copied off. |
| sudo by touch | `pam_u2f` *(off)* | **PAM lockout risk — read the module.** Configured as `sufficient`, so it's an alternative to your password, not a replacement. |

The best thing here is a hardware-backed SSH key:

```bash
ssh-keygen -t ed25519-sk -O resident -O verify-required
```

The private half never exists on disk. Copying `~/.ssh` gets an attacker
nothing — they'd need the physical key and your PIN. **Keep a second key in
`homelab.admin.sshKeys` as a fallback**, or losing the YubiKey means
reinstalling.

---

## What this doesn't do, deliberately

- **No email server.** Deferred by your call. It's the one item that can eat a
  weekend on its own.
- **No Matrix federation.** Federating means a publicly reachable server,
  which contradicts everything else here.
- **No public exposure of anything.** One deliberate exception: Sunshine's
  ports on the LAN when streaming is on, because that's the single workload
  where the tailnet's extra hop measurably costs you.
- **No Game Pass.** Doesn't run on Linux at all. That stays in Windows.
