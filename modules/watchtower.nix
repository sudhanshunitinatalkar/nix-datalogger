{ config, pkgs, lib, ... }:

{
  systemd.user.services.watchtower = {
    Unit = {
      Description = "Watchtower: Check Git for configuration updates";
      After = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "watchtower-update" ''
        set -e
        export PATH=${lib.makeBinPath [ pkgs.git pkgs.nix ]}:$PATH
        
        cd $HOME/nix-dataloggers
        
        git fetch origin main
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})
        
        if [ "$LOCAL" != "$REMOTE" ]; then
           echo "Watchtower: Update detected! Pulling and switching..."
           git pull
           nix run home-manager -- switch --flake .#datalogger
        fi
      '';
    };
  };

  systemd.user.timers.watchtower = {
    Unit = { Description = "Run Watchtower every 10 seconds"; };
    Timer = {
      OnBootSec = "1m";
      OnUnitActiveSec = "10s";
    };
    Install = { WantedBy = [ "timers.target" ]; };
  };
}