# A lightweight, modular Nix Flakes outputs builder designed to be vendored.
#
# Vendoring this file by using the following template:
# nix flake init -t github:pinggirjurangstudio/mkflake
#
# Usage:
# {
#   inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
#   outputs =
#     { ... }@inputs:
#     import ./mkflake.nix {
#       inherit inputs;
#       systems = [ "aarch64-darwin" ];
#       imports = [ ./your-module.nix ];
#     };
# }
#
# For more information, see: https://github.com/pinggirjurangstudio/mkflake

{
  inputs,
  systems ? [ ],
  imports ? [ ],
}:

let
  inherit (inputs) self nixpkgs;
  inherit (nixpkgs) lib;
  inherit (lib) types;
  mkOption = type: description: lib.mkOption { inherit type description; };
  mkOption' =
    type: default: description:
    lib.mkOption { inherit type default description; };
  assertion = types.submodule {
    options.assertion = mkOption types.bool "Whether the condition is met.";
    options.message = mkOption types.str "The error message to display to the user if the assertion fails.";
  };

  _global = rec {
    submodule = {
      freeform = types.submodule { freeformType = types.attrsOf types.unspecified; };
    };
    schema.options = {
      templates =
        mkOption' (types.attrsOf types.unspecified) { }
          "A set of templates for initializing new projects via `nix flake init`.";
      nixosModules =
        mkOption' (types.attrsOf types.unspecified) { }
          "Reusable NixOS modules that can be imported into other NixOS configurations.";
      nixosConfigurations =
        mkOption' (types.attrsOf types.unspecified) { }
          "Instantiated NixOS systems defined by this flake.";
      overlays =
        mkOption' (types.attrsOf types.unspecified) { }
          "Nixpkgs overlays used to modify or extend the package set.";
      flakeModules =
        mkOption' (types.attrsOf types.unspecified) { }
          "Custom modules intended for use in other flakes.";
      lib =
        mkOption' (types.attrsOf types.unspecified) { }
          "A set of library functions exported by this flake for use in Nix expressions.";
      perSystem = mkOption' (types.deferredModule
      ) { } "Configuration block for system-specific attributes like `packages` and `devShells`.";
      flake =
        mkOption' submodule.freeform { }
          "A raw attribute set to be merged directly into the final flake outputs.";
      assertions =
        mkOption' (types.listOf assertion) [ ]
          "A list of conditions that must be true for the flake evaluation to succeed.";
    };
    eval = lib.evalModules {
      specialArgs = inputs;
      modules = [ schema ] ++ imports;
    };
  };

  _perSystem = rec {
    submodule = {
      treefmt = types.submodule {
        options.excludes =
          mkOption' (types.listOf types.str) [ ]
            "Exclude files or directories matching the specified globs.";
        options.formatter =
          mkOption' (types.attrsOf submodule.formatter) { }
            "A set of formatters to apply.";
      };
      formatter = types.submodule {
        options.command = mkOption (types.either types.path types.str) "Command to execute.";
        options.includes = mkOption (types.listOf types.str) "Glob pattern of files to include.";
        options.excludes = mkOption' (types.listOf types.str) [ ] "Glob patterns of files to exclude.";
        options.options = mkOption' (types.listOf types.str) [ ] "Command-line arguments for the command.";
      };
    };
    schema.options = {
      checks =
        mkOption' (types.attrsOf types.package) { }
          "Automated tests and CI tasks (e.g., linter checks).";
      formatter =
        mkOption' (types.nullOr types.package) null
          "The default package used to format code when running `nix fmt`.";
      devShells =
        mkOption' (types.attrsOf types.package) { }
          "Development environments accessible via `nix develop`.";
      packages =
        mkOption' (types.attrsOf types.package) { }
          "Standard packages exported by this flake, buildable via `nix build`.";
      legacyPackages =
        mkOption' (types.attrsOf types.package) { }
          "A large set of packages, typically used for nixpkgs aliases.";
      apps =
        mkOption' (types.attrsOf types.unspecified) { }
          "Executables that can be run directly via `nix run`.";
      treefmt = mkOption' (submodule.treefmt
      ) { } "Configuration for the `treefmt` integration to manage multiple formatters.";
      assertions =
        mkOption' (types.listOf assertion) [ ]
          "System-specific list of conditions that must be true for the flake evaluation to succeed.";
    };
    eval = lib.genAttrs systems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        perSystemConfig = _global.eval.config.perSystem;
      in
      lib.evalModules {
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
                    cp -r ${self} $PRJ
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
              globalAssertions = map (a: a // { system = null; }) (_global.eval.config.assertions or [ ]);
              perSystemAssertions = map (a: a // { inherit system; }) (config.assertions or [ ]);
              failedAssertions = lib.filter (a: !(a.assertion)) (globalAssertions ++ perSystemAssertions);
              mkflakeCheck = pkgs.runCommandLocal "mkflake-check" { } ''
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
              checks.mkflake = mkflakeCheck;
            }
          )
        ];
      }
    );
  };

  removeEmptyAttrs = lib.filterAttrs (_: v: v != { } && v != null);
  mapSystems = attr: removeEmptyAttrs (lib.mapAttrs (_: eval: eval.config.${attr}) _perSystem.eval);
in

removeEmptyAttrs {
  debug.mkflake = {
    global = _global.eval.options;
  }
  // (lib.mapAttrs (_: eval: eval.options) _perSystem.eval);
  inherit (_global.eval.config)
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
// _global.eval.config.flake
