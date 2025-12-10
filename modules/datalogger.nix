{ config, pkgs, lib, ... }:

let
  # --- Configuration ---
  
  # 1. Target Directory for Binaries
  targetDir = "${config.home.homeDirectory}/datalogger-bin";

  # 2. Release URL
  # Updated to match the new repo structure and filename
  repoOwner = "sudhanshunitinatalkar";
  repoName = "datalog-bin"; 
  releaseTag = "v0.0.1";
  zipName = "release.zip";
  
  releaseUrl = "https://github.com/${repoOwner}/${repoName}/releases/download/${releaseTag}/${zipName}";

  # 3. Service Names (Binaries to run)
  # Added 'diag' which was visible in the folder structure image
  serviceNames = [ 
    "configure" 
    "cpcb" 
    "data" 
    "datalogger" 
    "display" 
    "network" 
    "saicloud" 
  ];

  # --- Service Generator ---
  mkDataloggerService = name: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      After = [ "network-online.target" "datalogger-updater.service" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      # Path to the binary
      ExecStart = "${targetDir}/bin/${name}";

      # Restart Policy
      Restart = "always";
      RestartSec = "5s";
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";

      # [CRITICAL] TMPDIR Handling for Standalone Binaries
      # 1. Tell PyInstaller to unpack in a persistent directory in $HOME (%h)
      # This ensures files are extracted to the user's home, not /tmp
      Environment = "TMPDIR=%h/datalogger-tmp";

      # 2. Ensure this directory exists before the binary launches
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/datalogger-tmp";

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

in
{
  # --- 1. Updater Service ---
  # Downloads the zip, extracts it, and restarts services if successful.
  systemd.user.services.datalogger-updater = {
    Unit = {
      Description = "Fetch datalogger binaries from GitHub Releases";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      
      ExecStart = pkgs.writeShellScript "update-datalogger" ''
        # Add tools to PATH
        export PATH=${lib.makeBinPath [ pkgs.curl pkgs.unzip pkgs.systemd pkgs.coreutils ]}:$PATH
        
        TARGET_BASE="${targetDir}"
        TARGET_BIN="$TARGET_BASE/bin"
        
        # [MODIFIED] Use a temp directory inside HOME instead of system default /tmp
        # This creates a folder like /home/datalog/datalogger-update-tmp
        mkdir -p "$HOME/datalogger-update-tmp"
        TEMP_DIR=$(mktemp -d -p "$HOME/datalogger-update-tmp")
        
        ZIP_FILE="$TEMP_DIR/${zipName}"
        
        echo "--- Starting Update Process ---"
        echo "Release URL: ${releaseUrl}"
        echo "Using Temp Directory: $TEMP_DIR"
        
        # 1. Download the Zip
        # -L: Follow redirects, -f: Fail on HTTP error
        if curl -L -f -o "$ZIP_FILE" "${releaseUrl}"; then
          echo "Download successful."

          # 2. Verify it is a valid zip
          if ! unzip -t "$ZIP_FILE" > /dev/null; then
            echo "Error: File is not a valid zip archive."
            rm -rf "$TEMP_DIR"
            exit 1
          fi

          # 3. Prepare Target Directory
          mkdir -p "$TARGET_BIN"

          # 4. Extract to Temp
          echo "Extracting..."
          unzip -o "$ZIP_FILE" -d "$TEMP_DIR/extracted"

          # 5. Install Binaries
          SERVICES="${lib.concatStringsSep " " serviceNames}"
          
          for svc in $SERVICES; do
            # Find the file anywhere in the extracted zip structure
            # This handles the "release/datalogger-0.0.1" subfolder structure automatically
            FOUND_FILE=$(find "$TEMP_DIR/extracted" -name "$svc" -type f | head -n 1)
            
            if [ -n "$FOUND_FILE" ]; then
              echo "Installing: $svc"
              cp -f "$FOUND_FILE" "$TARGET_BIN/$svc"
              chmod +x "$TARGET_BIN/$svc"
            else
              echo "Warning: Binary '$svc' not found in zip package."
            fi
          done
          
          # 6. Cleanup
          rm -rf "$TEMP_DIR"

          # 7. Restart Services to apply new binaries
          echo "Restarting application services..."
          # Using $SERVICES variable which expands to all service names
          systemctl --user restart $SERVICES
          echo "Update Complete."

        else
          echo "Failed to download update. Server returned error or no internet."
          rm -rf "$TEMP_DIR"
          exit 1
        fi
      '';
    };
  } 
  # Merge with the generated service definitions
  // (lib.genAttrs serviceNames mkDataloggerService);

  # --- 2. Timer (Auto-Update) ---
  systemd.user.timers.datalogger-updater = {
    Unit = {
      Description = "Check for datalogger updates every 5 minutes";
    };
    Timer = {
      OnBootSec = "1m";
      OnUnitActiveSec = "5m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}