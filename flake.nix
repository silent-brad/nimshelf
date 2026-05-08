{
  description = "Nimshelf - A Simple Self-hosted Digital Library in Nim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildNimPackage {
          pname = "nimshelf";
          version = "0.0.1";
          src = ./.;
          # Run `nix shell nixpkgs#nim_lk -c nim_lk > lock.json` to generate lock file
          lockFile = ./lock.json;
          nimFlags = [
            "-d:release"
          ];
          buildInputs = with pkgs; [
            nim-2_0
            nimble
            sqlite
          ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postFixup = ''
            wrapProgram $out/bin/main \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.sqlite ]}"
          '';
          meta.mainProgram = "main";
        };
      }
    );
}
