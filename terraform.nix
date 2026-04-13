{
  lib,
  providers,
  project,
  environments,
  services,
  ...
}:

let
  inherit (providers) cloudflare;
in

lib.mkMerge [

  # providers
  {
    # https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs
    terraform.required_providers.cloudflare = {
      source = "cloudflare/cloudflare";
      version = "~> 5";
    };

    # https://registry.terraform.io/providers/terraform-community-providers/railway/latest/docs
    terraform.required_providers.railway = {
      source = "terraform-community-providers/railway";
      version = "~> 0.6";
    };
  }

  # backend
  {
    # https://developers.cloudflare.com/terraform/advanced-topics/remote-backend
    terraform.backend.s3 = {
      endpoints.s3 = "https://${cloudflare.accountId}.r2.cloudflarestorage.com";
      bucket = "tfstate";
      key = "${project.name}/terraform.tfstate";
      region = "auto";
      skip_credentials_validation = true;
      skip_metadata_api_check = true;
      skip_region_validation = true;
      skip_requesting_account_id = true;
      skip_s3_checksum = true;
      use_path_style = true;
    };
  }

  # project
  {
    # https://registry.terraform.io/providers/terraform-community-providers/railway/latest/docs/resources/project
    resource.railway_project.main = {
      inherit (project) name;
      default_environment.name = environments.default;
    };

    output = {
      project_name = {
        value = project.name;
      };
      project_id = {
        value = "\${railway_project.main.id}";
      };
    };
  }

  # environments
  {
    # https://registry.terraform.io/providers/terraform-community-providers/railway/latest/docs/resources/environment
    resource.railway_environment = lib.listToAttrs (
      lib.map (environment: {
        name = environment;
        value = {
          name = environment;
          project_id = "\${railway_project.main.id}";
        };
      }) (lib.filter (environment: environment != environments.default) environments.allowed)
    );
  }

  # services
  {
    # https://registry.terraform.io/providers/terraform-community-providers/railway/latest/docs/resources/service
    resource.railway_service = lib.listToAttrs (
      lib.map (service: {
        name = service.name;
        value =
          let
            defaultEnvDep = "railway_project.main";
            allowedEnvDeps = lib.map (environment: "railway_environment.${environment}") (
              lib.filter (environment: environment != environments.default) environments.allowed
            );
            envDeps = [ defaultEnvDep ] ++ allowedEnvDeps;
          in
          {
            inherit (service) name;
            project_id = "\${railway_project.main.id}";
            depends_on = envDeps;
          };
      }) services
    );
  }

  # domains
  {
    resource.railway_custom_domain = lib.listToAttrs (
      lib.concatLists (
        lib.map (
          service:
          lib.concatLists (
            lib.mapAttrsToList (
              _: environment:
              lib.mapAttrsToList (domainKey: domainValue: {
                name = "${service.name}_${environment.name}_${domainKey}";
                value = {
                  domain = domainValue;
                  service_id = "\${railway_service.${service.name}.id}";
                  environment_id =
                    if environment.name == environments.default then
                      "\${railway_project.main.default_environment.id}"
                    else
                      "\${railway_environment.${environment.name}.id}";
                };
              }) environment.domains
            ) service.environments
          )
        ) services
      )
    );
  }
]
