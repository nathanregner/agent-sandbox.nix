# Test fixture: isolateNixStore=false
# Note: nix is NOT in allowedPackages, but should be runnable when store is not isolated
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashNonInteractive;
  binName = "bash";
  outName = "sandboxed-bash-no-store-isolation";
  allowedPackages = [ pkgs.coreutils pkgs.bashNonInteractive ];
  isolateNixStore = false;
  # Pass nix path so test can find it, but it's not in allowedPackages
  extraEnv = { NIX_BIN = "${pkgs.nix}/bin/nix"; };
}
