# DO NOT EDIT - This is a copy. Edit the original in the repo root.
{
  description = "Development environment flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    go-unifi-mcp.url = "github:claytono/go-unifi-mcp";
  };

  # Flake outputs that other flakes can use
  outputs = { self, nixpkgs, go-unifi-mcp }:
    let
      # Helpers for producing system-specific outputs
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" "aarch64-linux" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });

      # ARA package builder (shared across systems)
      mkAra = ps: ps.buildPythonPackage rec {
        pname = "ara";
        version = "1.7.3";
        pyproject = true;

        src = ps.fetchPypi {
          inherit pname version;
          hash = "sha256-kUeBOXfqlrZiXQvq+4TlIDuEgQYfEX5aib2CRihuGPQ=";
        };

        build-system = with ps; [
          setuptools
          pbr
        ];

        dependencies = with ps; [
          cliff
          django
          djangorestframework
          django-cors-headers
          dynaconf
          pbr
          pygments
          requests
          whitenoise
        ];

        doCheck = false;

        meta = {
          description = "ARA Records Ansible playbooks and makes them easier to understand and troubleshoot";
          homepage = "https://ara.recordsansible.org/";
        };
      };

      # Python environment with Ansible, ARA, and deps (shared across outputs)
      mkPythonEnv = pkgs: pkgs.python3.withPackages (ps: with ps; [
        ansible
        jinja2
        proxmoxer
        pyyaml
        ruamel-yaml
        websocket-client
        (mkAra ps)
      ]);

      # logcli for querying Grafana Loki from CLI
      mkLogcli = pkgs: let
        version = "3.6.4";
        sources = {
          "aarch64-darwin" = {
            url = "https://github.com/grafana/loki/releases/download/v${version}/logcli-darwin-arm64.zip";
            hash = "sha256-owKAFh2l5k8YXgbi8S0n/j0xO32rGJGbhlfO0g1YIDo=";
          };
          "x86_64-linux" = {
            url = "https://github.com/grafana/loki/releases/download/v${version}/logcli-linux-amd64.zip";
            hash = "sha256-YTs6k3G6xz+D0qLIlnu+QwrAyGYJijNtXHujPv5WYOA=";
          };
          "aarch64-linux" = {
            url = "https://github.com/grafana/loki/releases/download/v${version}/logcli-linux-arm64.zip";
            hash = "sha256-ohjbTGhTI6qaMnBO6vXjZY5fd1os0F7JZoc117R3NMw=";
          };
        };
        src = sources.${pkgs.stdenv.hostPlatform.system} or (throw "Unsupported system for logcli");
      in pkgs.stdenv.mkDerivation {
        pname = "logcli";
        inherit version;

        src = pkgs.fetchurl {
          inherit (src) url hash;
        };

        nativeBuildInputs = [ pkgs.unzip ];
        dontUnpack = true;

        installPhase = ''
          mkdir -p $out/bin
          unzip $src -d $out/bin
          mv $out/bin/logcli-* $out/bin/logcli
          chmod +x $out/bin/logcli
        '';

        meta = {
          description = "CLI for querying Grafana Loki";
          homepage = "https://grafana.com/docs/loki/latest/query/logcli/";
          platforms = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
        };
      };

      # mcp-cli for invoking MCP servers from CLI (built from source)
      mkMcpCli = pkgs: let
        version = "0.3.0-post";
        rev = "d77672a1ce800ec3fec1f43829909badb2ffbd32";

        src = pkgs.fetchFromGitHub {
          owner = "philschmid";
          repo = "mcp-cli";
          inherit rev;
          hash = "sha256-BlI81GumROJNHhav3H7bH9s1NfDYsEy3iwHowHYqfzc=";
        };

        # Fixed-output derivation: runs bun install with network access.
        # Hash is platform-specific because bun install produces native binaries.
        depsHashes = {
          "aarch64-darwin" = "sha256-v4eOACZLTjpYNDn29XjRY3BdwAi2ab0P3QMHOcYOFAU=";
          "x86_64-linux" = "sha256-BgCPeb8ZjO7SiJPkiAbWRi+bbsUdzzIwbBvnHoufviM=";
        };

        node_modules = pkgs.stdenv.mkDerivation {
          pname = "mcp-cli-deps";
          inherit version src;

          nativeBuildInputs = [ pkgs.bun ];

          buildPhase = ''
            export HOME=$TMPDIR
            bun install --frozen-lockfile
          '';

          installPhase = ''
            mkdir -p $out
            cp -r node_modules $out/node_modules
          '';

          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
          outputHash = depsHashes.${pkgs.stdenv.hostPlatform.system};
        };

      in pkgs.stdenv.mkDerivation {
        pname = "mcp-cli";
        inherit version src;

        nativeBuildInputs = [ pkgs.bun ];

        buildPhase = ''
          export HOME=$TMPDIR
          cp -r ${node_modules}/node_modules .
          bun build --compile --minify src/index.ts --outfile dist/mcp-cli
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp dist/mcp-cli $out/bin/real.mcp-cli
          cat > $out/bin/mcp-cli <<'WRAPPER'
          #!/usr/bin/env bash
          exec "$(dirname "$0")/real.mcp-cli" "$@" 2>/dev/null
          WRAPPER
          chmod +x $out/bin/mcp-cli
        '';

        meta = {
          description = "Lightweight CLI for interacting with MCP servers";
          homepage = "https://github.com/philschmid/mcp-cli";
          platforms = [ "aarch64-darwin" "x86_64-linux" ];
        };
      };
    in
    {
      # Development environments
      devShells = forEachSupportedSystem ({ pkgs }:
        let
          # Install managarr as .managarr to avoid name conflict with wrapper
          managarr-bin = pkgs.runCommand "managarr-bin" {} ''
            mkdir -p $out/bin
            ln -s ${pkgs.managarr}/bin/managarr $out/bin/.managarr
          '';

          pythonEnv = mkPythonEnv pkgs;

          # Replace dotnet-sdk with a stub to avoid building dotnet-vmr from
          # source on aarch64-darwin. The upstream pre-commit package takes
          # dotnet-sdk as a function argument for tests we don't run.
          # https://github.com/NixOS/nixpkgs/issues/294088
          pre-commit = pkgs.pre-commit.override {
            dotnet-sdk = pkgs.emptyDirectory;
          };

        in
        {
          default = pkgs.mkShell {
            # Pinned packages available in the environment
            packages = with pkgs; [
              act
              age
              ansible-lint
              pythonEnv
              awscli2
              curl
              jq
              kubernetes-helm
              kopia
              kubeconform
              kubecolor
              kubectl
              kustomize
              kyverno
              managarr-bin
              mosquitto
              nodejs_24
              opentofu
              pluto
              pre-commit
              rclone
              skopeo
              tflint
              uv
              velero
              yamlfix
              yq-go
              go-unifi-mcp.packages.${pkgs.stdenv.hostPlatform.system}.default
            ] ++ lib.optional (builtins.elem stdenv.hostPlatform.system [ "aarch64-darwin" "x86_64-linux" ]) (mkMcpCli pkgs)
              ++ lib.optional (builtins.elem stdenv.hostPlatform.system [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ]) (mkLogcli pkgs);

            shellHook = ''
              # Run pre-commit gc weekly
              _gc_marker=~/.cache/pre-commit-gc-last-run
              if [ ! -f "$_gc_marker" ] || [ -n "$(find "$_gc_marker" -mtime +7 2>/dev/null)" ]; then
                echo "Running pre-commit gc..."
                pre-commit gc && touch "$_gc_marker"
              fi

              # Run nix garbage collection weekly
              _nix_gc_marker=~/.cache/nix-gc-last-run
              if [ ! -f "$_nix_gc_marker" ] || [ -n "$(find "$_nix_gc_marker" -mtime +7 2>/dev/null)" ]; then
                echo "Running nix-collect-garbage..."
                nix-collect-garbage -d && rm -rf ~/.cache/nix/eval-cache-v[0-5] && touch "$_nix_gc_marker"
              fi
            '';
          };

          semaphore = pkgs.mkShell {
            packages = with pkgs; [
              pythonEnv
              opentofu
            ];
          };
        });
    };
}
