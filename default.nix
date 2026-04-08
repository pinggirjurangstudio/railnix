{ config, lib, ... }:

let
  inherit (lib) types mkOption mkEnableOption;
  inherit (import ./lib.nix { inherit lib; })
    mkTerraformConfig
    mkSecretOption
    mkRailwayPath
    mkRelativePath
    ;

  project = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
      };
      defaultEnvironment = mkOption {
        type = types.str;
      };
      src = mkOption {
        type = types.path;
      };
    };
  };

  providers = types.submodule {
    options = {
      cloudflare = mkOption {
        type = types.submodule {
          options = {
            accountId = mkOption {
              type = types.str;
            };
            apiToken = mkSecretOption "CLOUDFLARE_API_TOKEN";
            accessKey = mkSecretOption "AWS_ACCESS_KEY_ID";
            secretKey = mkSecretOption "AWS_SECRET_ACCESS_KEY";
          };
        };
      };
      railway = mkOption {
        type = types.submodule {
          options = {
            apiToken = mkSecretOption "RAILWAY_TOKEN";
          };
        };
      };
    };
  };

  service = types.submodule (
    { config, ... }:
    let
      src = mkRailwayPath cfg.project config.src;
    in
    {
      options = {
        src = mkOption {
          type = types.path;
        };
        dependencies = mkOption {
          type = types.listOf types.path;
          default = [ ];
        };
        generatedConfig = mkOption {
          type = types.unspecified;
          internal = true;
        };
      };
      config.generatedConfig = {
        "$schema" = "https://railway.com/railway.schema.json";
        build = {
          dockerfilePath = "${src}/Dockerfile";
          watchPatterns = [
            "${src}/**"
          ]
          ++ (lib.map (dep: "${mkRailwayPath cfg.project dep}/**") config.dependencies);
        };
      };
    }
  );

  environment = types.submodule {
    options = {
      serviceInstances = mkOption {
        type = types.attrsOf serviceInstance;
        default = { };
      };
    };
  };

  # NOTE: serviceInstance still unutilize
  # TODO: use serviceInstance for generating domain and variable terraform resource
  serviceInstance = types.submodule {
    options = {
      domain = mkOption {
        type = types.str;
      };
    };
  };

  cfg = config.railnix;
in

{
  options.railnix = {
    enable = mkEnableOption "railnix";
    project = mkOption {
      type = project;
    };
    providers = mkOption {
      type = providers;
    };
    services = mkOption {
      type = types.attrsOf service;
    };
    environments = mkOption {
      type = types.attrsOf environment;
    };
  };

  config = lib.mkIf cfg.enable {
    lib = {
      generateTerraformConfig = (
        args:
        mkTerraformConfig {
          modules = [ ./terraform.nix ];
          specialArgs = {
            inherit (cfg)
              project
              providers
              services
              environments
              ;
          };
        }
      );

      generateDeploymentPlan = (
        environment:
        if !lib.hasAttr environment cfg.environments then
          throw "Environment ${environment} not found"
        else
          lib.mapAttrs (name: serviceInstance: {
            config = cfg.services.${name}.generatedConfig;
            src = mkRelativePath cfg.project cfg.services.${name}.src;
          }) cfg.environments.${environment}.serviceInstances
      );
    };

    perSystem =
      { self, pkgs, ... }:
      {
        packages.railnix = pkgs.writeShellApplication {
          name = "railnix";
          runtimeInputs = with pkgs; [
            jq
            opentofu
            railway
          ];
          text = lib.readFile ./railnix.sh;
        };

        checks.railnix =
          let
            environments = lib.attrNames cfg.environments;
            terraformConfig = self.lib.generateTerraformConfig { };
            deploymentPlans = lib.map (environment: self.lib.generateDeploymentPlan environment) environments;
            result = lib.toJSON {
              inherit terraformConfig deploymentPlans;
            };
          in
          pkgs.runCommandLocal "railnix-check"
            {
              inherit result;
              passAsFile = [ "result" ];
            }
            ''
              cat "$resultPath" > /dev/null
              echo "All assertions are passed" > $out
            '';
      };
  };
}
