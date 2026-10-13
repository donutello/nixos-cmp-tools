{
  callPackage,
  coreutils,
  gnugrep,
  kmod,
  modules,
  pciutils,
  python3,
  stdenv,
  writeShellApplication,
}:

let
  inherit (callPackage ./sources.nix { }) wh1stle;

  # jdowning100's BAR0 tool, from the copy Wh1stle05/cmp90hx vendors.
  bar0poke = stdenv.mkDerivation {
    name = "bar0poke";
    src = wh1stle;
    buildPhase = "$CC -O2 -o bar0poke tools/bar0poke.c";
    installPhase = "install -Dm755 bar0poke $out/bin/bar0poke";
  };
in
writeShellApplication {
  name = "cmp90hx-unlock";
  runtimeInputs = [
    bar0poke
    coreutils
    gnugrep
    kmod
    pciutils
    python3
  ];
  runtimeEnv = {
    MODULES = modules;
    MASKREAD = "${wh1stle}/scripts/maskread.py";
  };
  text = builtins.readFile ./cmp90hx-unlock.sh;
  meta.platforms = [ "x86_64-linux" ];
}
