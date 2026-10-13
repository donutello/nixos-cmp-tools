{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.nvidia.cmpTools.cmp90hx;
  driver = pkgs.callPackage ../pkgs/cmp90hx-driver.nix {
    inherit (config.boot.kernelPackages) nvidiaPackages;
  };
  unlock = pkgs.callPackage ../pkgs/cmp90hx-unlock.nix { inherit (driver) modules; };
in
{
  imports = [ ./options.nix ];

  options.hardware.nvidia.cmpTools.cmp90hx = {
    enable = lib.mkEnableOption ''
      the CMP 90HX unlock: boots on a stock nvidia-open ${driver.stock.version},
      then `cmp90hx-unlock.service` reloads the card on patched modules, which
      restores full FP32 throughput. Redone on every boot
    '';
    pcieGen2.enable =
      lib.mkEnableOption ''
        opening the PCIe Gen2 path (two extra driver reloads per card, then a
        link retrain). Adds `iomem=relaxed`, which lets root map any
        driver-claimed MMIO
      ''
      // {
        default = true;
      };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.nvidia.open;
        message = "hardware.nvidia.cmpTools.cmp90hx requires hardware.nvidia.open = true.";
      }
      {
        assertion = !config.hardware.nvidia.cmpTools.cmp170hx.enable;
        message = "hardware.nvidia.cmpTools: cmp90hx and cmp170hx need different drivers and cannot share a host.";
      }
    ];

    hardware.nvidia = {
      package = driver.stock;
      cmpTools.kernelModules = driver.modules;
    };
    boot.kernelParams = lib.optional cfg.pcieGen2.enable "iomem=relaxed";

    # Must finish before anything opens /dev/nvidia*, or the reloads fail.
    systemd.services.cmp90hx-unlock = {
      description = "CMP 90HX unlock";
      after = [ "systemd-modules-load.service" ];
      wantedBy = [ "multi-user.target" ];
      # A switch restarting it would reload the driver under running jobs; new
      # modules wait for the next boot.
      restartIfChanged = false;
      environment.CMP90_PCIE_GEN2 = if cfg.pcieGen2.enable then "1" else "0";
      path = [ config.hardware.nvidia.package.bin ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe unlock;
        StateDirectory = "cmpunlocker-rs";
        TimeoutStartSec = "15min";
      };
    };

    environment.systemPackages = [ pkgs.pciutils ];

    warnings = lib.optional (config.hardware.nvidia.package.version != driver.stock.version) ''
      hardware.nvidia.cmpTools.cmp90hx: hardware.nvidia.package is overridden; the patched modules will not load.
    '';
  };
}
