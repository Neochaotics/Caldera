{
  description = "CalderaRIP with dock and API";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      versions = {
        caldera-rest-api = "2.1.0";
        calderarip = "18.2.0";
        calderadock = "3.15.0";
      };

      caldera-rest-api-deb = pkgs.fetchurl {
        url = "https://caldera-mirror.s3.eu-central-1.amazonaws.com/caldera-rest-api/caldera-rest-api-${versions.caldera-rest-api}-linux-x86_64.deb";
        sha256 = "sha256-AuXCFKQ4wJvmaE2NJpsPMDmXBV0BoHn3jQ+vgkNmw/A=";
      };

      calderarip-iso = pkgs.fetchurl {
        url = "https://caldera-mirror.s3.eu-central-1.amazonaws.com/ISO/CalderaRIP-v${versions.calderarip}-light.iso";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };

      calderadock-deb = pkgs.fetchurl {
        url = "https://caldera-mirror.s3.eu-central-1.amazonaws.com/calderadock/calderadock-v${versions.calderadock}-installer-linux.deb";
        sha256 = "sha256-fM5O8NWEcl5HcDcoUL/sivscVMZxYVq7Pq+JMryuwEw=";
      };

      extractDeb =
        name: version: src:
        pkgs.stdenv.mkDerivation {
          inherit src version;
          pname = "${name}-extracted";
          nativeBuildInputs = [ pkgs.dpkg ];
          unpackPhase = ''
            echo "Extracting $src..."
            dpkg-deb -x $src .
          '';
          installPhase = ''
            mkdir -p $out
            cp -r * $out/
          '';
        };

      calderaAPIExtracted = extractDeb "caldera-rest-api" versions.caldera-rest-api caldera-rest-api-deb;

      calderaRestApi = pkgs.buildFHSEnv {
        name = "caldera-rest-api";
        runtimeInputs = [
          pkgs.glibc
          pkgs.gcc.libstdcxx
        ];
        extraBuildCommands = ''
          ln -s ${calderaAPIExtracted}/opt $out/opt
          ln -s ${calderaAPIExtracted}/lib $out/lib
        '';
        runScript = "/opt/caldera-rest-api/caldera-rest-api";
      };

      calderadockExtracted = extractDeb "calderadock" versions.calderadock calderadock-deb;

      calderadock = pkgs.buildFHSEnv {
        name = "calderadock";
        version = versions.calderadock;
        targetPkgs =
          pkgs: with pkgs; [
            alsa-lib
            at-spi2-atk
            at-spi2-core
            atk
            bash
            brotli
            bzip2
            cairo
            coreutils
            cups
            dbus
            eudev
            expat
            fontconfig
            freetype
            gcc-unwrapped.lib
            gdk-pixbuf
            glib
            glibc
            gnutls
            gobject-introspection
            gtk3
            json-glib
            libdrm
            libffi
            libgbm
            libnotify
            libpng
            libsecret
            sqlite
            libusb1
            libuuid
            libxcursor
            libxkbcommon
            libxml2
            libappindicator-gtk3
            mesa
            nspr
            nss
            openssl
            pango
            pcre2
            pipewire
            systemd
            util-linux
            wayland
            xdg-desktop-portal
            xdg-desktop-portal-gtk
            xdg-desktop-portal-gnome
            xdg-utils
            xorg.libX11
            xorg.libXcomposite
            xorg.libXdamage
            xorg.libXext
            xorg.libXfixes
            xorg.libXrandr
            xorg.libXtst
            xorg.libXScrnSaver
            xorg.libxcb
            xorg.libxshmfence
            zlib
          ];
        extraBuildCommands = ''
          mkdir -p $out/opt
          ln -s ${calderadockExtracted}/opt/CalderaDock.linux $out/opt/CalderaDock.linux
          ln -s ${calderaAPIExtracted}/opt/caldera-rest-api $out/opt/caldera-rest-api
        '';
        runScript = "${pkgs.writeShellScript "calderadock-wrapper" ''
          exec /opt/CalderaDock.linux/CalderaDock \
            --no-sandbox \
            --disable-gpu-sandbox \
            "$@"
        ''}";
      };

      calderaIso = pkgs.runCommand "caldera-rip-iso" { } ''
        mkdir -p $out
        cp ${calderarip-iso} $out/CalderaRIP-v${versions.calderarip}-light.iso
      '';
    in
    {
      packages.${system} = {
        caldera-rest-api = calderaRestApi;
        calderaAPIExtracted = calderaAPIExtracted;
        calderadock = calderadock;
        calderaIso = calderaIso;
      };

      homeManagerModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          options.caldera.api.enable = lib.mkEnableOption "Enable Caldera REST API service";
          options.caldera.api.serverHost = lib.mkOption {
            type = lib.types.str;
            default = "0.0.0.0";
          };
          options.caldera.api.serverPort = lib.mkOption {
            type = lib.types.int;
            default = 12340;
          };
          options.caldera.api.loggerLevel = lib.mkOption {
            type = lib.types.str;
            default = "info";
          };
          options.caldera.api.loggerPrettify = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          options.caldera.api.services = lib.mkOption {
            type = lib.types.listOf lib.types.any;
            default = [ ];
          };

          options.caldera.dock.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };

          config =
            let
              apiEnabled = config.caldera.api.enable || config.caldera.dock.enable;
            in
            {
              systemd.user.services.caldera-rest-api = lib.mkIf apiEnabled {
                Unit = {
                  Description = "Caldera REST API service";
                  After = [ "network.target" ];
                  Wants = [ "network.target" ];
                };
                Service = {
                  Type = "exec";
                  ExecStart = "${self.packages.${pkgs.system}.caldera-rest-api}/bin/caldera-rest-api";
                  User = "caldera-rest-api";
                  Group = "caldera-rest-api";
                  Environment = lib.mkForce [
                    "SERVERHOST=${config.caldera.api.serverHost}"
                    "SERVERPORT=${toString config.caldera.api.serverPort}"
                    "LOGGERLEVEL=${config.caldera.api.loggerLevel}"
                    "LOGGERPRETTIFY=${if config.caldera.api.loggerPrettify then "true" else "false"}"
                    "SERVICES=${lib.concatStringsSep "," (map toString config.caldera.api.services)}"
                  ];
                  Restart = "on-failure";
                  RestartSec = "5s";
                  NoNewPrivileges = true;
                };
                Install = {
                  WantedBy = [ "default.target" ];
                };
              };
            };
        };

    };
}
