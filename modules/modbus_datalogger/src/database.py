import sqlite3
import sys
import os
import shutil
import time
import json
from datetime import datetime
import modbus 

# --- Core Database Functions ---

def initDB(db_path):
    """
    Initializes the SQLite database.
    
    - Takes an absolute database file path.
    - Creates the 'readings' table if it doesn't exist.
    - Sets PRAGMA settings to optimize for SD card read/write cycles
      (WAL mode and NORMAL synchronous).
    """
    try:
        db_dir = os.path.dirname(os.path.abspath(db_path))
        if not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)
            print(f"Created database directory: {db_dir}")

        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            
            # --- SD Card Optimizations ---
            cursor.execute("PRAGMA journal_mode = WAL;")
            cursor.execute("PRAGMA synchronous = NORMAL;")
            
            # --- Table Creation ---
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS readings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    is_published INTEGER NOT NULL DEFAULT 0,
                    timestamp TEXT NOT NULL,
                    data TEXT NOT NULL
                )
            ''')
            
            # Index on timestamp is crucial for fast deletion of old data
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_timestamp 
                ON readings (timestamp);
            ''')
            
        print(f"Database '{db_path}' initialized successfully.")
        
    except sqlite3.Error as e:
        print(f"An error occurred during database initialization: {e}", file=sys.stderr)
    except OSError as e:
        print(f"An error occurred creating the database directory: {e}", file=sys.stderr)


def deleteOldestRows(db_path, num_rows_to_delete):
    """
    Deletes the specified number of the oldest rows from the 'readings' table.

    Args:
        db_path (str): Path to the SQLite database file.
        num_rows_to_delete (int): The number of rows to delete.

    Returns:
        int: The number of rows actually deleted, or 0 on error.
    """
    deleted_rows = 0
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            
            # This query finds the oldest 'N' rows by their timestamp
            # and deletes them. Using the index on 'timestamp' makes this fast.
            cursor.execute(f'''
                DELETE FROM readings
                WHERE id IN (
                    SELECT id FROM readings
                    ORDER BY timestamp ASC
                    LIMIT {num_rows_to_delete}
                )
            ''')
            deleted_rows = cursor.rowcount
            conn.commit()
            
    except sqlite3.Error as e:
        print(f"An error occurred during row deletion: {e}", file=sys.stderr)
        return 0
        
    return deleted_rows

def getfreeSpace():
    """
    Returns the free disk space in bytes for the root filesystem ('/').
    
    Returns:
        int: The free space in bytes, or None if an error occurs.
    """
    try:
        total, used, free = shutil.disk_usage('/')
        return free
        
    except FileNotFoundError:
        print(f"Error: Root path '/' not found.", file=sys.stderr)
        return None
    except Exception as e:
        print(f"An error occurred checking disk space: {e}", file=sys.stderr)
        return None

def printAllReadings(db_path):
    """Helper function to print all rows from the database."""
    print(f"--- Current Data in {db_path} ---")
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            # --- FIX: Added 'is_published' to the query ---
            cursor.execute("SELECT id, is_published, timestamp, data FROM readings ORDER BY timestamp ASC")
            rows = cursor.fetchall()
            
            if not rows:
                print("Database is empty.")
                return

            for row in rows:
                # Truncate long data for cleaner printing
                # --- FIX: Adjusted indices for the new column ---
                data_preview = row[3][:75] + '...' if len(row[3]) > 75 else row[3]
                print(f"  ID: {row[0]}, Published: {row[1]}, Time: {row[2]}, Data: {data_preview}")
        print(f"--- Total Rows: {len(rows)} ---")

    except sqlite3.Error as e:
        print(f"Error reading data: {e}", file=sys.stderr)

def insertReading(db_path, timestamp, data):
    """
    Inserts a single sensor reading into the database.
    
    Args:
        db_path (str): Path to the SQLite database file.
        timestamp (str): ISO 8601 formatted timestamp string.
        json_data (str): The complete JSON data string to store.
    """
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "INSERT INTO readings (timestamp, data) VALUES (?, ?)",
                (timestamp, data)
            )
        # print(f"Inserted reading for {timestamp}") # Uncomment for debugging
    except sqlite3.Error as e:
        print(f"Error inserting data: {e}", file=sys.stderr)

# --- Example Usage ---
if __name__ == "__main__":
    
    # Use 'testid.json' as the config file, assuming it's in the same directory
    db_file = "test.db"
    config_file = "testid-modbus.json"
    num_rows_to_delete = 5

    # --- NEW: Delete old database file if it exists ---
    if os.path.exists(db_file):
        try:
            os.remove(db_file)
            print(f"Removed old database: {db_file}")
        except OSError as e:
            print(f"Error removing old database {db_file}: {e}", file=sys.stderr)
            sys.exit(1) # Exit if we can't remove it
    
    print(f"Initializing database: {db_file}")
    initDB(db_file)
    
    print(f"\nInserting 10 rows (1 per second) using config: {config_file}")
    for i in range(10):
        ts = datetime.now().isoformat()
        
        # Read from modbus simulator
        sensor_data = modbus.readsens_all(config_file)
        
        if sensor_data:
            json_data = json.dumps(sensor_data)
            insertReading(db_file, ts, json_data)
            print(f"Inserted row {i+1}/10")
        else:
            print(f"Error: Could not read sensor data from {config_file}. Skipping row {i+1}.")
            
        time.sleep(1) # Wait 1 second
    
    # Print the database contents
    printAllReadings(db_file)
    
    # Delete the oldest 5 rows
    print("\nDeleting oldest 5 rows...")
    deleted_count = deleteOldestRows(db_file, num_rows_to_delete)
    print(f"Successfully deleted {deleted_count} rows.")
    printAllReadings(db_file)
    
    print("\nTest complete.")
    print(f"You can delete the '{db_file}' file now.")

    
    print("\nTest complete.")
    print(f"You can delete the '{db_file}' file now.")