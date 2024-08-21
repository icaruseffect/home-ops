# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/74ec33a5-34db-4a36-9c4b-fea37895c33d";
      fsType = "btrfs";
      options = [ "subvol=root" "rw" "noatime" "discard=async" "compress-force=zstd" "space_cache=v2" "commit=120" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/74ec33a5-34db-4a36-9c4b-fea37895c33d";
      fsType = "btrfs";
      options = [ "subvol=home" "rw" "noatime" "discard=async" "compress-force=zstd" "space_cache=v2" "commit=120" ];
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/74ec33a5-34db-4a36-9c4b-fea37895c33d";
      fsType = "btrfs";
      options = [ "subvol=nix" "rw" "noatime" "discard=async" "compress-force=zstd" "space_cache=v2" "commit=120" ];
    };

  fileSystems."/var/log" =
    { device = "/dev/disk/by-uuid/74ec33a5-34db-4a36-9c4b-fea37895c33d";
      fsType = "btrfs";
      options = [ "subvol=log" "rw" "noatime" "discard=async" "compress-force=zstd" "space_cache=v2" "commit=120" ];
      neededForBoot = true;
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/70E7-0821";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/092c4721-94c2-4e87-9c1a-f6b4b9161e4d"; }
    ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp4s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
