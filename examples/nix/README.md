# Nix Formatting Example

This example uses [nixfmt](https://github.com/NixOS/nixfmt) to format Nix files with `rules_lint`.

## Setup

- `MODULE.bazel` installs nixfmt with `rules_multitool`.
- `tools/nixfmt.lock.json` pins nixfmt 1.4.0 for Linux x86_64.
- `tools/format/BUILD` sets the `nix` attribute on `format_multirun`.

## Usage

From this directory:

```sh
bazel run //tools/format
bazel run //tools/format:format.check
bats test
```

The formatter discovers `*.nix` files. Check mode uses nixfmt's `--check` flag and leaves source files unchanged.

The pinned release only provides a Linux x86_64 binary. Other platforms need a compatible nixfmt binary and a matching URL, SHA-256, OS, and CPU entry in the lockfile, or a different binary target supplied through the `nix` attribute.

## Using a Nix-provided formatter on macOS

Nix can supply nixfmt for the host platform without a separate GitHub release binary. The steps below describe an alternative to this example's Linux-only multitool setup.

1. [Install Nix](https://nixos.org/download/) on the Mac. Bazel integration requires an existing Nix installation; it does not install Nix or configure its daemon and store.
2. Verify that Nix can supply nixfmt 1.4.0:

   ```sh
   nix --extra-experimental-features 'nix-command flakes' build github:NixOS/nixfmt/v1.4.0
   ./result/bin/nixfmt --check src/hello.nix
   ```

   `nix build` creates a `result` symlink to the package in the Nix store. Enable `nix-command` and `flakes` in your Nix configuration for subsequent Bazel use.
3. Add [rules_nixpkgs](https://github.com/tweag/rules_nixpkgs) to the Bazel project. For a flake-based setup, create a project flake that exposes the desired nixfmt package, commit its `flake.lock`, and use [`nixpkgs_flake_package`](https://github.com/tweag/rules_nixpkgs#nixpkgs_flake_package) to import that package. The repository rule invokes Nix to realize the package. Alternatively, use `nixpkgs_package` with a pinned Nixpkgs revision and its nixfmt package.
4. Use the repository rule's `build_file` or `build_file_content` attribute to expose `bin/nixfmt` as a public Bazel file target. Replace `nix = "@multitool//tools/nixfmt"` in `tools/format/BUILD` with that target's label. Then run the same format and check commands shown above.

Keep the Nix store available when running the formatter: a Nix-provided binary can depend on other paths in that store. Every machine using this setup, including CI workers, needs Nix installed.
