# nix/hive.nix
let
  flake = builtins.getFlake (toString ./.);
in
  flake.colmena
