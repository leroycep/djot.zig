{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, zig, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      lib = pkgs.lib;
    in {
      devShell.x86_64-linux = pkgs.mkShell {
        packages = [
          zig.packages.x86_64-linux.master
          pkgs.python3Packages.livereload
        ];
      };
    };
}
