# Test fixture: basic sandbox isolation
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox ({
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash";
  allowedPackages = [ pkgs.coreutils ];
  stateDirs = [ "$HOME/.test-state-dir" ];
  stateFiles = [ "$HOME/.test-state-file" ];
  roStateDirs = [ "$HOME/.test-ro-dir" ];
  roStateFiles = [ "$HOME/.test-ro-file" ];
  extraEnv = { TEST_VAR = "test-value"; };
} // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  # overlayStateDirs is Linux-only (uses bwrap --tmp-overlay)
  overlayStateDirs = [ "$HOME/.test-overlay-dir" ];
})
