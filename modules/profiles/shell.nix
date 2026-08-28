{ config, lib, pkgs, ... }:

# Shell environment: zsh + starship + fastfetch, matching what you already run.

let
  cfg = config.homelab.shell;

  fastfetchConfig = pkgs.writeText "fastfetch.jsonc" (builtins.toJSON {
    "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
    logo = {
      source = "${./assets/pine.txt}";
      type = "file";
      padding = { top = 1; left = 2; };
      color = { "1" = "green"; };
    };
    display.separator = "  ";
    modules = [
      "break"
      { type = "title"; format = "{user-name}@{host-name}"; }
      { type = "separator"; string = "─"; }
      { type = "os"; key = "  os"; }
      { type = "kernel"; key = "  kernel"; }
      { type = "uptime"; key = "  uptime"; }
      { type = "packages"; key = "  pkgs"; }
      { type = "shell"; key = "  shell"; }
      { type = "terminal"; key = "  term"; }
      { type = "wm"; key = "  wm"; }
      "break"
      { type = "cpu"; key = "  cpu"; }
      { type = "gpu"; key = "  gpu"; }
      { type = "memory"; key = "  mem"; }
      { type = "disk"; key = "  disk"; folders = "/"; }
      "break"
      { type = "localip"; key = "  lan"; compact = true; }
      { type = "command"; key = "  tailnet"; text = "tailscale ip -4 2>/dev/null || echo offline"; }
      "break"
      { type = "colors"; symbol = "circle"; }
    ];
  });
in
{
  options.homelab.shell.enable =
    lib.mkEnableOption "zsh + starship + fastfetch" // { default = true; };

  config = lib.mkIf cfg.enable {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      histSize = 10000;

      # vi keybindings, matching your existing setup.
      interactiveShellInit = ''
        bindkey -v
        export KEYTIMEOUT=1

        # Cursor shape follows vi mode.
        function zle-keymap-select {
          case $KEYMAP in
            vicmd) echo -ne '\e[1 q';;
            viins|main) echo -ne '\e[5 q';;
          esac
        }
        zle -N zle-keymap-select
        echo -ne '\e[5 q'
      '';

      shellAliases = {
        ls = "eza --group-directories-first";
        ll = "eza -l --group-directories-first --git";
        la = "eza -la --group-directories-first --git";
        tree = "eza --tree";
        cat = "bat --paging=never";
        grep = "rg";
        df = "duf";
        du = "dust";
        top = "btop";

        # The three you'll type most.
        rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#vault";
        rebuild-test = "sudo nixos-rebuild test --flake /etc/nixos#vault";
        services = "systemctl list-units --type=service --state=running";
      };
    };

    users.defaultUserShell = pkgs.zsh;

    programs.starship = {
      enable = true;
      settings = {
        add_newline = false;
        format = "$directory$git_branch$git_status$nix_shell$character";
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          vimcmd_symbol = "[❮](bold yellow)";
        };
        directory.truncation_length = 3;
        nix_shell.format = "[$symbol]($style) ";
        nix_shell.symbol = "❄";
      };
    };

    environment.systemPackages = with pkgs; [
      fastfetch
      eza
      bat
      duf
      dust
      fzf
      zoxide
      neovim
    ];

    environment.variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      FASTFETCH_CONFIG = "${fastfetchConfig}";
    };

    # `fastfetch` picks up the config without needing the env var set.
    environment.etc."xdg/fastfetch/config.jsonc".source = fastfetchConfig;
  };
}
