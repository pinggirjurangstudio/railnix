# A modular flake outputs builder.
#
# Vendoring this file by using the following template:
# nix flake init -t sourcehut:~bzm/smoothflake#lib
#
# Usage:
# {
#   inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
#   outputs =
#     { nixpkgs, ... }@inputs:
#     import ./mkflake.nix {
#       inherit nixpkgs inputs;
#       systems = [ "aarch64-darwin" ];
#       imports = [ ./your-module.nix ];
#     };
# }
#
# For more information, see: https://git.sr.ht/~bzm/smoothflake

{
  nixpkgs,
  inputs,
  systems ? [ ],
  imports ? [ ],
}:

let
  inherit (nixpkgs) lib;
  inherit (lib) types;
  mkOption = type: lib.mkOption { inherit type; };
  mkOption' = type: default: lib.mkOption { inherit type default; };
  assertion = types.submodule {
    options.assertion = mkOption types.bool;
    options.message = mkOption types.str;
  };

  _global = rec {
    submodule = {
      freeform = types.submodule { freeformType = types.attrsOf types.unspecified; };
    };
    schema.options = {
      templates = mkOption' (types.attrsOf types.unspecified) { };
      nixosModules = mkOption' (types.attrsOf types.unspecified) { };
      nixosConfigurations = mkOption' (types.attrsOf types.unspecified) { };
      overlays = mkOption' (types.attrsOf types.unspecified) { };
      flakeModules = mkOption' (types.attrsOf types.unspecified) { };
      lib = mkOption' (types.attrsOf types.unspecified) { };
      perSystem = mkOption' (types.deferredModule) { };
      flake = mkOption' submodule.freeform { };
      assertions = mkOption' (types.listOf assertion) [ ];
    };
    config =
      (lib.evalModules {
        specialArgs = inputs;
        modules = [ schema ] ++ imports;
      }).config;
  };

  _perSystem = rec {
    submodule = {
      treefmt = types.submodule {
        options.excludes = mkOption' (types.listOf types.str) [ ];
        options.formatter = mkOption' (types.attrsOf submodule.formatter) { };
      };
      formatter = types.submodule {
        options.command = mkOption (types.either types.path types.str);
        options.includes = mkOption (types.listOf types.str);
        options.excludes = mkOption' (types.listOf types.str) [ ];
        options.options = mkOption' (types.listOf types.str) [ ];
      };
    };
    schema.options = {
      checks = mkOption' (types.attrsOf types.package) { };
      formatter = mkOption' (types.nullOr types.package) null;
      devShells = mkOption' (types.attrsOf types.package) { };
      packages = mkOption' (types.attrsOf types.package) { };
      legacyPackages = mkOption' (types.attrsOf types.package) { };
      apps = mkOption' (types.attrsOf types.unspecified) { };
      treefmt = mkOption' (submodule.treefmt) { };
      assertions = mkOption' (types.listOf assertion) [ ];
    };
    config = lib.genAttrs systems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        perSystemConfig = _global.config.perSystem;
      in
      (lib.evalModules {
        specialArgs = inputs;
        modules = [
          schema
          {
            _module.args.pkgs = lib.mkDefault pkgs;
            _module.args.system = system;
          }
          perSystemConfig
          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              # this part code are stripped version of
              # https://github.com/numtide/treefmt-nix/blob/dec15f37015ac2e774c84d0952d57fcdf169b54d/module-options.nix
              treefmtConfig = (pkgs.formats.toml { }).generate "treefmt.toml" config.treefmt;
              treefmtFormatter = pkgs.writeShellScriptBin "treefmt" ''
                set -euo pipefail
                unset PRJ_ROOT
                exec ${pkgs.treefmt}/bin/treefmt \
                  --config-file=${treefmtConfig} \
                  --tree-root-file=flake.nix \
                  "$@"
              '';
              treefmtCheck =
                pkgs.runCommandLocal "treefmt-check"
                  {
                    buildInputs = [
                      pkgs.git
                      pkgs.git-lfs
                      treefmtFormatter
                    ];
                  }
                  ''
                    set -e
                    PRJ=$TMP/project
                    cp -r ${inputs.self} $PRJ
                    chmod -R a+w $PRJ
                    cd $PRJ
                    export HOME=$TMPDIR
                    cat > $HOME/.gitconfig <<EOF
                    [user]
                      name = Nix
                      email = nix@localhost
                    [init]
                      defaultBranch = main
                    EOF
                    git init --quiet
                    git add .
                    git commit -m init --quiet
                    export LANG=${if pkgs.stdenv.isDarwin then "en_US.UTF-8" else "C.UTF-8"}
                    export LC_ALL=${if pkgs.stdenv.isDarwin then "en_US.UTF-8" else "C.UTF-8"}
                    treefmt --version
                    treefmt --no-cache
                    git status --short
                    git --no-pager diff --exit-code
                    touch $out
                  '';
              globalAssertions = map (a: a // { system = null; }) (_global.config.assertions or [ ]);
              perSystemAssertions = map (a: a // { inherit system; }) (config.assertions or [ ]);
              failedAssertions = lib.filter (a: !(a.assertion)) (globalAssertions ++ perSystemAssertions);
              smoothflakeCheck = pkgs.runCommandLocal "smoothflake-check" { } ''
                ${
                  if failedAssertions != [ ] then
                    throw ''

                      Failed assertions:
                      ${lib.concatStringsSep "\n" (map (a: "- ${a.message}") failedAssertions)}
                    ''
                  else
                    "echo 'All assertions are passed' > $out"
                }
              '';
            in
            {
              formatter = lib.mkDefault treefmtFormatter;
              checks.treefmt = lib.mkDefault treefmtCheck;
              checks.smoothflake = smoothflakeCheck;
            }
          )
        ];
      }).config
    );
  };

  removeEmptyAttrs = lib.filterAttrs (_: v: v != { } && v != null);
  mapSystems = attr: removeEmptyAttrs (lib.mapAttrs (_: cfg: cfg.${attr}) _perSystem.config);
in

removeEmptyAttrs {
  inherit (_global.config)
    templates
    nixosModules
    nixosConfigurations
    overlays
    flakeModules
    lib
    ;
  checks = mapSystems "checks";
  formatter = mapSystems "formatter";
  devShells = mapSystems "devShells";
  packages = mapSystems "packages";
  legacyPackages = mapSystems "legacyPackages";
  apps = mapSystems "apps";
}
// _global.config.flake
