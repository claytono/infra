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
      devShells = forEachSupportedSystem ({ pkgs }:
        let
          # Install recyclarr as .recyclarr to avoid name conflict with wrapper
          recyclarr-bin = pkgs.runCommand "recyclarr-bin" {} ''
            mkdir -p $out/bin
            ln -s ${pkgs.recyclarr}/bin/recyclarr $out/bin/.recyclarr
          '';
          # Install managarr as .managarr to avoid name conflict with wrapper
          managarr-bin = pkgs.runCommand "managarr-bin" {} ''
            mkdir -p $out/bin
            ln -s ${pkgs.managarr}/bin/managarr $out/bin/.managarr
          '';
        in
        {
          default = pkgs.mkShell {
            # Pinned packages available in the environment
            packages = with pkgs; [
              act
              ansible
              ansible-lint
              awscli2
              curl
              jq
              kopia
              kubeconform
              kubecolor
              kubectl
              kustomize
              managarr-bin
              mosquitto
              nodejs_24
              opentofu
              pluto
              pre-commit
              recyclarr-bin
              # Python with required packages
              (python3.withPackages (ps: with ps; [
                jinja2
                pyyaml
                ruamel-yaml
              ]))
              rclone
              skopeo
              tflint
              velero
              yamlfix
              yq-go
            ];
          };
        });
    };
}
