# Test fixture: sandbox with bindRepoRoot = false
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashNonInteractive;
  binName = "bash";
  outName = "sandboxed-bash";
  allowedPackages = [ pkgs.coreutils pkgs.bashNonInteractive pkgs.git ];
  bindRepoRoot = false;
}
