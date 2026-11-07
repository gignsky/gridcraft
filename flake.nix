{
  description = "GridCraft — spreadsheet, a free alternative to Excel, in pure Rust";

  inputs = {
    # GridCraft needs edition 2024 and rustc ≥ 1.95, so the flake tracks unstable. Consumers on a
    # release channel can retarget it: `inputs.gridcraft.inputs.nixpkgs.follows = "nixpkgs";`
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Optional build input of the repository: the fonts that the build embeds when `CRAFT_FONTS_DIR`
    # is set. Official releases always build with them; without them everything works but some
    # scripts have no glyphs. Pinned to the `craft-fonts-ref` that ci.yml and release.yml use — bump
    # all three together (`nix flake update craft-fonts`).
    craft-fonts = {
      url = "github:storytold/craft-fonts/b076417b5880bd4154bd22f00695b1d28c6bea83";
      flake = false;
    };

    # Dev shell only: nixpkgs' rustc has no wasm32 standard library, which `cargo xtask wasm` (part
    # of `cargo xtask ci`) and trunk need. The package builds with nixpkgs' rustPlatform.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      craft-fonts,
      rust-overlay,
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # The AppStream metadata carries a release date. The flake source's own commit date is
      # reproducible, unlike "now"; a tarball or dirty tree without one falls back to the epoch.
      buildDate =
        let
          d = self.lastModifiedDate or "";
        in
        if builtins.stringLength d >= 8 then
          "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}"
        else
          "1970-01-01";

      packageArgs = {
        inherit craft-fonts buildDate;
      };

      forAllSystems = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system; }) system);
    in
    {
      packages = forAllSystems (
        pkgs: _:
        let
          gridcraft = pkgs.callPackage ./nix/package.nix packageArgs;
        in
        {
          inherit gridcraft;
          default = gridcraft;
        }
      );

      # `nixpkgs.overlays = [ inputs.gridcraft.overlays.default ]` → `pkgs.gridcraft` everywhere.
      overlays.default = final: _prev: {
        gridcraft = final.callPackage ./nix/package.nix packageArgs;
      };

      apps = forAllSystems (
        _: system: {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.gridcraft;
          };
          # `nix run .#cli -- eval '=SUM(1,2,3)'`
          cli = {
            type = "app";
            program = lib.getExe' self.packages.${system}.gridcraft "gridcraft-cli";
          };
        }
      );

      devShells = forAllSystems (
        pkgs: system:
        let
          gridcraft = self.packages.${system}.gridcraft;
          tools = pkgs.callPackage ./nix/tools.nix { };
          # Stable Rust with the wasm32 target and the components `cargo xtask ci` runs.
          rust = (rust-overlay.lib.mkRustBin { } pkgs).stable.latest.default.override {
            targets = [ "wasm32-unknown-unknown" ];
            extensions = [
              "rust-src"
              "rust-analyzer"
              "clippy"
              "rustfmt"
            ];
          };
        in
        {
          default = pkgs.mkShell (
            {
              # The package's own native inputs, so `cargo build` in the shell needs no extra setup.
              inputsFrom = [ gridcraft ];
              packages = [
                rust
                # `cargo xtask test` uses nextest when it is installed.
                tools.cargo-nextest
                # The web build: `cd apps/gridcraft-web && trunk serve --release`.
                pkgs.trunk
                tools.wasm-bindgen-cli
                # `cargo xtask assets` lists the tracked files with git.
                pkgs.git
                pkgs.nixfmt
              ];
              # `cargo run` dlopens the Vulkan loader, libwayland and libxkbcommon like the packaged binary.
              LD_LIBRARY_PATH = lib.makeLibraryPath gridcraft.passthru.runtimeLibs;
              RUST_BACKTRACE = "1";
              shellHook = ''
                echo "GridCraft dev shell: 'cargo xtask ci' runs every gate (see docs/nix.md)."
              '';
            }
            // lib.optionalAttrs (craft-fonts != null) {
              # Embedded fonts in `cargo run` too; build.rs reads this as CRAFT_FONTS_DIR.
              CRAFT_FONTS_DIR = toString craft-fonts;
            }
          );
        }
      );

      checks = forAllSystems (
        pkgs: system: {
          gridcraft = self.packages.${system}.gridcraft;

          # `nix fmt` formats the flake; this keeps it formatted.
          formatting = pkgs.runCommand "gridcraft-nix-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            nixfmt --check ${./flake.nix} ${./nix}
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: _: pkgs.nixfmt);
    };
}
