{ pkgs, ... }:

{
  # See: https://treefmt.com/latest/getting-started/configure/#config-file
  treefmt = {
    formatter = {
      nixfmt = {
        command = "${pkgs.nixfmt}/bin/nixfmt";
        includes = [ "*.nix" ];
      };
      yamlfmt = {
        command = "${pkgs.yamlfmt}/bin/yamlfmt";
        includes = [
          "*.yaml"
          "*.yml"
        ];
      };
      actionlint = {
        command = "${pkgs.actionlint}/bin/actionlint";
        includes = [
          ".github/workflows/*.yaml"
          ".github/workflows/*.yml"
        ];
      };
    };
  };
}
