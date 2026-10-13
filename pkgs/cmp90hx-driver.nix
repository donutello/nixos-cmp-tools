# The host boots on `stock`; the unlock service then swaps in `modules`. The
# patched module must not be the first nvidia load after power-on: it needs
# state that only a stock GSP boot leaves behind.
{
  callPackage,
  lib,
  nvidiaPackages,
  runCommand,
  xz,
}:

let
  inherit (callPackage ./sources.nix { }) cmp90hx;

  stock = nvidiaPackages.mkDriver cmp90hx.driver;
  patched = stock.open.override { inherit (cmp90hx) patches; };

  # Uncompressed, because the service loads them with insmod (modprobe would
  # pick the stock ones from the kernel's module tree).
  modules = runCommand "nvidia-cmp90hx-modules-${stock.version}" { nativeBuildInputs = [ xz ]; } ''
    mkdir -p $out
    for ko in $(find ${patched} -name 'nvidia*.ko*'); do
      name=$(basename "$ko" .xz)
      xz -dcf "$ko" > "$out/$name"
    done
    ${lib.concatStrings (
      lib.mapAttrsToList (marker: min: ''
        n=$(grep -acF ${lib.escapeShellArg marker} $out/nvidia.ko || true)
        [ "$n" -ge ${toString min} ] || { echo "patch marker '${marker}': $n < ${toString min}" >&2; exit 1; }
      '') cmp90hx.markers
    )}
  '';
in
{
  inherit stock modules;
}
