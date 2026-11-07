# Developing with Nix

The flake gives you every tool the quality gates and the README workflows need, at the right versions, with one
command. It also builds and runs GridCraft from source. You don't need Nix to work on GridCraft (see
[Without Nix](#without-nix)), but with it there is nothing else to install.

## What the flake provides

| Output | Use |
|---|---|
| `devShells.default` | `nix develop`: the development environment below |
| `packages.default` | `nix build`: `./result/bin/gridcraft` and `./result/bin/gridcraft-cli`, with the desktop file, icons, MIME types and AppStream metadata from `packaging/linux/` |
| `apps.default` | `nix run`: start the desktop app |
| `apps.cli` | `nix run .#cli -- <args>`: run `gridcraft-cli` |
| `overlays.default` | `pkgs.gridcraft` in a NixOS or home-manager configuration |
| `checks` | `nix flake check`: builds the package and checks the Nix files are formatted |
| `formatter` | `nix fmt flake.nix nix`: formats the Nix files |

Systems: `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`. CI evaluates the flake for all three on every change to
`flake.nix`, `flake.lock`, `nix/` or `Cargo.lock` (`nix flake check --no-build --all-systems`). It doesn't build it:
`cargo xtask ci` stays the quality gate.

## Setup

1. Install Nix with flakes enabled. The [Determinate Systems installer](https://determinate.systems/nix-installer/)
   enables them by default. With the upstream installer, add `experimental-features = nix-command flakes` to
   `~/.config/nix/nix.conf`.
2. From the repository root, run `nix develop`. The first run downloads the toolchain. Later runs start at once.

To enter the shell automatically when you `cd` into the checkout, install [nix-direnv](https://github.com/nix-community/nix-direnv)
and run `echo "use flake" > .envrc && direnv allow`. `.envrc` is a personal file, so don't commit it.

## What's in `nix develop`

| Tool | Why |
|---|---|
| Stable Rust (from [rust-overlay](https://github.com/oxalica/rust-overlay)) with `clippy`, `rustfmt`, `rust-analyzer`, `rust-src` and the `wasm32-unknown-unknown` target | nixpkgs' Rust has no wasm32 standard library, and `cargo xtask wasm` and the web build need one. The workspace needs Rust ≥ 1.95 (`rust-version` in `Cargo.toml`). |
| `cargo-nextest` ≥ 0.9.150 | `.config/nextest.toml` requires that version, and an older nextest refuses to run. `nix/tools.nix` builds it when nixpkgs is behind. |
| `trunk` and `wasm-bindgen-cli` | The web app (`apps/gridcraft-web`). trunk needs exactly the `wasm-bindgen` version in `Cargo.lock`. |
| The windowing and GPU libraries (Wayland, X11, xkbcommon, Vulkan loader, libEGL, D-Bus) | Build inputs of the package. `LD_LIBRARY_PATH` points at the ones winit, wgpu and rfd open at run time, so `cargo run` works like the packaged app. |
| `git`, `nixfmt`, `pkg-config` | `cargo xtask assets` lists the tracked files with git. nixfmt formats the Nix files. |

The shell also sets `CRAFT_FONTS_DIR` to the pinned [craft-fonts](https://github.com/storytold/craft-fonts) checkout, so
`cargo build` embeds the same fonts as a release. To build without them, run `unset CRAFT_FONTS_DIR`.

## Everyday commands

Inside `nix develop`:

```sh
cargo xtask ci                                                   # every gate: fmt, clippy, tests, assets, layers, wasm, …
cargo run --release -p gridcraft -- --sample sales               # desktop app with a sample workbook
cargo run --release -p gridcraft -- --sample sales --control 7979   # + JSON control channel (docs/control-protocol.md)
cargo run -p gridcraft-cli -- eval '=SUM(1,2,3)'                 # headless CLI (docs/cli.md)
cd apps/gridcraft-web && trunk serve --release                   # web app on http://127.0.0.1:8771
```

Without entering the shell:

```sh
nix develop -c cargo xtask ci        # one command in the dev shell
nix build                            # the package → ./result/bin/
nix run . -- --sample sales          # the desktop app
nix run .#cli -- eval '=SUM(1,2,3)'  # the CLI
nix flake check                      # build the package and check formatting
```

## Desktop notes (NixOS)

- wgpu needs a Vulkan or OpenGL driver: set `hardware.graphics.enable = true;`.
- The window opens natively on Wayland and falls back to X11/XWayland.
- Open and Save dialogs go through xdg-desktop-portal. GNOME and KDE ship a portal backend. On Hyprland and other
  wlroots compositors, add one:
  `xdg.portal = { enable = true; extraPortals = [ pkgs.xdg-desktop-portal-gtk ]; };`.
- On other Linux distributions, `nix run` works when the system's GPU driver is visible to Nix programs, for
  example through [nixGL](https://github.com/nix-community/nixGL).

## Keeping the flake current

- **Cargo.lock changes** need nothing for the package, because it reads `Cargo.lock` directly (git dependencies included).
  When the `wasm-bindgen` version in `Cargo.lock` changes, update `wasm-bindgen-cli` in `nix/tools.nix` to the
  matching `wasm-bindgen-cli_0_2_<n>` from nixpkgs.
- **craft-fonts**: the `craft-fonts` input is pinned to the `craft-fonts-ref` in `.github/workflows/ci.yml` and
  `release.yml`. Change all three together, then run `nix flake update craft-fonts`.
- **nixpkgs and Rust**: `nix flake update` moves nixpkgs and rust-overlay forward. Once nixpkgs ships
  cargo-nextest ≥ 0.9.150, `nix/tools.nix` uses it unchanged and the override can be deleted.
- Run `nix flake check --no-build --all-systems` (what CI runs) and `nix develop -c cargo xtask ci` before pushing
  Nix changes.

## Without Nix

Install the same tools by hand:

```sh
rustup toolchain install stable --component clippy rustfmt
rustup target add wasm32-unknown-unknown
cargo install cargo-nextest --locked          # ≥ 0.9.150
cargo install trunk --locked                  # web app only
```

On Debian or Ubuntu, CI installs these system packages (`.github/workflows/ci.yml`): `pkg-config libxkbcommon-dev
libwayland-dev libx11-dev libxcursor-dev libxrandr-dev libxi-dev libgtk-3-dev libfontconfig1-dev libfreetype-dev
mesa-vulkan-drivers`.
