{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.maps;
  data = config.homelab.dataDir;
  mapDir = "${data}/files/maps";

  # Self-contained viewer. No CDN references — this has to work with the
  # internet unplugged, which is the entire point.
  viewer = pkgs.writeText "index.html" ''
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>maps</title>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <link rel="stylesheet" href="./vendor/maplibre-gl.css">
      <script src="./vendor/maplibre-gl.js"></script>
      <script src="./vendor/pmtiles.js"></script>
      <style>
        body { margin:0 } #map { position:absolute; inset:0 }
        #coords { position:absolute; bottom:0; right:0; z-index:1;
                  background:rgba(0,0,0,.6); color:#fff; padding:4px 8px;
                  font:12px/1.4 monospace }
      </style>
    </head>
    <body>
      <div id="map"></div><div id="coords"></div>
      <script>
        // Register the pmtiles:// protocol so MapLibre can range-request
        // straight into the single .pmtiles file Caddy is serving.
        const protocol = new pmtiles.Protocol();
        maplibregl.addProtocol("pmtiles", protocol.tile);

        const map = new maplibregl.Map({
          container: "map",
          // TODO: point at your basemap style. Protomaps ships styles at
          // https://github.com/protomaps/basemaps — vendor one as style.json.
          style: "./style.json",
          center: [-98.5, 39.8],
          zoom: 4,
          hash: true
        });
        map.addControl(new maplibregl.NavigationControl());
        map.addControl(new maplibregl.ScaleControl({ unit: "metric" }));
        map.addControl(new maplibregl.GeolocateControl({ trackUserLocation: true }));

        // Click to read off coordinates — the one thing you always end up
        // wanting from a self-hosted map.
        map.on("mousemove", e => {
          document.getElementById("coords").textContent =
            e.lngLat.lat.toFixed(5) + ", " + e.lngLat.lng.toFixed(5);
        });
      </script>
    </body>
    </html>
  '';

  # One-shot helper to pull the basemap and the viewer's JS. Run it once with
  # a network connection; after that the map works fully offline.
  fetchAssets = pkgs.writeShellApplication {
    name = "maps-fetch";
    runtimeInputs = with pkgs; [ pmtiles curl ];
    text = ''
      set -euo pipefail
      DIR="${mapDir}"
      mkdir -p "$DIR/vendor"

      # --- basemap -------------------------------------------------------
      # pmtiles slices a bounding box out of the hosted planet file WITHOUT
      # downloading all ~120GB of it — it range-requests only the tiles inside
      # your box. This is the feature that makes offline maps practical.
      if [ ! -f "$DIR/basemap.pmtiles" ]; then
        echo "==> extracting basemap for bbox ${cfg.bbox}"
        pmtiles extract \
          "${cfg.planetUrl}" \
          "$DIR/basemap.pmtiles" \
          --bbox="${cfg.bbox}" \
          --maxzoom=${toString cfg.maxZoom}
      fi

      # --- viewer libraries ----------------------------------------------
      cd "$DIR/vendor"
      [ -f maplibre-gl.js ]  || curl -fLO https://unpkg.com/maplibre-gl@4/dist/maplibre-gl.js
      [ -f maplibre-gl.css ] || curl -fLO https://unpkg.com/maplibre-gl@4/dist/maplibre-gl.css
      [ -f pmtiles.js ]      || curl -fL -o pmtiles.js https://unpkg.com/pmtiles@3/dist/pmtiles.js

      echo "==> done. basemap: $(du -h "$DIR/basemap.pmtiles" | cut -f1)"
      echo "    you still need a style.json — see protomaps/basemaps"
    '';
  };
