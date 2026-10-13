{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.nvidia.cmpTools.cmp170hx;
  driver = pkgs.callPackage ../pkgs/cmp170hx-driver.nix {
    inherit (config.boot.kernelPackages) nvidiaPackages;
  };
in
{
  imports = [ ./options.nix ];

  options.hardware.nvidia.cmpTools.cmp170hx.enable = lib.mkEnableOption ''
    the CMP 170HX unlock: replaces `hardware.nvidia.package` with a patched
    nvidia-open ${driver.version} that restores full compute and the real
    HBM2e size (8 GB cards → 64 GB, 10 GB cards → 40 GB) on every driver load
  '';

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.nvidia.open;
        message = "hardware.nvidia.cmpTools.cmp170hx requires hardware.nvidia.open = true.";
      }
    ];

    hardware.nvidia = {
      package = driver;
      cmpTools.kernelModules = driver.open;
      # Asks the GSP for PCIe Gen2.
      moduleParams.nvidia.NVreg_RegistryDwords = "RmForceEnableGen2=1;RMPcieLinkSpeed=0x1";
    };

    warnings = lib.optional (config.hardware.nvidia.package.version != driver.version) ''
      hardware.nvidia.cmpTools.cmp170hx: hardware.nvidia.package is overridden; the card stays locked.
    '';
  };
}
