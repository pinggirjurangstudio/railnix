{
  description = "Declarative Railway monorepo configuration via Nix Flakes";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { ... }@inputs:
    let
      flakeModule = import ./.;
    in
    import ./mkflake.nix {
      inherit inputs;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        { perSystem = import ./.config/shell.nix; }
        { perSystem = import ./.config/treefmt.nix; }
        { flakeModules.default = flakeModule; }

        # NOTE: for testing purposes
        # nix flake check
        # nix run .#railnix init
        # nix run .#railnix plan
        # nix run .#railnix up development
        {
          imports = [ flakeModule ];

          railnix = {
            enable = true;

            project = {
              name = "railnix";
              defaultEnvironment = "production";
              src = ./.;
            };

            providers = {
              cloudflare.accountId = "my-cloudflare-account-id";
              railway = { };
            };

            services = {
              backend = {
                src = ./examples/backend;
                dependencies = [ ./examples/lib ];
              };
              frontend = {
                src = ./examples/frontend;
              };
            };

            environments.development.serviceInstances = {
              backend = { };
              frontend = { };
            };

            environments.production.serviceInstances = {
              backend = { };
              frontend = { };
            };
          };
        }
      ];
    };
}
