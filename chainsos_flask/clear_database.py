import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), 'db.sqlite3')

def clear_sos_logs():
    """Clear all SOS logs from the database"""
    try:
        con = sqlite3.connect(DB_PATH)
        cur = con.cursor()
        
        # Get count before deletion
        cur.execute('SELECT COUNT(*) FROM sos')
        sos_count = cur.fetchone()[0]
        
        cur.execute('SELECT COUNT(*) FROM tracking_packets')
        tracking_count = cur.fetchone()[0]
        
        print(f"Current database state:")
        print(f"  SOS packets: {sos_count}")
        print(f"  Tracking packets: {tracking_count}")
        
        # Clear SOS table
        cur.execute('DELETE FROM sos')
        
        # Clear tracking packets table
        cur.execute('DELETE FROM tracking_packets')
        
        con.commit()
        
        print(f"\n✅ Database cleared successfully!")
        print(f"  Deleted {sos_count} SOS packets")
        print(f"  Deleted {tracking_count} tracking packets")
        
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}")
    finally:
        if con:
            con.close()

def clear_sos_only():
    """Clear only SOS logs, keep tracking packets"""
    try:
        con = sqlite3.connect(DB_PATH)
        cur = con.cursor()
        
        # Get count before deletion
        cur.execute('SELECT COUNT(*) FROM sos')
        sos_count = cur.fetchone()[0]
        
        print(f"Current SOS packets: {sos_count}")
        
        # Clear only SOS table
        cur.execute('DELETE FROM sos')
        
        con.commit()
        
        print(f"✅ SOS logs cleared successfully!")
        print(f"  Deleted {sos_count} SOS packets")
        
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}")
    finally:
        if con:
            con.close()

def clear_tracking_only():
    """Clear only tracking packets, keep SOS logs"""
    try:
        con = sqlite3.connect(DB_PATH)
        cur = con.cursor()
        
        # Get count before deletion
        cur.execute('SELECT COUNT(*) FROM tracking_packets')
        tracking_count = cur.fetchone()[0]
        
        print(f"Current tracking packets: {tracking_count}")
        
        # Clear only tracking packets table
        cur.execute('DELETE FROM tracking_packets')
        
        con.commit()
        
        print(f"✅ Tracking packets cleared successfully!")
        print(f"  Deleted {tracking_count} tracking packets")
        
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}")
    finally:
        if con:
            con.close()

def show_database_status():
    """Show current database status"""
    try:
        con = sqlite3.connect(DB_PATH)
        cur = con.cursor()
        
        # Get counts
        cur.execute('SELECT COUNT(*) FROM sos')
        sos_count = cur.fetchone()[0]
        
        cur.execute('SELECT COUNT(*) FROM tracking_packets')
        tracking_count = cur.fetchone()[0]
        
        cur.execute('SELECT COUNT(*) FROM devices')
        device_count = cur.fetchone()[0]
        
        print(f"📊 Database Status:")
        print(f"  SOS packets: {sos_count}")
        print(f"  Tracking packets: {tracking_count}")
        print(f"  Devices: {device_count}")
        
        # Show latest entries
        cur.execute('SELECT packet_id, device_id, timestamp FROM sos ORDER BY timestamp DESC LIMIT 5')
        latest_sos = cur.fetchall()
        
        if latest_sos:
            print(f"\n📋 Latest SOS packets:")
            for row in latest_sos:
                timestamp = datetime.fromtimestamp(row[2]).strftime('%Y-%m-%d %H:%M:%S')
                print(f"  {row[0]} - {row[1]} - {timestamp}")
        
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}")
    finally:
        if con:
            con.close()

if __name__ == "__main__":
    print("🗑️  ChainSOS Database Cleanup Tool")
    print("=" * 40)
    
    while True:
        print("\nOptions:")
        print("1. Show database status")
        print("2. Clear SOS logs only")
        print("3. Clear tracking packets only")
        print("4. Clear ALL data (SOS + tracking)")
        print("5. Exit")
        
        choice = input("\nEnter your choice (1-5): ").strip()
        
        if choice == '1':
            show_database_status()
        elif choice == '2':
            clear_sos_only()
        elif choice == '3':
            clear_tracking_only()
        elif choice == '4':
            confirm = input("⚠️  This will delete ALL SOS and tracking data. Are you sure? (yes/no): ").strip().lower()
            if confirm == 'yes':
                clear_sos_logs()
            else:
                print("❌ Operation cancelled.")
        elif choice == '5':
            print("👋 Goodbye!")
            break
        else:
            print("❌ Invalid choice. Please try again.")
