# Development tools for the dev shell (flake.nix) whose nixpkgs versions don't fit this repository.
# Nothing here is part of the package build.
{
  lib,
  fetchFromGitHub,
  rustPlatform,
  cargo-nextest,
  wasm-bindgen-cli_0_2_129,
}:

{
  # .config/nextest.toml requires nextest ≥ 0.9.150 (GHSA-vc25-qg58-w57c is fixed there) and an older
  # one refuses to run (exit 92), so `cargo xtask ci` would fail. Drop this override once nixpkgs
  # ships 0.9.150 or later.
  cargo-nextest =
    if lib.versionAtLeast cargo-nextest.version "0.9.150" then
      cargo-nextest
    else
      cargo-nextest.overrideAttrs (
        finalAttrs: _: {
          version = "0.9.150";
          src = fetchFromGitHub {
            owner = "nextest-rs";
            repo = "nextest";
            tag = "cargo-nextest-${finalAttrs.version}";
            hash = "sha256-8smZD0W9pcVEDnOHt5AOMpWkP5TawOGxsDksoKcb4Ys=";
          };
          cargoDeps = rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src;
            name = "cargo-nextest-${finalAttrs.version}";
            hash = "sha256-rY+6iJXf7j2Uz1Q7MtbntkBxYCDr+WaP9DUxm6P3hZ4=";
          };
        }
      );

  # trunk needs exactly the wasm-bindgen version in Cargo.lock, or it downloads its own copy. Keep
  # this in step with `name = "wasm-bindgen"` in Cargo.lock.
  wasm-bindgen-cli = wasm-bindgen-cli_0_2_129;
}
