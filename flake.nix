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
    in
    {

      # Development environments
      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          # Pinned packages available in the environment
          packages = with pkgs; [
            act
            ansible
            ansible-lint
            awscli2
            curl
            jq
            kubeconform
            kubectl
            kustomize
            mosquitto
            nodejs_24
            opentofu
            pluto
            pre-commit
            python3
            python3Packages.pyyaml
            skopeo
            tflint
            trivy
            yamlfix
            yq-go
          ];
        };
      });


    };
}
