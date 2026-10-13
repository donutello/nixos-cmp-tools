{ callPackage, nvidiaPackages }:

let
  inherit (callPackage ./sources.nix { }) cmp170hx;
in
nvidiaPackages.mkDriver (cmp170hx.driver // { patchesOpen = cmp170hx.patches; })
