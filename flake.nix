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
        runtimeLibs = with pkgs; [
          sqlite
          libsodium
        ];
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
            "--threads:on"
            "--mm:orc"
          ];
          buildInputs = with pkgs; [
            sqlite
            libsodium
          ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postFixup = ''
            wrapProgram $out/bin/main \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"
          '';
          meta.mainProgram = "main";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nim-2_0
            nimble
            sqlite
            libsodium
          ];
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;
        };
      }
    );
}
