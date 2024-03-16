{ pkgs, config, ... }:

{

  users.defaultUserShell = pkgs.zsh;
  # Give extra permissions with Nix
  # nix.settings.trusted-users = [ "nils" ];

  # users.groups.nils = {
  #   gid = 1000;
  #   name = "nils";
  # };

  users.users.nils = {
    uid = 1000;
    isNormalUser = true;
    createHome = true;
    useDefaultShell = true;
    home = "/home/nils";
    extraGroups = [ "wheel" "networkmanager" "audio" "docker" ];
    openssh.authorizedKeys.keys =
      let
        authorizedKeys = pkgs.fetchurl {
          url = "https://github.com/tyriis.keys";
          sha256 = "HQJOzIzdTcapfYRMueESfmlWGaylteMBLU8AqqwMTS4=";
        };
      in
      pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  };

  users.users.jasmin = {
    isNormalUser = true;
    createHome = true;
    home = "/home/jasmin";
    extraGroups = [ "wheel" "networkmanager" "audio" "docker" ];
    openssh.authorizedKeys.keys =
      let
        authorizedKeys = pkgs.fetchurl {
          url = "https://github.com/jazzlyn.keys";
          sha256 = "Xeu/F1/mWxWwE4uN+Jar+R25ChQx0EEYZxE0E3Yxj5s=";
        };
      in
      pkgs.lib.splitString "\n" (builtins.readFile
        authorizedKeys);
  };

  # allow of sudo without password
  # security.sudo.wheelNeedsPassword = false;
}
