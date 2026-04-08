{ pkgs, ... }:

{
  devShells.default = pkgs.mkShell {
    name = "railnix";
    packages = with pkgs; [
      railway
      opentofu
    ];
    RAILWAY_NO_TELEMETRY = 1;
  };
}
