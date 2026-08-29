# Server + PC + Game Pass, on one machine

You want four things from one box:

1. Services that are always up — DNS especially, since everything on your
   network depends on it
2. A PC you sit at and use
3. Game Pass, which you use heavily
4. Games on the TV, which already has Moonlight and Steam Link

Three of these are easy together. Game Pass is what makes it hard.

## The Game Pass problem

**PC Game Pass does not run on Linux.** The Xbox app uses MSIX/MSIXVC
packaging and the Xbox Gaming Runtime, and neither works under Proton. This is
not a "check ProtonDB" situation — it's the whole delivery platform, not
individual titles.

There is active work: the Heroic Games Launcher developers launched
[Xodus](https://www.gamingonlinux.com/2026/08/xbox-pc-and-game-pass-coming-to-linux-with-the-xodus-project/)
on 10 August 2026 to run GDK/Game Pass titles on Linux via a patched Proton
fork. As of now they have authentication, licence acquisition, and MSIXVC
decryption working — but **not end-to-end game execution**. It's a week old.
Worth watching, not worth planning around.

So my earlier suggestion — drop the dual boot, run everything under Proton —
doesn't survive contact with Game Pass. Retracting that. Here's the real menu.

---

## Option A — Dual boot (what you have now)

Windows and NixOS on the same disk, one at a time.

- **Works with Game Pass:** yes, natively
- **Server uptime:** ✗ everything goes down when you game
- **Cost:** free
- **Effort:** none, it's already set up

The killer is DNS. When this box is in Windows, every device configured to use
it stops resolving anything — that's the whole house, not just you. Jellyfin
and the rest degrade gracefully; DNS doesn't.

Mitigate by setting a **secondary DNS** on your devices (or in the Tailscale
admin console) so name resolution survives the box being down. That reduces
this from "the network breaks" to "some services are offline for a few hours",
which is genuinely tolerable.

**This is the sane starting point.** Get the server working, run it this way,
and only move to Option B if the downtime actually bothers you.

---

## Option B — Windows in a VM with the GPU passed through

NixOS runs permanently and owns the machine. Windows runs as a VM with the
6750 XT handed to it directly, so games get native performance. The server
never reboots.

- **Works with Game Pass:** yes — it's real Windows
- **Server uptime:** ✓ never goes down
- **Cost:** depends entirely on the question below
- **Effort:** a weekend, and a real one

### Answered: your CPU is an i7-12700KF, and the F means no integrated graphics

That settles it. Intel's `F` suffix means the iGPU is fused off, so the 6750 XT
is the only graphics device in the machine. Two ways forward:

**Buy a cheap second GPU (~$40-60 used).** A GT 1030, RX 550, or literally any
old card in a spare PCIe slot drives your GNOME desktop while the 6750 XT is
bound to `vfio-pci` and belongs to Windows permanently. Both run at the same
time — you can be working in GNOME while the Windows VM games. This is the
clean version and, combined with the NVMe you already need, it's the difference
between "a weekend project that works" and "a weekend project that fights you".

**Or single-GPU passthrough, free.** A script unbinds the GPU from the host,
hands it to the VM, and reverses it on shutdown. Your Linux desktop session
dies while Windows runs — but **every service keeps running**, because they're
all headless and don't care about the GPU. Jellyfin, DNS, Vaultwarden,
Tailscale: unaffected.

That's the key insight for your situation: single-GPU passthrough is a bad
deal on a workstation and a perfectly fine one on a server that occasionally
games. The thing it costs you — simultaneous Linux desktop and Windows — is
exactly the thing you already give up with dual boot. You're strictly better
off than now.

It is genuinely fiddly: IOMMU group separation, sometimes ROM patching, and a
bind/unbind hook script that has to be exactly right or you get a black screen
with no way to see why. Budget a weekend and don't do it first.

Good news on Alder Lake: IOMMU support on Z690/B660-class boards is solid, and
the 12700KF's PCIe topology usually puts the primary x16 slot in its own IOMMU
group, which is the thing that most often blocks passthrough.

### GPU contention, either way

The 6750 XT can't be in a Windows VM and transcoding Jellyfin at the same time.
With no iGPU to fall back on, your options are: let Jellyfin use CPU transcode
while you're gaming (the 12700KF has 20 threads — it'll cope with one or two
streams), or pre-transcode your library so it direct-plays and never needs a
GPU at all. The second is the real fix and is worth doing regardless.

