{ config, lib, pkgs, ... }:

let cfg = config.homelab.osint;
in
{
  options.homelab.osint.enable = lib.mkEnableOption "OSINT tooling (SpiderFoot + CLI tools)";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # Practical people-OSINT, i.e. the tools that are actually used rather
    # than the ones that look impressive in a screenshot.
    #
    # Two operational notes that matter more than the tool list:
    #
    # 1. These tools work by querying hundreds of third-party services. Every
    #    query is attributable to whatever IP made it. Run them as the
    #    `torified` group (see anonymity.nix) so that's a Tor exit and not
    #    your home connection:
    #
    #        tor-route on
    #        sg torified -c 'maigret someusername'
    #
    #    Note the tradeoff: many sites rate-limit or outright block Tor exits,
    #    so some modules will fail. The VPN namespace is the middle ground.
    #
    # 2. Results are unverified by construction — these aggregate public
    #    sources including stale and wrong ones. Username collisions across
    #    platforms are extremely common and are the single biggest source of
    #    false positives. Treat output as leads to confirm, not findings.
    #########################################################################

    # SpiderFoot: the one with a web UI. Automates ~200 modules over a target
    # (name, email, username, domain, IP) and graphs the relationships. This
    # is the closest practical thing to the "OSINT map" you described.
    services.spiderfoot = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 5001;
    };

    homelab.proxy.routes.osint = "127.0.0.1:5001";

    environment.systemPackages = with pkgs; [
      # --- people / accounts ------------------------------------------------
      maigret # username -> profiles across ~500 sites. best in class.
      sherlock # same idea, faster, narrower coverage
      holehe # email -> which sites have an account with it

      # --- documents and images --------------------------------------------
      exiftool # metadata: camera, GPS, software, timestamps
      # `exiftool -a -G1 file.jpg` is the one command worth memorising

      # --- infrastructure ---------------------------------------------------
      theharvester # emails, subdomains, hosts from public sources
      amass # attack-surface mapping
      subfinder # passive subdomain enumeration
      whois
      dnsutils
      nmap # yours, or with permission. not a passive tool.

      # --- archives and capture ---------------------------------------------
      monolith # freeze a page into one self-contained html file
      yt-dlp # archive video before it disappears
      wget # `wget -mkEpnp` for a whole-site mirror

      # --- glue -------------------------------------------------------------
      jq
      miller # csv/json wrangling, better than jq for tabular results
      python3
    ];

    #########################################################################
    # Worth knowing about, deliberately not installed:
    #
    #   recon-ng      capable framework, but most of its modules need paid API
    #                 keys to return anything. Sets up an evening of key
    #                 management for results the tools above give you free.
    #   phoneinfoga   phone-number OSINT. Coverage outside the US is poor and
    #                 the useful lookups are all paid.
    #   Maltego       the commercial standard. Community edition is heavily
    #                 limited and it isn't self-hostable in any real sense.
    #
    # Also: your SearXNG instance (knowledge.nix) has a JSON API. For search
    # sweeps across many engines at once without hitting any single one hard,
    # querying it is often more useful than a dedicated tool.
    #########################################################################

    # SpiderFoot scans can run for hours and write a lot; keep them off the
    # root filesystem.
    systemd.tmpfiles.rules = [
      "d ${config.homelab.dataDir}/files/osint 0750 root root -"
    ];
  };
}
