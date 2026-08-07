{ config, lib, pkgs, ... }:

let cfg = config.homelab.monitoring;
in
{
  options.homelab.monitoring.enable = lib.mkEnableOption "Prometheus + Grafana + Loki";

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9090;
      retentionTime = "90d";

      exporters = {
        node = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = 9100;
          enabledCollectors = [ "systemd" "processes" "interrupts" ];
        };
        smartctl = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = 9633;
        };
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
        }
        {
          job_name = "smartctl";
          static_configs = [{ targets = [ "127.0.0.1:9633" ]; }];
        }
      ] ++ lib.optional config.homelab.ups.enable {
        job_name = "ups";
        static_configs = [{ targets = [ "127.0.0.1:9199" ]; }];
      };

      # The alerts that would actually have saved you, on a single-box setup.
      rules = [
        (builtins.toJSON {
          groups = [{
            name = "vault";
            rules = [
              {
                alert = "DiskWillFillIn24h";
                expr = ''predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"}[6h], 24*3600) < 0'';
                for = "1h";
                labels.severity = "warning";
              }
              {
                alert = "DiskSpaceLow";
                expr = ''node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes < 0.10'';
                for = "15m";
                labels.severity = "critical";
              }
              {
                alert = "SmartFailurePredicted";
                expr = ''smartctl_device_smart_status == 0'';
                for = "5m";
                labels.severity = "critical";
              }
              {
                alert = "ServiceFailed";
                expr = ''node_systemd_unit_state{state="failed"} == 1'';
                for = "5m";
                labels.severity = "warning";
              }
              {
                alert = "HostRebooted";
                expr = ''time() - node_boot_time_seconds < 300'';
                labels.severity = "info";
              }
            ];
          }];
        })
      ];
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3001;
          domain = "grafana.${config.homelab.domain}";
          root_url = "https://grafana.${config.homelab.domain}";
        };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
        "auth.anonymous".enabled = false;
      };

      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://127.0.0.1:3100";
          }
        ];
      };
    };

    # Loki + Promtail: searchable logs. On one box this is arguably overkill
    # versus journalctl, but it's what makes "why did that fail last Tuesday"
    # answerable.
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 3100;
        };
        common = {
          ring.kvstore.store = "inmemory";
          replication_factor = 1;
          path_prefix = "/var/lib/loki";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
        };
        schema_config.configs = [{
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = { prefix = "index_"; period = "24h"; };
        }];
        limits_config.retention_period = "30d";
      };
    };

    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        clients = [{ url = "http://127.0.0.1:3100/loki/api/v1/push"; }];
        scrape_configs = [{
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = { job = "systemd-journal"; host = config.networking.hostName; };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }];
      };
    };

    homelab.proxy.routes = {
      grafana = "127.0.0.1:3001";
      prometheus = "127.0.0.1:9090";
    };
  };
}
