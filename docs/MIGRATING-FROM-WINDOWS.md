# Getting your program list out of Windows

## The short answer

**`winget export`** is the smart tool you're asking about. It's built into
Windows 11, needs nothing installed, and produces machine-readable JSON:

```powershell
winget export -o packages.json
```

But it only knows about programs it can match to its catalog, which in practice
misses a lot — anything installed before winget existed, anything from a
downloaded `.exe`, Store apps, and your Steam library.

So `scripts/export-windows-programs.ps1` in this repo checks all four places
Windows keeps this information:

| Source | Catches | Misses |
|---|---|---|
| `winget export` | anything in winget's catalog | old installs, Store apps, games |
| Registry uninstall keys | **every classic installer** | Store apps, games |
| `Get-AppxPackage` | Store / UWP apps | everything else |
| Steam `appmanifest_*.acf` | your actual game library | non-Steam games |

Run it in PowerShell:

```powershell
cd path\to\nixserver\scripts
.\export-windows-programs.ps1
```

Output lands on your Desktop in `windows-programs\`:

```
winget.json            machine-readable, for winget itself
winget-list.txt        human-readable
installed-programs.csv the real list — every registry uninstall entry
store-apps.csv         Store / UWP
steam-games.csv        game library with app IDs
protondb-links.txt     one ProtonDB URL per game, ready to click through
```

That last file is the useful one for the gaming decision — it saves you looking
up 80 titles by hand.

## Then, on the NixOS side

```bash
./scripts/match-nixpkgs.sh installed-programs.csv > matches.md
```

This searches nixpkgs for each program name and reports exact hits, fuzzy
candidates, and misses. It's a first pass, not an answer — names differ across
ecosystems and a name match doesn't guarantee the same project. Eyeball it.

Better than either script for the ones you care about:

```bash
nix search nixpkgs firefox
```

or just search [search.nixos.org/packages](https://search.nixos.org/packages),
which is faster and shows descriptions.

## What actually transfers

Expect roughly three buckets.

**Same program, works identically.** Firefox, Chrome, VLC, OBS, Blender,
Krita, GIMP, Inkscape, Audacity, Discord, Signal, Steam, VS Code, Git,
Docker, most dev tooling, most open-source anything. Add to
`environment.systemPackages` and you're done.

**Different program, same job.** This is where most of the list lands:

| Windows | NixOS |
|---|---|
| Notepad++ | `vscodium`, `kate`, `gnome-text-editor` |
| 7-Zip / WinRAR | `p7zip`, `file-roller` (GUI) |
| Everything (search) | `fd`, `ripgrep` — already installed |
| WinDirStat | `ncdu` (TUI), `baobab` (GUI) |
| PuTTY | `openssh` — just `ssh` |
| WinSCP / FileZilla | `filezilla`, or `rsync` |
| Rufus / balenaEtcher | `dd`, `ventoy` |
| CPU-Z / HWiNFO | `lm_sensors`, `btop`, `nvtopPackages.amd` |
| MSI Afterburner | `lact`, `corectrl` (AMD overclocking) |
| Photoshop | `gimp`, `krita`, `photogimp` |
| MS Office | `libreoffice`, `onlyoffice-bin` |
| Adobe Reader | `zathura`, `evince`, `okular` |
| iTunes / MusicBee | Jellyfin, or `strawberry` |
| Task Manager | `btop`, `htop` |
| Device Manager | `lshw`, `pciutils`, `usbutils` |

**Doesn't exist on Linux, no real substitute.** Adobe CC (all of it), MS Office
proper, most anti-cheat games, PC Game Pass, iTunes, vendor RGB software
(OpenRGB covers some hardware), and anything with a hardware dongle. This is
why Windows stays on the machine.

## The NixOS way to think about it

Resist porting your Windows install one package at a time. Most of a Windows
program list is installers you ran once for a specific task and forgot.

Better approach: start from an empty `environment.systemPackages`, use the
machine for a week, and add things as you reach for them and find them missing.
The list you end up with will be a fraction of the CSV and will actually
reflect what you use.

For one-off tools, you don't even need to install:

```bash
nix run nixpkgs#cowsay -- hello        # run it, never install it
nix shell nixpkgs#ffmpeg nixpkgs#yt-dlp  # temp shell with both
```

Nothing is added to the system, nothing to clean up. This alone replaces a
large chunk of what a Windows program list is for.

## Where to put things

- **`environment.systemPackages`** in `modules/profiles/desktop.nix` — GUI apps
  for the desktop
- **`environment.systemPackages`** in `modules/profiles/base.nix` — CLI tools
  you want everywhere (ripgrep already lives here)
- **A service module** — anything that runs in the background; give it its own
  file under `modules/services/`
- **Nothing at all** — for one-offs, use `nix run`
