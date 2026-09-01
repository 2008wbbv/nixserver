{ config, lib, pkgs, ... }:

let cfg = config.homelab.osint;
in
{
  options.homelab.osint.enable = lib.mkEnableOption "OSINT tooling (SpiderFoot + CLI tools)";

  config = lib.mkIf cfg.enable {
    # Two things matter more than the tool list:
    #   1. Every query is attributable to the IP that made it. Run these as the
    #      `torified` group (anonymity.nix) so that's a Tor exit, not your
    #      house. Caveat: many sites block Tor exits, so the VPN namespace is
    #      often the better middle ground.
    #   2. Results are unverified aggregation. Username collisions across
    #      platforms are the dominant false positive. Leads, not findings.

    # SpiderFoot is NOT in nixpkgs — no NixOS module and no package, on any
    # branch. (An earlier version of this file assumed both; it was wrong.)
    # If you want its web UI, run it in a container or a uv/pipx venv and add
    # a homelab.proxy.routes entry by hand. The CLI tools below cover most of
    # what people actually use it for.

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

    # Not installed on purpose: recon-ng (most modules need paid API keys),
    # phoneinfoga (poor coverage outside the US). Your SearXNG instance has a
    # JSON API and is often more useful than either for broad sweeps.

    # SpiderFoot scans can run for hours and write a lot; keep them off the
    # root filesystem.
    systemd.tmpfiles.rules = [
      "d ${config.homelab.dataDir}/files/osint 0750 root root -"
    ];
  };
}
