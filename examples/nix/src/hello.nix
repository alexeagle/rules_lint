{ pkgs, ... }: {
  packages = [
    pkgs.hello
    pkgs.cowsay
  ];
}
