let
  pkgs = import <nixpkgs> { };
  sandbox = import ../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashNonInteractive;
  binName = "bash";
  outName = "sandboxed-bash-symlink-state";
  allowedPackages = [ pkgs.coreutils pkgs.bashNonInteractive ];
  stateDirs  = [ "$HOME/.test-symlink-dir" ];
  stateFiles = [ "$HOME/.test-symlink-file" ];
}
