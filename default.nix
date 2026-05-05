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
        description = "Cloudflare provider configuration.";
        type = types.submodule {
          options = {
            accountId = mkOption {
              description = "The Cloudflare Account ID.";
              type = types.str;
            };
            apiToken = mkSecretOption "CLOUDFLARE_API_TOKEN";
            accessKey = mkSecretOption "AWS_ACCESS_KEY_ID";
            secretKey = mkSecretOption "AWS_SECRET_ACCESS_KEY";
          };
        };
      };
      railway = mkOption {
        description = "Railway provider configuration.";
        type = types.submodule {
          options = {
            apiToken = mkSecretOption "RAILWAY_API_TOKEN";
          };
        };
      };
    };
  };

  projectSubmodule = types.submodule {
    options = {
      name = mkOption {
        description = "The name of the project, used as a prefix or identifier in cloud resources.";
        type = types.str;
      };
      root = mkOption {
        description = "The absolute path to the root of the project repository.";
        type = types.path;
      };
    };
  };

  environmentsSubmodule = types.submodule {
    options = {
      allowed = mkOption {
        description = "A list of valid environment names (e.g., `development`, `production`).";
        type = types.listOf types.str;
      };
      default = mkOption {
        description = "The default environment, must be one of the allowed environments.";
        type = types.str;
      };
    };
  };

  servicesSubmodule = types.submodule (
    { config, ... }:
    {
      options = {
        name = mkOption {
          description = "The service name. Defaults to the directory name of the service.";
          type = types.str;
          default = lib.baseNameOf config.relativePath;
        };
        dependencies = mkOption {
          description = "A list of local paths to other services or files this service depends on.";
          type = types.listOf types.path;
          default = [ ];
        };
        environments = mkOption {
          description = "Environment-specific configurations for the service.";
          type = types.attrsOf (
            types.submodule (
              { name, ... }:
              {
                config.name = name;
                options = {
                  name = mkOption {
                    description = "Environment name.";
                    type = types.str;
                    internal = true;
                  };
                  domains = mkOption {
                    description = "List of domain for this specific environment.";
                    type = types.attrsOf types.str;
                    default = { };
                  };
                };
              }
            )
          );
          default = { };
        };
        build = mkOption {
          description = "Build configurations for the service.";
          type = types.submodule {
            options = {
              builder = mkOption {
                description = "The build strategy to use (defaulting to DOCKERFILE).";
                type = types.str;
                internal = true;
                default = "DOCKERFILE";
              };
              watchPatterns = mkOption {
                description = "File patterns that trigger a rebuild when changed.";
                type = types.listOf types.str;
                internal = true;
                default = [
                  "${config.railwayPath}/**"
                ]
                ++ (lib.map (dep: "${mkRailwayPath cfg.project dep}/**") config.dependencies);
              };
              dockerfilePath = mkOption {
                description = "Path to the Dockerfile relative to the project root.";
                type = types.str;
                internal = true;
                default = "${config.railwayPath}/Dockerfile";
              };
            };
          };
          default = { };
        };
        deploy = mkOption {
          description = "Deploy configurations for the service.";
          type = types.submodule {
            options = {
              healthcheckPath = mkOption {
                description = "HTTP endpoint path for Railway healthchecks.";
                type = types.nullOr types.str;
                default = null;
              };
              healthcheckTimeout = mkOption {
                description = "Time in seconds to wait before a healthcheck is considered failed.";
                type = types.nullOr types.int;
                default = null;
              };
            };
          };
          default = { };
        };
        relativePath = mkOption {
          description = "Path of the service relative to the project root.";
          type = types.str;
          internal = true;
        };
        railwayPath = mkOption {
          description = "The path format required specifically for Railway deployment configuration.";
          type = types.str;
          internal = true;
        };
      };
    }
  );
in

{
  options.railnix = {
    enable = mkEnableOption "railnix";
    providers = mkOption {
      description = "Credentials and settings for cloud providers.";
      type = providersSubmodule;
    };
    project = mkOption {
      description = "A project metadata.";
      type = projectSubmodule;
    };
    environments = mkOption {
      description = "Configuration for deployment environments.";
      type = environmentsSubmodule;
    };
    services = mkOption {
      description = "A list of services to be managed, defined by their filesystem paths.";
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
                config = {
                  "$schema" = "https://railway.com/railway.schema.json";
                  inherit (service) build deploy;
                };
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
