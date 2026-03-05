# Example: a dev shell with a sandboxed Claude Code binary.
# Copy this into your project and adjust as needed.
#
# Usage:
#   nix-shell example.shell.nix

let
  pkgs = import <nixpkgs> { config.allowUnfree = true; };
  sandbox = import (builtins.fetchTarball
    "https://github.com/archie-judd/agent-sandbox.nix/archive/main.tar.gz") {
      pkgs = pkgs;
    };
  claude-sandboxed = sandbox.mkSandbox {
    pkg = pkgs.claude-code;
    binName = "claude";
    outName = "claude-sandboxed";
    allowedPackages = [
      pkgs.coreutils
      pkgs.bash
      pkgs.git
      pkgs.ripgrep
      pkgs.fd
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.jq
    ];
    stateDirs = [ "$HOME/.claude" ];
    stateFiles = [ "$HOME/.claude.json" ];
    extraEnv = {
      # Use literal strings for secrets to evaluate at runtime!
      # builtins.getEnv will leak your token into the /nix/store.
      CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
      GIT_AUTHOR_NAME = "claude-agent";
      GIT_AUTHOR_EMAIL = "claude-agent@localhost";
      GIT_COMMITTER_NAME = "claude-agent";
      GIT_COMMITTER_EMAIL = "claude-agent@localhost";
    };
    inheritPath = false;
  };
  copilot-sandboxed = sandbox.mkSandbox {
    pkg = pkgs.github-copilot-cli;
    binName = "copilot";
    outName = "copilot-sandboxed";
    stateDirs = [ "$HOME/.config/github-copilot" "$HOME/.copilot" ];
    stateFiles = [ ];
    allowedPackages = [
      pkgs.coreutils
      pkgs.bash
      pkgs.git
      pkgs.ripgrep
      pkgs.fd
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.jq
    ];
    extraEnv = {
      GITHUB_TOKEN = "$GITHUB_TOKEN";
      GIT_AUTHOR_NAME = "copilot-agent";
      GIT_AUTHOR_EMAIL = "copilot-agent@localhost";
      GIT_COMMITTER_NAME = "copilot-agent";
      GIT_COMMITTER_EMAIL = "copilot-agent@localhost";
    };
    inheritPath = true;
  };

in pkgs.mkShell { packages = [ claude-sandboxed copilot-sandboxed ]; }
