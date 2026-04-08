# Test fixture: network restricted with per-domain method filtering
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bash;
  binName = "bash";
  outName = "sandboxed-bash-methods";
  allowedPackages = [ pkgs.coreutils pkgs.bash pkgs.curl ];
  restrictNetwork = true;
  allowedDomains = {
    "httpbin.org" = [ "GET" "HEAD" ];
    "pie.dev" = "*";
  };
}
