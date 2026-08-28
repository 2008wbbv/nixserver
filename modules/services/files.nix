{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.files;
  data = config.homelab.dataDir;
in
{
  options.homelab.files.enable = lib.mkEnableOption "Samba file shares + Syncthing";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # Samba
    #
    # SMB is a fine protocol on a trusted segment and a liability on an
    # untrusted one. With no VLANs yet, the mitigation is that it is NOT in
    # allowedTCPPorts — shares are reachable over the tailnet only, from
    # devices you have personally enrolled. That is a stronger boundary than
    # most home VLAN setups manage.
    #
    # SMB1 is off, signing is required, guest access is off.
    #########################################################################
    homelab.stack.groups.files = [ "samba-smbd" "syncthing" ];

    services.samba = {
      enable = true;
      openFirewall = false;
      settings = {
        global = {
          "server min protocol" = "SMB3";
          "client min protocol" = "SMB3";
          "server signing" = "mandatory";
          "restrict anonymous" = "2";
          "map to guest" = "never";
          "security" = "user";

          # Only listen on the tailnet interface.
          "interfaces" = "${config.homelab.tailnetInterface}";
          "bind interfaces only" = "yes";

          "server string" = "vault";
          "workgroup" = "WORKGROUP";
        };

        files = {
          path = "${data}/files";
          browseable = "yes";
          writable = "yes";
          "valid users" = config.homelab.admin.name;
          "create mask" = "0644";
          "directory mask" = "0755";
        };

        media = {
          path = "${data}/media";
          browseable = "yes";
          writable = "no"; # read-only; the *arr stack writes here
          "valid users" = config.homelab.admin.name;
        };
      };
    };

    # Samba keeps its own password database; set yours once after first boot:
    #   sudo smbpasswd -a <your-username>

    #########################################################################
    # Syncthing — continuous sync to laptop/phone. This is also the answer to
    # "KeePass" if you'd rather keep a .kdbx file than run Vaultwarden: the
    # database is encrypted at rest by KeePass itself, and Syncthing just moves
    # the file around. Fewer moving parts, no server to compromise.
    #########################################################################
    services.syncthing = {
      enable = true;
      user = config.homelab.admin.name;
      dataDir = "${data}/files/sync";
      configDir = "/var/lib/syncthing";
      guiAddress = "127.0.0.1:8384";
      openDefaultPorts = false; # tailnet only

      overrideDevices = true;
      overrideFolders = true;
      settings = {
        options = {
          urAccepted = -1; # no usage reporting
          globalAnnounceEnabled = false; # tailnet is enough; no public discovery
          relaysEnabled = false;
          natEnabled = false;
        };
        devices = {
          # TODO: add your devices. Get IDs from each client's UI.
          # laptop = { id = "XXXXXXX-..."; };
        };
        folders = {
          # documents = {
          #   path = "${data}/files/documents";
          #   devices = [ "laptop" ];
          #   versioning = { type = "simple"; params.keep = "10"; };
          # };
        };
      };
    };

    homelab.proxy.routes.sync = "127.0.0.1:8384";
  };
}
