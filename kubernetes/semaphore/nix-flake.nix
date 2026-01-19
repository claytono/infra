# DO NOT EDIT - This is a copy. Edit the original in the repo root.
{
  description = "Development environment flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  # Flake outputs that other flakes can use
  outputs = { self, nixpkgs }:
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
            ];

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
