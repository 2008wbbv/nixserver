# Secrets

`secrets/secrets.yaml` is **not** in this repo yet — it can't be, because it has
to be encrypted to keys that don't exist until you generate them.

## Why this exists at all

Everything in a Nix config ends up in `/nix/store`, which is world-readable by
every user and every process on the machine. A password written inline in a
`.nix` file is a password published to the whole system. sops-nix keeps secrets
encrypted at rest (safe to commit) and decrypts them into `/run/secrets/...`
at activation, owned by the right service user.

## Setup, in order

1. **Generate your admin key** (on your laptop, not the server):

   ```
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   age-keygen -y ~/.config/sops/age/keys.txt
   ```

   Back this key up somewhere you will still have it after a disk failure.
   Losing it means losing every secret in this repo.

2. **Install NixOS on the server first**, without any secrets. All the modules
   that need them are disabled by default, so a bare `tier 1` build works.

3. **Get the server's key** from its SSH host key:

   ```
   nix shell nixpkgs#ssh-to-age -c sh -c 'ssh-keyscan vault | ssh-to-age'
   ```

4. **Paste both public keys into `.sops.yaml`.**

5. **Create the file:**

   ```
   sops secrets/secrets.yaml
   ```

## Expected contents

Keys referenced by the modules in this repo, so `sops` complains at build time
rather than at 3am:

```yaml
tailscale:
    authkey: tskey-auth-...

wireguard:
    torrent: |
        [Interface]
        PrivateKey = ...
        Address = 10.x.x.x/32
        DNS = 10.64.0.1
        [Peer]
        PublicKey = ...
        AllowedIPs = 0.0.0.0/0,::0/0
        Endpoint = xxx.xxx.xxx.xxx:51820

vaultwarden:
    env: |
        ADMIN_TOKEN=...

restic:
    password: ...
    env: |
        B2_ACCOUNT_ID=...
        B2_ACCOUNT_KEY=...

searx:
    env: |
        SEARXNG_SECRET=...

freshrss:
    password: ...

murmur:
    env: |
        MURMUR_PASSWORD=...

nut:
    monitor-password: ...
```

Only the ones for modules you've enabled are actually required — sops-nix will
fail activation for a missing secret that a running service asked for.

## Rotating

Change the value with `sops secrets/secrets.yaml`, commit, rebuild. To add a new
machine's key, update `.sops.yaml` then `sops updatekeys secrets/secrets.yaml`.
