#!/usr/bin/env bash

# ==============================================================================
# INDUSTRIAL DATALOGGER BOOTSTRAP SCRIPT
# Location: ~/dataloggerOS/datalogger_run.sh
# Function: 
#   1. Auto-updates git repository.
#   2. Launches a single Nix environment.
#   3. Spawns 7 parallel Python processes with self-healing (auto-restart) logic.
# ==============================================================================

# --- CONFIGURATION ---
REPO_DIR="$HOME/datalogger"
REPO_URL="https://github.com/sudhanshunitinatalkar/datalogger.git"
LOG_DIR="$HOME/datalogger_logs"
BOOT_LOG="$LOG_DIR/boot_system.log"

# --- PRE-FLIGHT CHECKS ---
mkdir -p "$LOG_DIR"

# Helper function to log strictly to file (No Terminal Output)
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [SYSTEM] $1" >> "$BOOT_LOG"
}

log_msg "=== BOOT SEQUENCE INITIATED ==="

# --- STEP 1: GIT AUTO-UPDATE ---
if [ ! -d "$REPO_DIR" ]; then
    log_msg "Repository missing. Cloning from source..."
    if git clone "$REPO_URL" "$REPO_DIR" >> "$BOOT_LOG" 2>&1; then
        log_msg "Clone successful."
    else
        log_msg "CRITICAL FAILURE: Could not clone repository. Check internet/URL."
        # In industrial context, we might retry or exit. 
        # Here we exit to let systemd attempt a restart loop if configured.
        exit 1
    fi
else
    log_msg "Repository found. Checking for updates..."
    # Attempt pull, but don't fail boot if internet is down
    (
        cd "$REPO_DIR" || exit
        if git pull >> "$BOOT_LOG" 2>&1; then
            log_msg "Update successful (Git Pull)."
        else
            log_msg "WARNING: Git pull failed (Network down?). Proceeding with existing code."
        fi
    )
fi

# --- STEP 2: DEFINE SUPERVISOR LOGIC ---
# This script block runs INSIDE the Nix environment.
# It creates a monitoring loop for every python script.
SUPERVISOR_SCRIPT=$(cat << 'EOF'
    # List of modules to run simultaneously
    SCRIPTS=("configure" "cpcb" "data" "datalogger" "display" "network" "saicloud")
    LOG_DIR="$HOME/datalogger_logs"
    REPO_ROOT="$HOME/datalogger"

    echo "Starting Process Supervisor inside Nix Environment..."

    # Function: Watchdog for a single service
    start_watchdog() {
        local name=$1
        local script_path="$REPO_ROOT/src/${name}.py"
        local service_log="$LOG_DIR/${name}_runtime.log"

        # Infinite Loop for Self-Healing
        while true; do
            # Log start attempt
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Service: $name" >> "$service_log"
            
            # Run Python Script
            # We redirect stdout/stderr here to catch crashes that happen *before* # the Python script initializes its own logging.
            python "$script_path" >> "$service_log" 2>&1
            
            # If we reach here, the script has crashed/exited
            EXIT_CODE=$?
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] CRASH: $name exited with code $EXIT_CODE" >> "$service_log"
            
            # Exponential backoff or simple delay to prevent CPU thrashing on boot loops
            echo "Restarting in 3 seconds..." >> "$service_log"
            sleep 3
        done
    }

    # Launch all watchdogs in the background
    for script_name in "${SCRIPTS[@]}"; do
        start_watchdog "$script_name" &
    done

    # IMPORTANT: Wait strictly keeps the parent shell alive.
    # If we don't wait, the Nix session closes and kills all child processes.
    wait
EOF
)

# --- STEP 3: EXECUTE NIX ENVIRONMENT ---
log_msg "Launching Nix Develop Environment..."

# We switch to the repo dir so Nix finds the flake.nix
cd "$REPO_DIR" || { log_msg "CRITICAL: Cannot enter repo dir"; exit 1; }

# Run nix develop. 
# --command bash -c "..." executes our supervisor logic inside the flake environment.
# We redirect all Nix output to the boot log to keep the terminal silent.
nix develop . --command bash -c "$SUPERVISOR_SCRIPT" >> "$BOOT_LOG" 2>&1

log_msg "CRITICAL: Nix environment exited unexpectedly. Service Stopping."