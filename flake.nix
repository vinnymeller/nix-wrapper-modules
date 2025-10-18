{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      lib = import ./lib.nix { lib = nixpkgs.lib; };
      wrapperModules = import ./modules.nix {
        lib = nixpkgs.lib;
        wlib = self.lib;
      };
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          filesToPatch = import ./checks/filesToPatch.nix {
            inherit pkgs;
            self = self;
          };
        }
      );
    };
}
