{ config, pkgs, lib, ... }:

let
  # 1. Configuration: Version and Source
  version = "0.0.1";
  
  # 2. Package Definition
  # This downloads the zip and patches binaries for NixOS compatibility
  dataloggerBin = pkgs.stdenv.mkDerivation {
    pname = "datalogger-services";
    inherit version;

    src = pkgs.fetchzip {
      url = "https://github.com/sudhanshunitinatalkar/datalog-bin/releases/download/v${version}/release.zip";
      
      # [IMPORTANT] REPLACE THIS WITH THE HASH FROM: nix-prefetch-url --unpack <url>
      sha256 = "16xifrxdxan4sf558s22d5ki96440xvn9q6xwh7ci3yyan18qbl7"; 
      
      # We manually handle the folder structure to be safe
      stripRoot = false;
    };

    # Automatically fix binary paths (interpreter/libs) for NixOS
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];

    # Runtime dependencies (Common libs; add more here if a binary crashes)
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];

    installPhase = ''
      mkdir -p $out/bin
      
      # Extract from the nested structure: release/datalogger-0.0.1/
      # We move all binaries directly to $out/bin for easier access
      cp -r release/datalogger-${version}/* $out/bin/
      
      # Ensure they are executable
      chmod +x $out/bin/*
    '';
  };

  # 3. Service List (Ignoring 'diag' as requested)
  binaryNames = [ 
    "configure" 
    "cpcb" 
    "data" 
    "datalogger" 
    "display" 
    "network" 
    "saicloud" 
  ];

  # 4. Service Generator
  mkService = name: {
    name = "datalogger-${name}";
    value = {
      description = "Datalogger Service: ${name}";
      wantedBy = [ "multi-user.target" ]; # Runs on boot
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      serviceConfig = {
        # Points directly to the patched binary in the Nix store
        ExecStart = "${dataloggerBin}/bin/${name}";
        
        # Crash recovery
        Restart = "always";
        RestartSec = "5s";
        
        # Run as root (System Service)
        User = "root";
      };
    };
  };

in
{
  # Generate all services from the list
  systemd.services = builtins.listToAttrs (map mkService binaryNames);
}