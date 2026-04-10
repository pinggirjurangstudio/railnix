{ config, lib, ... }:

let
  cfg = config.railnix;

  inherit (lib) types mkOption mkEnableOption;
  inherit (import ./lib.nix { inherit lib; })
    mkTerraformConfig
    mkSecretOption
    mkRailwayPath
    mkRelativePath
    ;

  providersSubmodule = types.submodule {
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

  projectSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
      };
      root = mkOption {
        type = types.path;
      };
    };
  };

  environmentsSubmodule = types.submodule {
    options = {
      allowed = mkOption {
        type = types.listOf types.str;
      };
      default = mkOption {
        type = types.str;
      };
    };
  };

  servicesSubmodule = types.submodule (
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = lib.baseNameOf config.relativePath;
        };
        dependencies = mkOption {
          type = types.listOf types.path;
          default = [ ];
        };
        environments = mkOption {
          type = types.attrsOf (
            types.submodule (
              { name, ... }:
              {
                config.name = name;
                options = {
                  name = mkOption {
                    type = types.str;
                    internal = true;
                  };
                };
              }
            )
          );
          default = { };
        };
        relativePath = mkOption {
          type = types.str;
          internal = true;
        };
        railwayPath = mkOption {
          type = types.str;
          internal = true;
        };
        generatedConfig = mkOption {
          type = types.unspecified;
          internal = true;
        };
      };
      config.generatedConfig = {
        "$schema" = "https://railway.com/railway.schema.json";
        build = {
          dockerfilePath = "${config.railwayPath}/Dockerfile";
          watchPatterns = [
            "${config.railwayPath}/**"
          ]
          ++ (lib.map (dep: "${mkRailwayPath cfg.project dep}/**") config.dependencies);
        };
      };
    }
  );
in

{
  options.railnix = {
    enable = mkEnableOption "railnix";
    providers = mkOption {
      type = providersSubmodule;
    };
    project = mkOption {
      type = projectSubmodule;
    };
    environments = mkOption {
      type = environmentsSubmodule;
    };
    services = mkOption {
      type = types.listOf (
        types.coercedTo types.path (
          p:
          let
            service = import p;
            servicePath = if lib.pathType p == "directory" then p else lib.dirOf p;
          in
          {
            railwayPath = mkRailwayPath cfg.project servicePath;
            relativePath = mkRelativePath cfg.project servicePath;
          }
          // service
        ) servicesSubmodule
      );
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.elem cfg.environments.default cfg.environments.allowed;
        message = ''
          Default environment '${cfg.environments.default}' is not in the allowed environments list.
          Allowed environments are: ${lib.concatStringsSep ", " cfg.environments.allowed}.
        '';
      }
    ]
    ++ lib.flatten (
      lib.map (
        service:
        lib.mapAttrsToList (_: environment: {
          assertion = lib.elem environment.name cfg.environments.allowed;
          message = ''
            Service '${service.name}' references undefined environment '${environment.name}'.
            Allowed environments are: ${lib.concatStringsSep ", " cfg.environments.allowed}.
          '';
        }) service.environments
      ) cfg.services
    );

    lib = {
      generateTerraformConfig = (
        args:
        mkTerraformConfig {
          modules = [ ./terraform.nix ];
          specialArgs = {
            inherit (cfg)
              providers
              project
              environments
              services
              ;
          };
        }
      );

      generateDeploymentPlan = (
        environment:
        if !lib.elem environment cfg.environments.allowed then
          throw "Environment '${environment}' not found in 'environments.allowed'."
        else
          lib.listToAttrs (
            lib.map (service: {
              name = service.name;
              value = {
                config = service.generatedConfig;
                path = service.relativePath;
              };
            }) (lib.filter (service: lib.hasAttr environment service.environments) cfg.services)
          )
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
            terraformConfig = self.lib.generateTerraformConfig { };
            deploymentPlans = lib.map (
              environment: self.lib.generateDeploymentPlan environment
            ) cfg.environments.allowed;
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
