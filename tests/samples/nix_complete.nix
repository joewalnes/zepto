# Nix expression language sample
# NixOS configuration / flake

{
  description = "A sample Nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, home-manager, flake-utils }:
    let
      # Helper function
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Package overlay
      overlay = final: prev: {
        myApp = final.callPackage ./package.nix { };
      };
    in
    {
      # NixOS configuration
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration.nix
          ({ config, pkgs, lib, ... }: {
            # System settings
            system.stateVersion = "24.05";
            networking.hostName = "myhost";
            time.timeZone = "UTC";

            # Boot
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;

            # Users
            users.users.admin = {
              isNormalUser = true;
              extraGroups = [ "wheel" "docker" "networkmanager" ];
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample admin@myhost"
              ];
            };

            # Packages
            environment.systemPackages = with pkgs; [
              vim
              git
              curl
              wget
              htop
              tmux
              ripgrep
              fd
              jq
            ];

            # Services
            services.openssh = {
              enable = true;
              settings = {
                PermitRootLogin = "no";
                PasswordAuthentication = false;
              };
            };

            services.nginx = {
              enable = true;
              virtualHosts."example.com" = {
                forceSSL = true;
                enableACME = true;
                locations."/" = {
                  proxyPass = "http://127.0.0.1:8080";
                };
              };
            };

            # Firewall
            networking.firewall = {
              enable = true;
              allowedTCPPorts = [ 22 80 443 ];
              allowedUDPPorts = [ ];
            };

            # Docker
            virtualisation.docker.enable = true;

            # Nix settings
            nix = {
              settings = {
                auto-optimise-store = true;
                experimental-features = [ "nix-command" "flakes" ];
              };
              gc = {
                automatic = true;
                dates = "weekly";
                options = "--delete-older-than 30d";
              };
            };
          })
          home-manager.nixosModules.home-manager
        ];
      };

      # Development shell
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_20
              yarn
              python311
              rustc
              cargo
            ];

            shellHook = ''
              echo "Development environment loaded"
              export DATABASE_URL="postgresql://localhost/dev"
            '';
          };
        }
      );

      # Packages
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
        in {
          default = pkgs.myApp;
          myApp = pkgs.myApp;
        }
      );
    };
}
