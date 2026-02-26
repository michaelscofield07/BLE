from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import sqlite3
import os
from datetime import datetime
import time

app = Flask(__name__)
CORS(app)

DB_PATH = os.path.join(os.path.dirname(__file__), 'db.sqlite3')

def init_db():
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS devices (
            device_id TEXT PRIMARY KEY,
            name TEXT,
            contacts TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS sos (
            packet_id TEXT PRIMARY KEY,
            device_id TEXT,
            timestamp INTEGER,
            lat REAL,
            lon REAL,
            message TEXT,
            received_at TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS tracking_packets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            packet_id TEXT,
            device_id TEXT,
            sos_id TEXT,
            timestamp INTEGER,
            type TEXT,
            lat REAL,
            lon REAL,
            confidence TEXT,
            received_at TEXT,
            UNIQUE(packet_id)
        )
        """
    )
    con.commit()
    con.close()


init_db()

@app.route('/favicon.ico')
def favicon():
    return '', 204  


@app.route('/tracking', methods=['POST'])
def receive_tracking():
    data = request.get_json(force=True, silent=True) or {}
    required = ['packet_id', 'device_id', 'sos_id', 'timestamp', 'type']
    if not all(k in data for k in required):
        return jsonify({'ok': False, 'error': 'missing fields'}), 400

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    try:
        # Check if packet already exists
        cur.execute('SELECT 1 FROM tracking_packets WHERE packet_id=?', (data['packet_id'],))
        if cur.fetchone():
            con.close()
            return jsonify({'ok': True, 'status': 'duplicate'}), 200

        # Insert tracking packet
        cur.execute(
            'INSERT INTO tracking_packets (packet_id, device_id, sos_id, timestamp, type, lat, lon, confidence, received_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            (
                data['packet_id'],
                data['device_id'],
                data['sos_id'],
                int(data['timestamp']),
                data['type'],
                data.get('lat'),
                data.get('lon'),
                data.get('confidence', 'HIGH'),
                datetime.utcnow().isoformat(),
            ),
        )
        con.commit()
        print(f"TRACKING: {data['device_id']} SOS {data['sos_id']} type {data['type']}")
    except Exception as e:
        print(f"Error saving tracking packet: {e}")
        con.rollback()
    finally:
        con.close()

    return jsonify({'ok': True}), 200


@app.route('/sos', methods=['POST'])
@app.route('/receive', methods=['POST'])
def receive():
    data = request.get_json(force=True, silent=True) or {}
    required = ['packet_id', 'device_id', 'timestamp', 'lat', 'lon', 'message']
    if not all(k in data for k in required):
        return jsonify({'ok': False, 'error': 'missing fields'}), 400

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    try:
        cur.execute('SELECT 1 FROM sos WHERE packet_id=?', (data['packet_id'],))
        if cur.fetchone():
            con.close()
            return jsonify({'ok': True, 'status': 'duplicate'}), 200

        try:
            ts = int(data['timestamp'])
        except Exception:
            ts = None
        if ts is not None:
            cur.execute(
                'SELECT 1 FROM sos WHERE device_id=? AND ABS(timestamp - ?) <= ? LIMIT 1',
                (data['device_id'], ts, 60),
            )
            if cur.fetchone():
                con.close()
                return jsonify({'ok': True, 'status': 'duplicate_near'}), 200

        cur.execute('SELECT 1 FROM devices WHERE device_id=?', (data['device_id'],))
        if not cur.fetchone():
            cur.execute('INSERT INTO devices (device_id, name, contacts) VALUES (?, ?, ?)', (data['device_id'], None, None))

        cur.execute(
            'INSERT INTO sos (packet_id, device_id, timestamp, lat, lon, message, received_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (
                data['packet_id'],
                data['device_id'],
                int(data['timestamp']),
                float(data['lat']),
                float(data['lon']),
                data['message'],
                datetime.utcnow().isoformat(),
            ),
        )
        con.commit()
    finally:
        con.close()
    print(f"ALERT: {data['device_id']} at ({data['lat']}, {data['lon']}) message={data['message']}")

    return jsonify({'ok': True}), 200


def format_timestamp(ts):
    try:
        dt = datetime.fromtimestamp(int(ts))
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    except:
        return str(ts)  

@app.route('/dashboard')
def dashboard():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute('SELECT * FROM sos ORDER BY timestamp DESC LIMIT 200')
    rows = [dict(row) for row in cur.fetchall()]
    con.close()
    for row in rows:
        row['formatted_time'] = format_timestamp(row['timestamp'])
    
    return render_template('dashboard.html', alerts=rows)


@app.route('/tracking/<sos_id>')
def get_tracking(sos_id):
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute(
        'SELECT * FROM tracking_packets WHERE sos_id = ? ORDER BY timestamp ASC',
        (sos_id,)
    )
    rows = [dict(row) for row in cur.fetchall()]
    con.close()
    
    return jsonify({'tracking_data': rows})


@app.route('/clear-database', methods=['POST'])
def clear_database():
    data = request.get_json(force=True, silent=True) or {}
    clear_type = data.get('type', 'all')  # 'all', 'sos', 'tracking'
    
    try:
        con = sqlite3.connect(DB_PATH)
        cur = con.cursor()
        
        # Get counts before deletion
        cur.execute('SELECT COUNT(*) FROM sos')
        sos_count = cur.fetchone()[0]
        
        cur.execute('SELECT COUNT(*) FROM tracking_packets')
        tracking_count = cur.fetchone()[0]
        
        deleted_sos = 0
        deleted_tracking = 0
        
        if clear_type in ['all', 'sos']:
            cur.execute('DELETE FROM sos')
            deleted_sos = sos_count
            
        if clear_type in ['all', 'tracking']:
            cur.execute('DELETE FROM tracking_packets')
            deleted_tracking = tracking_count
            
        con.commit()
        con.close()
        
        return jsonify({
            'ok': True,
            'message': f'Cleared {deleted_sos} SOS packets and {deleted_tracking} tracking packets',
            'deleted_sos': deleted_sos,
            'deleted_tracking': deleted_tracking
        })
        
    except Exception as e:
        return jsonify({
            'ok': False,
            'error': str(e)
        }), 500

@app.route('/database-status')
def database_status():
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
        
        # Get latest entries
        cur.execute('''
            SELECT packet_id, device_id, timestamp, message 
            FROM sos 
            ORDER BY timestamp DESC 
            LIMIT 10
        ''')
        latest_sos = []
        for row in cur.fetchall():
            latest_sos.append({
                'packet_id': row[0],
                'device_id': row[1],
                'timestamp': row[2],
                'formatted_time': format_timestamp(row[2]),
                'message': row[3]
            })
        
        con.close()
        
        return jsonify({
            'ok': True,
            'sos_count': sos_count,
            'tracking_count': tracking_count,
            'device_count': device_count,
            'latest_sos': latest_sos
        })
        
    except Exception as e:
        return jsonify({
            'ok': False,
            'error': str(e)
        }), 500

@app.route('/')
def root():
    return jsonify({'ok': True, 'service': 'ChainSOS'}), 200


if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)


