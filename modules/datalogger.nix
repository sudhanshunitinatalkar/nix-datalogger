{ config, pkgs, lib, ... }:

let
  # --- RELEASE CONFIGURATION ---
  # Update these when you make a new release on GitHub
  releaseVersion = "v1.0.0"; 
  githubUser = "sudhanshunitinatalkar";
  githubRepo = "datalogger-bin"; 
  
  # Fetch binaries (Update hashes after uploading your release!)
  fetchServiceBin = name: hash: pkgs.fetchurl {
    url = "https://github.com/${githubUser}/${githubRepo}/releases/download/${releaseVersion}/${name}";
    sha256 = hash;
  };

  # Define services and their hashes
  binaries = {
    datalogger = fetchServiceBin "datalogger" "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    network    = fetchServiceBin "network"    "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
    display    = fetchServiceBin "display"    "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
    configure  = fetchServiceBin "configure"  "sha256-DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=";
    saicloud   = fetchServiceBin "saicloud"   "sha256-EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE=";
    cpcb       = fetchServiceBin "cpcb"       "sha256-FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF=";
    data       = fetchServiceBin "data"       "sha256-GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG=";
  };

  # --- DIRECTORY PATHS ---
  baseDir = "${config.home.homeDirectory}/datalogger-bin";
  binDir  = "${baseDir}/bin";
  # [FIX] This is the persistent temp folder in your Home directory
  tmpDir  = "${baseDir}/tmp";

  # --- SERVICE GENERATOR ---
  mkService = name: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${binDir}/${name}";
      
      # [FIX] Force PyInstaller to unpack in home dir instead of /tmp
      Environment = "TMPDIR=${tmpDir}";

      # Robustness settings
      Restart = "always";
      RestartSec = "5s";
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";
      
      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

in
{
  # 1. INSTALLATION SCRIPT
  # Runs on deployment to setup folders and install binaries
  home.activation.installDataloggerBinaries = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "--- Installing Datalogger Binaries ---"
    
    # [FIX] Ensure the custom temp directory exists
    mkdir -p "${tmpDir}"
    mkdir -p "${binDir}"

    # Get the system's dynamic loader (required for patching)
    INTERPRETER="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"

    install_bin() {
      NAME=$1
      SRC=$2
      DEST="${binDir}/$NAME"

      # Only copy if file is missing or changed
      if [ ! -f "$DEST" ] || [ "$(sha256sum $DEST | cut -d' ' -f1)" != "$(sha256sum $SRC | cut -d' ' -f1)" ]; then
        echo "Updating $NAME..."
        cp "$SRC" "$DEST"
        chmod +x "$DEST"
        
        # Patch the binary to use this system's loader
        ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$DEST"
      fi
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: "install_bin ${name} ${src}") binaries)}
  '';

  # 2. SERVICE DEFINITIONS
  systemd.user.services = lib.mapAttrs mkService binaries;
}