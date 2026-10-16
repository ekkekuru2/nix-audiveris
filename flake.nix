{
  description = "Audiveris (Optical Music Recognition) packaged as an out-of-tree Nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The upstream sources, pulled in as-is: this repository holds only the
    # Nix packaging, never a copy or a fork of Audiveris itself.
    audiveris = {
      url = "github:Audiveris/audiveris";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      audiveris,
    }:
    let
      inherit (nixpkgs) lib;

      # The bundled JavaCPP natives (Tesseract, Leptonica) and the dependency
      # lockfile are platform specific, so only these two are supported.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      # "20260813160023" -> "2026-08-13"
      srcDate =
        let
          d = audiveris.lastModifiedDate;
        in
        "${lib.substring 0 4 d}-${lib.substring 4 2 d}-${lib.substring 6 2 d}";

      # Upstream sets its own version in buildSrc; this is that version plus
      # the date of the commit we are actually building.
      version = "5.11.0-unstable-${srcDate}";

      mkAudiveris =
        pkgs:
        pkgs.callPackage ./package.nix {
          inherit version;
          src = audiveris;
          rev = audiveris.rev;
        };
    in
    {
      # Usable from another flake as:
      #   nixpkgs.overlays = [ inputs.nix-audiveris.overlays.default ];
      overlays.default = final: _prev: { audiveris = mkAudiveris final; };

      packages = forAllSystems (
        system:
        let
          audiverisPkg = mkAudiveris nixpkgs.legacyPackages.${system};
        in
        {
          audiveris = audiverisPkg;
          default = audiverisPkg;
        }
      );

      apps = forAllSystems (system: {
        audiveris = self.apps.${system}.default;

        default = {
          type = "app";
          program = lib.getExe self.packages.${system}.audiveris;
          meta.description = "Audiveris optical music recognition application";
        };

        # Regenerates ./deps.json after the 'audiveris' input has been updated.
        # Needs network access; must be run from the root of this repository.
        update-deps = {
          type = "app";
          program = "${self.packages.${system}.audiveris.mitmCache.updateScript}";
          meta.description = "Regenerate the Gradle dependency lockfile (deps.json)";
        };
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # For hacking on the packaging itself, or on Audiveris outside of Nix.
          default = pkgs.mkShell {
            packages = [
              pkgs.jdk25
              (pkgs.gradle_9.override { java = pkgs.jdk25; })
              pkgs.git
            ];
            JAVA_HOME = "${pkgs.jdk25}";
          };
        }
      );

      checks = forAllSystems (system: {
        inherit (self.packages.${system}) audiveris;

        # Transcribes one of the example scores shipped with Audiveris and
        # checks that MusicXML comes out, which exercises the bundled
        # Tesseract/Leptonica natives too.
        transcribe = nixpkgs.legacyPackages.${system}.callPackage ./tests/transcribe.nix {
          audiveris = self.packages.${system}.audiveris;
          audiverisSrc = audiveris;
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
