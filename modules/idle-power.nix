{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.nvidia.cmpTools.idlePower;
in
{
  options.hardware.nvidia.cmpTools.idlePower = {
    enable = lib.mkEnableOption ''
      nvidia-pstated, which forces idle GPUs into P8 and back to full clocks
      when load returns. Needs the unfree package `cuda_nvml_dev` at build time
    '';
    idleSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Seconds at 0% utilization before a GPU is dropped to P8.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nvidia-pstated = {
      description = "Force idle NVIDIA GPUs into a low performance state";
      after = [
        "systemd-modules-load.service"
        "cmp90hx-unlock.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment.LD_LIBRARY_PATH = lib.makeLibraryPath [ config.hardware.nvidia.package ];
      serviceConfig = {
        ExecStart = "${
          lib.getExe (pkgs.callPackage ../pkgs/nvidia-pstated.nix { })
        } --sleep-interval 1000 --iterations-before-switch ${toString cfg.idleSeconds}";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
