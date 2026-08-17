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

### The question that decides everything: does your CPU have integrated graphics?

**If yes** (Ryzen with a `G` suffix — 5600G, 5700G, 8700G — or any Intel with
UHD/Iris graphics): this is straightforward. The iGPU drives your NixOS
desktop, the 6750 XT gets bound to `vfio-pci` at boot and belongs to Windows
permanently. Both run at once. You can be using GNOME while the Windows VM
games. This is the clean answer and I'd recommend it without hesitation.

**If no** (Ryzen 5600X, 5800X, 3600, any non-G Ryzen — which is the common
case): you need **single-GPU passthrough**. A script unbinds the GPU from the
host, hands it to the VM, and reverses it on shutdown. Your desktop session
dies while Windows is running — but **all your services keep running**,
because they're headless and don't care about the GPU.

That's the key insight: single-GPU passthrough is bad for a workstation and
perfectly fine for a server that occasionally games. Jellyfin, DNS, Vaultwarden
and everything else stay up. You just can't use the Linux desktop and Windows
at the same time.

It's fiddly to set up (IOMMU groups, ROM patching sometimes, a
bind/unbind script that has to be right) and can break on kernel updates.

**Or spend ~$50 on a used GPU.** Any GT 1030, RX 550, or similar in a second
slot drives the NixOS desktop and turns this back into the easy case. If your
CPU has no iGPU, this is by far the best money you can spend on this project.

### GPU contention, either way

The 6750 XT can't be in a Windows VM and transcoding Jellyfin at the same
time. In the iGPU case, point Jellyfin's VAAPI at the iGPU — it's plenty for
transcoding and this stops being a problem. In the single-GPU case, plan on
Jellyfin falling back to CPU transcode while you're gaming, or pre-transcode
your library so it direct-plays and never needs a GPU at all.

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

## What I'd actually do

**Now:** Option A + Option C. Dual boot as you already planned, set a secondary
DNS so the network survives it, and use cloud gaming on the TV for anything it
handles well. Zero extra work, zero extra cost. Get the server itself solid
first — that's the part with real value in it.

**Then, if the downtime annoys you:** check whether your CPU has an iGPU. If it
does, Option B is a weekend well spent. If it doesn't, buy a $50 GPU and then
do Option B.

**Skip:** single-GPU passthrough with no fallback display, unless you enjoy
that kind of thing for its own sake. The failure mode is a black screen with no
way to see what went wrong.

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

## Unanswered

**What CPU is it?** That single fact decides whether Option B is a clean
afternoon or a fiddly weekend, and it's the only thing standing between you and
a server that never goes down.
