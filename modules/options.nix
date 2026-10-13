# What the card modules share.
{ config, lib, ... }:

let
  # The NixOS release this branch's pins have passed on; flake.nix's nixpkgs
  # follows the same release.
  release = "26.05";
in
{
  # Not readOnly: the module system counts a read-only option's definitions
  # before resolving mkIf, and each card module defines it under its own.
  options.hardware.nvidia.cmpTools.kernelModules = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    description = ''
      Set by the card modules, to read rather than set: the nvidia kernel
      modules the unlocked card runs, the patched driver's on a CMP 170HX and
      those `cmp90hx-unlock.service` loads on a CMP 90HX. A card runs an
      update's modules only after a reboot, so comparing this between the
      booted and the newest generation tells whether one is still due.
    '';
  };

  # The driver is built from the host's nixpkgs, so a branch is only known to
  # work on its own release.
  config.warnings =
    lib.optional
      (config.hardware.nvidia.cmpTools.kernelModules != null && lib.trivial.release != release)
      ''
        hardware.nvidia.cmpTools: this branch has been tested on NixOS ${release}, but this host runs
        ${lib.trivial.release}. Use the branch named after your release, nixos-${lib.trivial.release}, if it exists.
      '';
}
