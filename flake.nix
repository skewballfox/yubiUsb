{
  description = "A Nix Flake for a gui optional swayfx-based system with YubiKey setup";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    drduhConfig.url = "github:drduh/config";
    # this should work. see https://discourse.nixos.org/t/flakes-re-locking-necessary-at-each-evaluation-when-import-sub-flake-by-path/34465/6
    localConfig.url = "github:skewballfox/live_config";
    #localConfig.url = "path:config";
    localConfig.flake = false;
    drduhConfig.flake = false;
  };

  outputs = {
    self,
    nixpkgs,
    drduhConfig,
    localConfig,
  }: let
    mkSystem = system:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          
          "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
          "${nixpkgs}/nixos/modules/hardware/all-firmware.nix"
          "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
          #"${nixpkgs}/nixos/modules/installer/virtualization/qemu-vm.nix"
          (
            {
              lib,
              pkgs,
              config,
              ...
            }: let
              gpgAgentConf = pkgs.runCommand "gpg-agent.conf" {} ''
                sed '/pinentry-program/d' ${drduhConfig}/gpg-agent.conf > $out
                echo "pinentry-program ${pkgs.pinentry.curses}/bin/pinentry" >> $out
              '';
              viewYubikeyGuide = pkgs.writeShellScriptBin "view-yubikey-guide" ''
                viewer="$(type -P xdg-open || true)"
                if [ -z "$viewer" ]; then
                  viewer="${pkgs.glow}/bin/glow -p"
                fi
                exec $viewer "${self}/README.md"
              '';
              shortcut = pkgs.makeDesktopItem {
                name = "yubikey-guide";
                icon = "${pkgs.yubikey-manager-qt}/share/ykman-gui/icons/ykman.png";
                desktopName = "drduh's YubiKey Guide";
                genericName = "Guide to using YubiKey for GPG and SSH";
                comment = "Open the guide in a reader program";
                categories = ["Documentation"];
                exec = "${viewYubikeyGuide}/bin/view-yubikey-guide";
              };
              yubikeyGuide = pkgs.symlinkJoin {
                name = "yubikey-guide";
                paths = [viewYubikeyGuide shortcut];
              };
              
            in {
              isoImage = {
                isoName = "yubikeyLive.iso";
                # As of writing, zstd-based iso is 1542M, takes ~2mins to
                # compress. If you prefer a smaller image and are happy to
                # wait, delete the line below, it will default to a
                # slower-but-smaller xz (1375M in 8mins as of writing).
                squashfsCompression = "zstd";

                appendToMenuLabel = " YubiKey Live ${self.lastModifiedDate}";
                makeEfiBootable = true; # EFI booting
                makeUsbBootable = true; # USB booting
              };

              hardware = {
                cpu.amd.updateMicrocode = true;
                #enableAllFirmware = true;
                enableRedistributableFirmware = true;
                opengl = {
                  enable = true;
                  driSupport = true;
                  driSupport32Bit = true;
                  extraPackages = with pkgs; [ amdvlk vulkan-validation-layers vaapiVdpau libvdpau-va-gl ];
                  # For 32 bit applications 
                  extraPackages32 = with pkgs; [
                    driversi686Linux.amdvlk
                  ];
                };
                # nvidia = {
                #   package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;
                #   #package = pkgs.linuxKernel.packages.linux_zen.nvidia_x11_production_open;
                #   open = true;
                # };
                
              };
              swapDevices = [];
              
              boot.kernelPackages = pkgs.linuxPackages_latest;
              boot.tmp.cleanOnBoot = true;
              boot.kernel.sysctl = {"kernel.unprivileged_bpf_disabled" = 1;};
              boot.initrd.network.enable = false;
              boot.initrd.kernelModules = [ "amdgpu" ];

              services = {
                pcscd.enable = true;
                udev.packages = [pkgs.yubikey-personalization];
                # Automatically log in at the virtual consoles.
                getty.autologinUser = "nixos";
                
                dbus.enable = true;
                pipewire = {
                  enable = true;
                  alsa.enable = true;
                  alsa.support32Bit = true;
                  pulse.enable = true;
                };
                xserver = {
                  enable = true;
                  videoDrivers = [ "modesetting" "fbdev" "amdgpu" ];
                  libinput.enable = true;
                };
                
                
              };
              xdg.portal = {
                enable = true;
                extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
              };
              
            #   documentation.enable = true;
            #   documentation.man = {
            #     enable = true;
            #     generateCaches = true;
            # };
              # Programs to be configured
              # for the difference between `programs` and `environment.systemPackages`
              # see https://discourse.nixos.org/t/programs-foo-enable-true-vs-systempackages-foo-is-confusing/5534
              programs = {
                ssh.startAgent = false;
                gnupg.agent = {
                  enable = true;
                  enableSSHSupport = true;
                };
                sway= {
                  enable = true;
                  wrapperFeatures.base = true;
                  wrapperFeatures.gtk = true;
                  extraSessionCommands = ''
                  export XDG_DATA_HOME="$HOME/.local/share"
                  export QT_QPA_PLATFORM=wayland
                  export QT_QPA_PLATFORMTHEME=qt5ct
                  export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
                  export GDK_BACKEND=wayland
                  #NOTE: Simple DirectMedia Layer
                  export SDL_VIDEODRIVER=wayland

                  #so thunderbird-wayland will actually use wayland
                  export MOZ_ENABLE_WAYLAND=1
                  #think it's used for obs studio
                  export MOZ_WEBRENDER=1

                  # for IntelliJ, Android Studio, etc
                  # https://stackoverflow.com/questions/33424736/intellij-idea-14-on-arch-linux-opening-to-grey-screen/34419927#34419927
                  export _JAVA_AWT_WM_NONREPARENTING=1

                  #necessary for tumbler apparently
                  export XDG_CACHE_HOME=$HOME/.cache
                  
                  #stuff to try to get gnome-pinentry and seahorse
                  #to properly work
                  export XDG_CURRENT_DESKTOP=sway
                  export XDG_SESSION_DESKTOP=sway
                  export XDG_SESSION_TYPE=wayland
                  export CURRENT_DESKTOP=sway

                  # Vukan rendering for wlroots
                  # NOTE: requires vulkan-validation-layers
                  # https://wiki.archlinux.org/title/sway#Use_another_wlroots_renderersw
                  export WLR_RENDERER=vulkan
                  '';
                };

                
                # fish = {
                #   enable = true;
                #   interactiveShellInit = ''
                #     set -g fish_key_bindings fish_default_key_bindings
                #     bind \cc kill-whole-line repaint
                #     bind \cd forward-char
                #   '';
                  
                # };
                
                
              };

              # Use less privileged nixos user
              users.users = {
                nixos = {
                  isNormalUser = true;
                  extraGroups = ["wheel" "video"];
                  initialHashedPassword = "";
                };
                root.initialHashedPassword = "";
              };

              security = {
                pam.services.lightdm.text = ''
                  auth sufficient pam_succeed_if.so user ingroup wheel
                '';
                sudo = {
                  enable = true;
                  wheelNeedsPassword = false;
                };
                rtkit.enable = true;
              };

              environment.systemPackages = with pkgs; [
                #probably already included
                coreutils

                # for debugging
                pciutils

                # if a gui is needed
                swayfx
                kitty
                
                i3status-rust
                vulkan-validation-layers
                vulkan-tools
                vulkan-loader
                libva
                libva-utils
                
                # terminal porn
                starship
                glow
                bat
                ripgrep
                findutils
                jq

                wayland
                mesa
                 # VAAPI
                vaapiVdpau
                libvdpau-va-gl
                
                # Tools for backing up keys
                paperkey
                pgpdump
                parted
                cryptsetup
                

                # Yubico's official tools
                yubikey-manager
                yubikey-manager-qt
                yubikey-personalization
                yubikey-personalization-gui
                yubico-piv-tool
                yubioath-flutter

                # Testing
                ent
                haskellPackages.hopenpgp-tools

                # Password generation tools
                diceware
                pwgen

                # Might be useful beyond the scope of the guide
                cfssl
                pcsctools
                tmux
                htop
                gopass
                fish
                helix
                atuin

                #fonts
                fira-code
                fira
                font-awesome
                cooper-hewitt
                ibm-plex
                jetbrains-mono
                iosevka
                # bitmap
                spleen
                fira-code-symbols
                powerline-fonts
                nerdfonts

                # # to get fish to build
                # linux-manual
                # man-pages
                # man-pages-posix

                # This guide itself (run `view-yubikey-guide` on the terminal
                # to open it in a non-graphical environment).
                yubikeyGuide
              ];

              # Disable networking so the system is air-gapped
              # Comment all of these lines out if you'll need internet access
              
              networking = {
                resolvconf.enable = false;
                dhcpcd.enable = false;
                dhcpcd.allowInterfaces = [];
                interfaces = {};
                firewall.enable = true;
                useDHCP = false;
                useNetworkd = false;
                wireless.enable = false;
                networkmanager.enable = lib.mkForce false;
              };
              environment.pathsToLink = [
                "/share/fish"
              ];
              # Unset history so it's never stored Set GNUPGHOME to an
              # ephemeral location and configure GPG with the guide's

              environment.interactiveShellInit = ''
                unset HISTFILE
                export GNUPGHOME="/run/user/$(id -u)/gnupg"
                if [ ! -d "$GNUPGHOME" ]; then
                  echo "Creating \$GNUPGHOME…"
                  install --verbose -m=0700 --directory="$GNUPGHOME"
                fi
                [ ! -f "$GNUPGHOME/gpg.conf" ] && cp --verbose "${drduhConfig}/gpg.conf" "$GNUPGHOME/gpg.conf"
                [ ! -f "$GNUPGHOME/gpg-agent.conf" ] && cp --verbose ${gpgAgentConf} "$GNUPGHOME/gpg-agent.conf"
                echo "\$GNUPGHOME is \"$GNUPGHOME\""
              '';

              # Copy the contents of contrib to the home directory, add a
              # shortcut to the guide on the desktop, and link to the whole
              # repo in the documents folder.
              system.activationScripts.yubikeyGuide = let
                homeDir = "/home/nixos/";
                configDir = "/home/nixos/.config/";
                desktopDir = homeDir + "Desktop/";
                documentsDir = homeDir + "Documents/";
              in ''
                mkdir -p ${desktopDir} ${documentsDir} ${configDir}
                chown nixos ${homeDir} ${desktopDir} ${documentsDir} ${configDir}
                cp -R ${localConfig}/config/* ${configDir}
                cp -R ${self}/contrib/* ${homeDir}
                ln -sf ${yubikeyGuide}/share/applications/yubikey-guide.desktop ${desktopDir}
                ln -sfT ${self} ${documentsDir}/YubiKey-Guide
              '';
              system.stateVersion = "23.11";
            }
          )
        ];
      };
  in {
    nixosConfigurations.yubikeyLive.x86_64-linux = mkSystem "x86_64-linux";
    nixosConfigurations.yubikeyLive.aarch64-linux = mkSystem "aarch64-linux";
    #nixosConfigurations.yubikeyLive.qemu = mkSystem
    formatter.x86_64-linux = (import nixpkgs {system = "x86_64-linux";}).alejandra;
    formatter.aarch64-linux = (import nixpkgs {system = "aarch64-linux";}).alejandra;
  };
}