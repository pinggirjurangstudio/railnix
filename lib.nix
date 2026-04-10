{ lib }:

let
  inherit (lib) mkOption types;

  terraformSchema = {
    options = {
      terraform = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
      provider = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
      resource = mkOption {
        type = types.attrsOf (types.attrsOf types.anything);
        default = { };
      };
      data = mkOption {
        type = types.attrsOf (types.attrsOf types.anything);
        default = { };
      };
      variable = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
      output = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
      locals = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
      module = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
    };
  };
in

{
  mkTerraformConfig =
    {
      modules,
      specialArgs ? { },
    }:
    let
      eval = lib.evalModules {
        specialArgs = {
          inherit lib;
        }
        // specialArgs;
        modules = [ terraformSchema ] ++ modules;
      };
    in
    lib.filterAttrs (_: v: v != { } && v != null) eval.config;

  mkSecretOption =
    var:
    mkOption {
      type = types.str;
      default = "";
      description = "This option doesn't do anything, you should put apiToken in ${var}.";
    };

  mkRailwayPath =
    project: targetPath:
    let
      exists = lib.pathExists targetPath;
    in
    if !exists then
      throw "Path '${toString targetPath}' does not exist. Check your 'railnix' configuration."
    else
      lib.removePrefix (lib.toString project.root) (lib.toString targetPath);

  mkRelativePath =
    project: targetPath:
    let
      exists = lib.pathExists targetPath;
    in
    if !exists then
      throw "Path '${toString targetPath}' does not exist. Check your 'railnix' configuration."
    else
      lib.path.removePrefix project.root targetPath;
}
