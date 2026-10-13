# Every upstream pin, from sources.json.
{
  fetchFromGitHub,
  fetchurl,
  lib,
  runCommand,
}:

let
  pins = lib.importJSON ./sources.json;
  repos = lib.mapAttrs (
    _: pin:
    fetchFromGitHub {
      inherit (pin)
        owner
        repo
        rev
        hash
        ;
    }
  ) pins.repos;
  # Arguments for nvidiaPackages.mkDriver.
  driver = version: pins.drivers.${version} // { inherit version; };

  # Patches 0014/0015 only exist inside a release tarball next to a 129 MB
  # binary; extract just the patches so the binary never enters the store.
  pearlfortune = runCommand "cmp90hx-stockflow-patches" { } ''
    mkdir -p $out
    tar xzf ${fetchurl { inherit (pins.pearlfortune) url hash; }} --wildcards --strip-components=4 \
      -C $out '*/stockflow/${pins.cmp90hx.driver}/patches/*.patch'
  '';
  from = repos // {
    inherit pearlfortune;
  };
in
{
  inherit (repos) wh1stle;

  cmp170hx = {
    driver = driver pins.cmp170hx.driver;
    # amoghmunikote's driver/build.sh order, then ours: re-apply the Gen2
    # registers GSP-RM reverts, and retry the retrain.
    patches = map (p: "${repos.amoghmunikote}/driver/patches/${p}.patch") pins.cmp170hx.patches ++ [
      ./patches/cmp170hx-gen2-retrain.patch
    ];
  };

  cmp90hx = {
    driver = driver pins.cmp90hx.driver;
    # Wh1stle05/cmp90hx's scripts/install.sh order.
    patches = map (p: "${from.${p.from}}/${p.path}") pins.cmp90hx.patches;
    # Strings the patched nvidia.ko must contain at least this often.
    markers = {
      "CMP90_STOCKFLOW_REJOIN16" = 7;
      "CMP90 Gen2" = 5;
    };
  };

  nvidiaPstated = {
    src = repos.nvidiaPstated;
    # Upstream's CMake fetches this at configure time; sources.json holds the
    # hash upstream declares.
    nvapi = fetchurl { inherit (pins.nvapi) url hash; };
  };
}
