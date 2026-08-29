{ config, lib, pkgs, ... }:

let cfg = config.homelab.yubikey;
in
{
  options.homelab.yubikey = {
    enable = lib.mkEnableOption "YubiKey support (smartcard, FIDO2, OTP)";

    sudoUnlock = lib.mkEnableOption ''
      tapping the YubiKey instead of typing a password for sudo.

      READ THE WARNING IN THIS FILE FIRST. Misconfigured PAM locks you out of
      your own machine, and unlike a bad NixOS generation you cannot reboot
      your way past it.
    '';
  };

  config = lib.mkIf cfg.enable {
    #########################################################################
    # A YubiKey does four unrelated jobs. You probably want all four, but
    # they use different subsystems and fail independently:
    #
    #   FIDO2/WebAuthn   passwordless login to websites, and SSH keys that
    #                    physically cannot be copied off the key
    #   PIV/smartcard    certificates; needs pcscd running
    #   OpenPGP          GPG signing/encryption with the key as the card
    #   OTP              the touch-and-it-types-a-code thing; what Vaultwarden
    #                    accepts as a second factor
    #########################################################################

    # Smartcard daemon — PIV and OpenPGP both need it. Without pcscd running,
    # `ykman piv info` just reports no device and it looks like broken hardware.
    services.pcscd.enable = true;

    # udev rules so a non-root user can talk to the key at all. The single
    # most common "my YubiKey doesn't work on Linux" cause.
    services.udev.packages = with pkgs; [
      yubikey-personalization
      libfido2
    ];

    environment.systemPackages = with pkgs; [
      yubikey-manager # `ykman` — the tool you'll actually use
      yubikey-personalization # slot config, `ykpersonalize`
      yubico-piv-tool # PIV certificates
      yubioath-flutter # Yubico Authenticator (TOTP stored on the key)
      pam_u2f # for the sudo config below
      libfido2 # `fido2-token`, low-level
      age-plugin-yubikey # age encryption backed by the key — pairs with sops
    ];

    # GPG with the YubiKey as a smartcard.
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true; # SSH auth via the GPG key on the card
      pinentryPackage =
        if config.homelab.desktop.environment == "gnome"
        then pkgs.pinentry-gnome3
        else pkgs.pinentry-curses;
    };

    #########################################################################
    # SSH with a hardware-backed key — the best thing on this list
    #
    # Generate a key that lives ON the YubiKey and cannot be extracted:
    #
    #     ssh-keygen -t ed25519-sk -O resident -O verify-required
    #
    # The private half never exists on disk. Copying ~/.ssh gets an attacker
    # nothing; they need the physical key and your PIN. Put the .pub in
    # hosts/vault/default.nix alongside your existing key.
    #
    # KEEP A SECOND KEY IN THAT LIST. If the YubiKey is your only way in and
    # you lose it, you're reinstalling. Either a second YubiKey or a normal
    # key stored somewhere safe.
    #########################################################################

    #########################################################################
    # sudo by touch
    #
    # WARNING, and it's a real one: PAM misconfiguration locks you out with no
    # recovery path short of booting a live USB and editing the config. Unlike
    # a broken service, you can't fix this from the machine itself.
    #
    # Before enabling:
    #   1. Register the key:   mkdir -p ~/.config/Yubico
    #                          pamu2fcfg > ~/.config/Yubico/u2f_keys
    #   2. Register a SECOND key on the next line of that file:
    #                          pamu2fcfg -n >> ~/.config/Yubico/u2f_keys
    #   3. Keep a root shell open in another terminal while you test.
    #
    # `sufficient` rather than `required` below means the key is an
    # *alternative* to your password, not a replacement — lose the key and you
    # can still type the password. That's the safe configuration and the one
    # I'd stay on.
    #########################################################################
    security.pam = lib.mkIf cfg.sudoUnlock {
      u2f = {
        enable = true;
        settings.cue = true; # prints "touch your key" instead of hanging silently
        control = "sufficient";
      };
      services.sudo.u2fAuth = true;
    };

    #########################################################################
    # Also worth knowing:
    #
    #   Vaultwarden supports YubiKey OTP as a second factor — enable it in the
    #   web vault under Settings > Two-step Login once vaultwarden is up.
    #
    #   age-plugin-yubikey lets sops-nix secrets be encrypted to the YubiKey
    #   rather than a file on your laptop. Stronger, but it means you cannot
    #   edit secrets without the key present. Worth it once the setup is
    #   stable; do not do this during initial bring-up.
    #
    #   `ykman info` is the first command to run when something isn't working.
    #########################################################################
  };
}
