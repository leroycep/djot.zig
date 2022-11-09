{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zls = {
      url = "github:zigtools/zls";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig";
    };
  };

  outputs = { self, nixpkgs, zig, zls }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      lib = pkgs.lib;
    in {
      devShell.x86_64-linux = pkgs.mkShell {
        packages = [
          zig.packages.x86_64-linux.master
          zls.packages.x86_64-linux.zls
          pkgs.python3Packages.livereload
        ];
      };
    };
}
