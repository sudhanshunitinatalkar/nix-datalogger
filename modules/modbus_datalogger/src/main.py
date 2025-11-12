import database
import modbus
import cpuid
import json
import sys
import time
from datetime import datetime

CONFIG_FILE = "testid.json"

def load_config(config_path):
    """
    Loads the main JSON configuration file.
    """
    print(f"Loading configuration from {config_path}...")
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        print("Configuration loaded successfully.")
        return config
    except FileNotFoundError:
        print(f"FATAL ERROR: Configuration file '{config_path}' not found.", file=sys.stderr)
        return None
    except json.JSONDecodeError:
        print(f"FATAL ERROR: Could not decode JSON from '{config_path}'. Check format.", file=sys.stderr)
        return None
    except Exception as e:
        print(f"FATAL ERROR: An unexpected error occurred loading config: {e}", file=sys.stderr)
        return None

def main_loop():
    """
    Main datalogger application loop.
    """
    # 1. Load the main configuration file
    config = load_config(CONFIG_FILE)
    if config is None:
        sys.exit(1) # Exit if config fails to load

    # 2. Get the actual CPU ID and update the config in memory
    print("Fetching CPU ID...")
    actual_cpuid = cpuid.get_cpuid()
    if actual_cpuid:
        print(f"CPU ID found: {actual_cpuid}")
        config["device_info"]["device_id"] = actual_cpuid
    else:
        print("Warning: Could not get CPU ID. Using placeholder.")
        # We can keep the "REPLACE_WITH_CPUID" or set a default
        if config["device_info"]["device_id"] == "REPLACE_WITH_CPUID":
             config["device_info"]["device_id"] = "UNKNOWN_PI"

    # 3. Get settings from the config
    # We can pass these specific dictionaries to other functions
    db_path = config["database"]["db_path"]
    poll_interval = config["datalogger_settings"]["polling_interval_seconds"]
    
    # 4. Initialize the database
    print(f"Initializing database at {db_path}...")
    database.initDB(db_path)
    
    print(f"--- Starting Datalogger ---")
    print(f"Device ID: {config['device_info']['device_id']}")
    print(f"Polling Interval: {poll_interval} seconds")
    print("Press Ctrl+C to stop.")

    # 5. Start the main polling loop
    try:
        while True:
            # Get current time
            ts = datetime.now().isoformat()
            
            # Read sensor data
            # We pass the *filename* to readsens_all, which is now smart
            # enough to find the "sensor_config" section.
            sensor_data = modbus.readsens_all(CONFIG_FILE)
            
            if sensor_data:
                # We can add the device_info to the data before saving
                full_data_to_save = {
                    "device_info": config["device_info"],
                    "sensor_readings": sensor_data
                }
                
                # Convert to JSON string for storage
                json_data = json.dumps(full_data_to_save)
                
                # Insert into the database
                database.insertReading(db_path, ts, json_data)
                print(f"[{ts}] Successfully logged data.")
            else:
                print(f"[{ts}] Error: Could not read sensor data. Skipping this poll.")
            
            # Wait for the next poll
            time.sleep(poll_interval)
            
    except KeyboardInterrupt:
        print("\n--- Datalogger stopping. ---")
    except Exception as e:
        print(f"\n--- FATAL ERROR in main loop: {e} ---", file=sys.stderr)
    finally:
        print("--- Datalogger shut down. ---")


if __name__ == "__main__":
    main_loop()