If you buy the cheap second GPU, point Jellyfin's VAAPI at *that* one instead
and the problem disappears entirely — even a GT 1030 transcodes fine.

---

## Option C — Xbox Cloud Gaming

Game Pass Ultimate includes cloud streaming. It runs in a Chromium-based
browser, which means it runs on Linux, and it very likely runs **on your TV
directly** with no PC involved at all.

- **Works with Game Pass:** yes, for the cloud-eligible catalogue
- **Server uptime:** ✓ untouched
- **Cost:** free with your existing sub
- **Effort:** none

Costs: input latency noticeably worse than local, 1080p-class image quality,
compression artefacts in fast motion, and not every Game Pass title is
available for streaming.

Fine for single-player and turn-based. Not fine for anything competitive.

**Try this first, tonight, before building anything.** If your TV has the Xbox
app or a decent browser, you may find it covers more of your Game Pass usage
than you'd expect — and every hour it covers is an hour the server stays up.

---

## The TV, concretely

Your TV has both Moonlight and Steam Link, which covers every case:

| Playing | From | Use |
|---|---|---|
| Steam games on Linux | NixOS host | Steam Link, or Moonlight → Sunshine |
| Game Pass / any Windows game | Windows (bare metal or VM) | Steam Link, or Sunshine on Windows → Moonlight |
| Emulation (demanding) | NixOS host | Moonlight → Sunshine, launching ES-DE |
| Retro / casual | anywhere | RomM in the TV's browser |
| Game Pass, no PC at all | Microsoft's servers | Xbox app or browser on the TV |

Moonlight is the better protocol of the two — lower latency, HEVC support,
and it streams anything rather than just Steam. Use Steam Link as the fallback
when you can't be bothered to configure Sunshine.

**Wire the TV with ethernet.** A 4K60 stream is 40–50 Mbps sustained with zero
tolerance for jitter, and WiFi variance is precisely what streaming can't
absorb. If you can't run cable, MoCA over existing coax beats WiFi.

## Hardware reality check

| | |
|---|---|
| CPU | i7-12700KF — 8P+4E, 20 threads. Plenty. **No iGPU** (the `F`). |
| RAM | 32 GB. Fine for all of this simultaneously, including a Windows VM. |
| GPU | RX 6750 XT — the only display device in the box. |
| Disks | **Both ~98% full.** This blocks everything; see INSTALL-DUALBOOT.md. |

The disk situation is the actual blocker, not the GPU one. ~48 GB free across
two drives is not enough to install onto. Solve that first.

## DECIDED: Option A, dual boot

You're fine with the server being off occasionally, provided it recovers
cleanly on its own. That takes Option B off the table entirely — **the GPU
question is closed**, no passthrough, no second card needed.

It also moves the work: instead of engineering around downtime, the config
engineers for *clean recovery from* downtime. That's `modules/profiles/
resilience.nix` — persistent timers so missed backups and scrubs catch up,
services that retry rather than staying dead, a watchdog for hangs, persistent
logs, and Wake-on-LAN so you can power it back on without walking over.

Two things that live outside the config and matter more than anything in it:

1. **NixOS must stay the default systemd-boot entry.** If Windows is default,
   an unattended reboot leaves the server down until you're physically there.
   `bootctl status` to check.
2. **Set a secondary DNS** on your devices or in the Tailscale admin console.
   Everything else degrades gracefully when the box is off; DNS takes the
   whole network with it.

Option C (Xbox Cloud Gaming) is still worth trying — every hour it covers is
an hour you don't reboot at all — but it's now a convenience rather than part
of the architecture.
