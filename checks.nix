# The gates `nix flake check` runs besides the flake's own outputs.
{
  self,
  nixpkgs,
  pkgs,
}:

let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;
  packages = self.packages.${system};

  check =
    name: inputs: script:
    pkgs.runCommand name { nativeBuildInputs = inputs; } ''
      cd ${self}
      ${script}
      touch $out
    '';

  # A minimal host with these cmpTools settings, instantiated but not built, so
  # an option or assertion that breaks against a newer nixpkgs fails here.
  eval =
    name: settings:
    let
      host = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.default
          {
            nixpkgs.hostPlatform = system;
            nixpkgs.config.allowUnfree = true;
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "/dev/null";
              fsType = "ext4";
            };
            services.xserver.videoDrivers = [ "nvidia" ];
            hardware.nvidia.open = true;
            hardware.nvidia.cmpTools = settings;
            system.stateVersion = "26.05";
          }
        ];
      };
    in
    # Also catches a release in modules/options.nix that differs from flake.nix's nixpkgs.
    assert lib.assertMsg (
      host.config.warnings == [ ]
    ) "eval-${name} warns: ${lib.concatStringsSep "; " host.config.warnings}";
    pkgs.writeText "eval-${name}" (
      builtins.unsafeDiscardStringContext "${host.config.system.build.toplevel.drvPath} ${toString host.config.hardware.nvidia.cmpTools.kernelModules}"
    );

  # Upstream's build.sh rewrites the memory geometry at build time unless the
  # patched kernel_gsp.c already picks it by device ID; this build relies on the
  # latter, so it checks for the same markers build.sh does.
  geometry = [
    "SEC2_POSTBL_TIMING_CMP_170HX_8GB_PCI_DEVICE_ID"
    "SEC2_POSTBL_TIMING_CMP_170HX_10GB_PCI_DEVICE_ID"
    "0x02779000U"
    "0x02669000U"
    "0x0000001000000000ULL"
    "0x0000000A00000000ULL"
  ];
in
{
  inherit (packages) cmp90hx-modules cmp90hx-unlock nvidia-pstated;
  cmp170hx-modules = packages.cmp170hx-driver.open;

  cmp170hx-geometry = packages.cmp170hx-driver.open.overrideAttrs {
    pname = "cmp170hx-geometry";
    buildPhase = ''
      for marker in ${lib.escapeShellArgs geometry}; do
        grep -qF "$marker" src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c \
          || { echo "kernel_gsp.c lacks $marker: upstream's build-time geometry rewrite is needed" >&2; exit 1; }
      done
    '';
    installPhase = "touch $out";
    dontFixup = true;
  };

  eval-cmp170hx = eval "cmp170hx" { cmp170hx.enable = true; };
  eval-cmp90hx = eval "cmp90hx" {
    cmp90hx.enable = true;
    idlePower.enable = true;
  };
  eval-cmp90hx-gen1 = eval "cmp90hx-gen1" {
    cmp90hx.enable = true;
    cmp90hx.pcieGen2.enable = false;
  };

  format = check "format" [ pkgs.nixfmt ] "nixfmt --check $(find . -name '*.nix')";
  lint = check "lint" [
    pkgs.deadnix
    pkgs.statix
  ] "statix check . && deadnix --fail .";
}
