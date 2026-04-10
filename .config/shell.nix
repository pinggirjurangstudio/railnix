{ pkgs, ... }:

{
  devShells.default = pkgs.mkShell {
    name = "railnix";
    packages = with pkgs; [
      railway
      opentofu
      jq
    ];
    RAILWAY_NO_TELEMETRY = 1;
  };
}