in
{
  options.homelab.maps = {
    enable = lib.mkEnableOption "offline OpenStreetMap basemap + web viewer";

    bbox = lib.mkOption {
      type = lib.types.str;
      default = "-125.0,24.5,-66.9,49.4"; # continental US
      example = "-80.52,39.72,-75.24,42.52"; # Pennsylvania
      description = ''
        Area to extract, as west,south,east,north in decimal degrees.

        A single US state at maxZoom 14 lands somewhere between 150MB and 1.5GB
        depending on how dense it is — trivial next to your media library.

        Easiest way to get the numbers: draw a box at bboxfinder.com, or look
        the state up on Wikipedia (it lists extreme points), or:
          curl 'https://nominatim.openstreetmap.org/search?q=Pennsylvania&format=json' | jq '.[0].boundingbox'
        (note nominatim returns south,north,west,east — different order.)

        Pad it out a bit past the border. Nothing is worse than a map that
        stops exactly where you were driving to.
      '';
    };

    maxZoom = lib.mkOption {
      type = lib.types.int;
      default = 14;
      description = ''
        Deepest zoom level to include. This is the main size lever.
          12  city blocks visible, small file
          14  individual buildings — the sane default
          15+ roughly quadruples size per level for detail you rarely need
      '';
    };

    planetUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://build.protomaps.com/20240101.pmtiles";
      description = ''
        Protomaps planet build to slice from. These are dated and roll forward;
        check https://maps.protomaps.com/builds/ for the current one before
        your first extract. TODO: update this to a recent build.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    #########################################################################
    # You said: map system, offline maps, no TAK. So this is deliberately not
    # a TAK server — no CoT protocol, no unit tracking, no federation. It is
    # a map that works with the internet unplugged.
    #
    # Architecture is about as simple as self-hosting gets:
    #
    #   basemap.pmtiles   one file. the entire map of your region.
    #   Caddy             serves it. pmtiles uses HTTP range requests, so a
    #                     plain static file server is a complete tile backend.
    #                     no tile server, no database, no rendering pipeline.
    #   MapLibre          reads it directly in the browser.
    #
    # This replaces what would traditionally be PostGIS + osm2pgsql + a
    # renderer + a tile cache — days of import, hundreds of GB. Protomaps
    # collapses that into a file you can copy to a USB stick.
    #
    # Sizes, roughly: a US-wide extract is a few GB; a single state is in the
    # hundreds of MB; the whole planet is ~120GB if you ever want it.
    #########################################################################

    systemd.tmpfiles.rules = [
      "d ${mapDir}        0755 caddy caddy -"
      "d ${mapDir}/vendor 0755 caddy caddy -"
      "L+ ${mapDir}/index.html - - - - ${viewer}"
    ];

    services.caddy.virtualHosts."maps.${config.homelab.domain}".extraConfig = ''
      tls internal
      @denied not remote_ip 100.64.0.0/10 127.0.0.1/32
      respond @denied "not available here" 403

      root * ${mapDir}
      file_server browse

      # pmtiles is entirely dependent on range requests working.
      header /basemap.pmtiles Accept-Ranges bytes
      header /basemap.pmtiles Cache-Control "public, max-age=86400"
    '';

    environment.systemPackages = [
      fetchAssets
      pkgs.pmtiles
      pkgs.osmium-tool # slice/filter raw OSM data
      pkgs.gdal # reproject, convert, general geospatial swiss army knife
    ];

    #########################################################################
    # Setup, once:
    #
    #   sudo -u caddy maps-fetch          # edit the bbox in this file first
    #   # then grab a style.json from github.com/protomaps/basemaps
    #   # and drop it in ${mapDir}/
    #
    # Then https://maps.${config.homelab.domain} from anywhere on the tailnet.
    #
    #
    # If you want more than a basemap later, in rough order of effort:
    #
    #   routing     `valhalla` — turn-by-turn from an OSM extract. Hours to
    #               build tiles for a region, then fully offline.
    #   search      `nominatim` — geocoding. Postgres-backed, heavy; a
    #               country-sized import is an overnight job. `photon` is the
    #               lighter alternative if you only need forward search.
    #   queries     Overpass API — "every fire hydrant in this polygon".
    #               This is the one that overlaps your OSINT-mapping interest,
    #               and it's the heaviest of the three to self-host. Running
    #               `osmium` over a regional .osm.pbf answers most of the same
    #               questions without a server.
    #   imagery     satellite/aerial is the notable gap — there is no free
    #               bulk-downloadable global source. USGS NAIP covers the US
    #               at high resolution and is public domain.
    #
    # On your phone, offline: Organic Maps or OsmAnd both take OSM regions
    # directly and need nothing from this server. Worth having regardless as
    # the fallback when the server is what's unreachable.
    #########################################################################
  };
}
