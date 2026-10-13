{
  description = "NixOS modules that unlock NVIDIA CMP 170HX and CMP 90HX cards and lower the 90HX's idle power";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      inherit (pkgs.linuxPackages) nvidiaPackages;
      cmp90hx = pkgs.callPackage ./pkgs/cmp90hx-driver.nix { inherit nvidiaPackages; };
    in
    {
      nixosModules = {
        cmp170hx = ./modules/cmp170hx.nix;
        cmp90hx = ./modules/cmp90hx.nix;
        idlePower = ./modules/idle-power.nix;
        default.imports = [
          ./modules/cmp170hx.nix
          ./modules/cmp90hx.nix
          ./modules/idle-power.nix
        ];
      };

      packages.${system} = {
        cmp170hx-driver = pkgs.callPackage ./pkgs/cmp170hx-driver.nix { inherit nvidiaPackages; };
        cmp90hx-driver = cmp90hx.stock;
        cmp90hx-modules = cmp90hx.modules;
        cmp90hx-unlock = pkgs.callPackage ./pkgs/cmp90hx-unlock.nix { inherit (cmp90hx) modules; };
        nvidia-pstated = pkgs.callPackage ./pkgs/nvidia-pstated.nix { };
      };

      checks.${system} = import ./checks.nix { inherit self nixpkgs pkgs; };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
