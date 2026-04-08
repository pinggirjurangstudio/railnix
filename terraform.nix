{
  lib,
  project,
  providers,
  services,
  environments,
  ...
}:

let
  inherit (providers) cloudflare;
  inherit (import ./lib.nix { inherit lib; }) mkRailwayPath;
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
      default_environment.name = project.defaultEnvironment;
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
    resource.railway_environment = lib.mapAttrs (name: environment: {
      inherit name;
      project_id = "\${railway_project.main.id}";
    }) (lib.filterAttrs (name: value: name != project.defaultEnvironment) environments);
  }

  # services
  {
    # https://registry.terraform.io/providers/terraform-community-providers/railway/latest/docs/resources/service
    resource.railway_service = lib.mapAttrs (
      name: service:
      let
        hasDeps = (service ? dependencies) && (lib.length service.dependencies > 0);
        src = mkRailwayPath project service.src;
      in
      {
        inherit name;
        project_id = "\${railway_project.main.id}";
        # https://docs.railway.com/builds/build-configuration#set-the-root-directory
        root_directory = if hasDeps then "/" else src;
        config_path = "${src}/railway.json";
      }
    ) services;
  }

]
