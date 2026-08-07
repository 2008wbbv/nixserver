{ config, lib, pkgs, ... }:

# "Super locked down networking" — without a router or managed switch.
#
# You can't do VLAN segmentation yet, so isolation has to come from the host
# instead. Four layers, in order of how much they actually buy you:
#
#   1. Default-deny inbound on the LAN NIC. The tailnet is the only trusted
#      interface. Nothing on your LAN — including a compromised smart TV —
#      can reach a single service on this box.
#   2. Services bind to 127.0.0.1. Even if a firewall rule is wrong, most
#      things are not listening on a routable address at all.
#   3. Network namespaces for anything that talks to strangers (torrent, Tor,
#      I2P). A kill-switch by construction, not by rule.
#   4. systemd sandboxing per unit, so a service compromise isn't a host
#      compromise.
#
# When you buy a router + managed switch, VLANs become layer 0 and none of this
# gets thrown away.

{
  networking = {
    # nftables backend; the legacy iptables one is on its way out.
    nftables.enable = true;

    firewall = {
      enable = true;

      # Deliberately empty. Every service is reached over the tailnet.
      # If you ever add a port here, write a comment saying why.
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];

      trustedInterfaces = [ config.homelab.tailnetInterface ];

      # Drop rather than reject: no "I'm here" replies to LAN scans.
      rejectPackets = false;
      logRefusedConnections = false; # too noisy to be useful; log drops selectively instead

      # Block outbound too? Not by default — too many services break in
      # confusing ways. The netns modules handle egress control where it matters.
    };

    # networkd instead of NetworkManager: declarative, and it won't rewrite
    # /etc/resolv.conf out from under our own resolver.
    networkmanager.enable = lib.mkDefault false;
    useNetworkd = true;
    useDHCP = false;
  };

  # Catch-all DHCP on wired interfaces. Without this the box has no network at
  # all once NetworkManager is off — check your NIC name with `ip link` and
  # narrow the match if this host ever grows a second interface.
  systemd.network = {
    enable = true;
    networks."10-wired" = {
      matchConfig.Name = "en* eth*";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # Sensible kernel-level network defaults.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.log_martians" = 1;

    # Don't advertise ourselves on the LAN more than necessary.
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
  };

  security = {
    # Lock down what unprivileged users can do.
    protectKernelImage = true;
    lockKernelModules = false; # true breaks ZFS/amdgpu late-loading; revisit later
    forcePageTableIsolation = true;

    # AppArmor is a cheap second opinion alongside systemd sandboxing.
    apparmor = {
      enable = true;
      killUnconfinedConfinables = false;
    };

    auditd.enable = true;
    audit = {
      enable = true;
      rules = [ "-a exit,always -F arch=b64 -S execve -k exec" ];
    };
  };

  # Brute-force protection on the one thing that does listen (SSH, tailnet-only).
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment.enable = true;
  };
}
