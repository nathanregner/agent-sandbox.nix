# Test fixture: PATH merging with extraEnv
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashNonInteractive;
  binName = "bash";
  outName = "sandboxed-bash-path-merge";
  allowedPackages = [ pkgs.coreutils pkgs.bashNonInteractive ];
  extraEnv = { PATH = "/extra/path"; };
}
