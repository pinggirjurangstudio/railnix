{ pkgs, ... }:

{
  # See: https://treefmt.com/latest/getting-started/configure/#config-file
  treefmt = {
    formatter = {

      nixfmt = {
        command = "${pkgs.nixfmt}/bin/nixfmt";
        includes = [ "*.nix" ];
      };

      shfmt = {
        command = "${pkgs.shfmt}/bin/shfmt";
        options = [ "-w" ];
        includes = [
          "*.sh"
          "*.envrc"
        ];
      };

      prettier = {
        command = "${pkgs.prettier}/bin/prettier";
        options = [ "--write" ];
        includes = [
          "*.md"
          "*.json"
          "*.yaml"
          "*.yml"
        ];
        excludes = [ ".zed/*.json" ];
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
