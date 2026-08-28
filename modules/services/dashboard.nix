{ config, lib, pkgs, ... }:

# A landing page listing everything, because ~20 services at ~20 URLs is more
# than anyone remembers. Auto-populated from homelab.proxy.routes, so it can't
# drift out of sync with what's actually running.

let
  cfg = config.homelab.dashboard;
  inherit (config.homelab) domain;
  routes = config.homelab.proxy.routes;

  # Sort each route into a section. Anything unlisted lands in "other", so a
  # new service still shows up without touching this file.
  section = name:
    if builtins.elem name [ "jellyfin" "music" "audiobooks" "roms" ] then "Media"
    else if builtins.elem name [ "search" "rss" "wiki" "library" "maps" ] then "Knowledge"
    else if builtins.elem name [ "vault" "sync" "cloud" "git" ] then "Personal"
    else if builtins.elem name [ "chat" "matrix" "ntfy" ] then "Comms & AI"
    else if builtins.elem name [ "grafana" "prometheus" "sunshine" ] then "System"
    else if builtins.elem name [ "torrent" "i2p" "osint" "printer" ] then "Tools"
    else "Other";

  sections = lib.groupBy section (builtins.attrNames routes);

  page = pkgs.writeText "index.html" ''
    <!doctype html>
    <html lang="en"><head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>vault</title>
    <style>
      :root { color-scheme: dark; --bg:#0f1115; --fg:#e6e6e6; --dim:#8b93a1;
              --card:#171a21; --accent:#7fb069; --line:#242833; }
      * { box-sizing: border-box }
      body { margin:0; padding:2rem 1.25rem; background:var(--bg); color:var(--fg);
             font:15px/1.5 ui-sans-serif,system-ui,-apple-system,sans-serif }
      .wrap { max-width: 60rem; margin: 0 auto }
      h1 { font-size:1.05rem; font-weight:600; letter-spacing:.02em; margin:0 0 .25rem }
      .sub { color:var(--dim); font-size:.85rem; margin-bottom:2rem }
      h2 { font-size:.75rem; text-transform:uppercase; letter-spacing:.09em;
           color:var(--dim); font-weight:600; margin:2rem 0 .75rem;
           padding-bottom:.4rem; border-bottom:1px solid var(--line) }
      .grid { display:grid; gap:.6rem;
              grid-template-columns:repeat(auto-fill,minmax(11rem,1fr)) }
      a.card { display:block; padding:.8rem .9rem; background:var(--card);
               border:1px solid var(--line); border-radius:8px; color:var(--fg);
               text-decoration:none; transition:border-color .12s, transform .12s }
      a.card:hover { border-color:var(--accent); transform:translateY(-1px) }
      .name { font-weight:500 }
      .host { color:var(--dim); font-size:.75rem; margin-top:.15rem }
      footer { margin-top:3rem; color:var(--dim); font-size:.75rem }
      pre { color:var(--accent); font-size:.7rem; line-height:1.1; margin:0 0 1rem }
    </style></head><body><div class="wrap">
    <pre>${builtins.readFile ../profiles/assets/pine.txt}</pre>
    <h1>vault</h1>
    <div class="sub">tailnet only &middot; nothing here is reachable from the internet</div>
    ${lib.concatStrings (lib.mapAttrsToList (sec: names: ''
      <h2>${sec}</h2>
      <div class="grid">
      ${lib.concatMapStrings (n: ''
        <a class="card" href="https://${n}.${domain}">
          <div class="name">${n}</div>
          <div class="host">${n}.${domain}</div>
        </a>
      '') (lib.sort (a: b: a < b) names)}
      </div>
    '') sections)}
    <footer>generated from homelab.proxy.routes &middot; <code>stack</code> to start/stop groups</footer>
    </div></body></html>
  '';
in
{
  options.homelab.dashboard.enable =
    lib.mkEnableOption "a landing page listing every service" // { default = true; };

  config = lib.mkIf (cfg.enable && config.homelab.proxy.enable) {
    services.caddy.virtualHosts."home.${domain}".extraConfig = ''
      tls internal
      @denied not remote_ip 100.64.0.0/10 127.0.0.1/32
      respond @denied "not available here" 403
      root * ${pkgs.runCommand "dashboard" { } ''
        mkdir -p $out && cp ${page} $out/index.html
      ''}
      file_server
    '';
  };
}
