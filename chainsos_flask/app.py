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
    con.commit()
    con.close()

# Initialize database on startup
init_db()

@app.route('/favicon.ico')
def favicon():
    return '', 204  # No content response for favicon


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
    con.commit()
    con.close()


@app.route('/sos', methods=['POST'])
@app.route('/receive', methods=['POST'])  # Keep old endpoint for compatibility
def receive():
    data = request.get_json(force=True, silent=True) or {}
    required = ['packet_id', 'device_id', 'timestamp', 'lat', 'lon', 'message']
    if not all(k in data for k in required):
        return jsonify({'ok': False, 'error': 'missing fields'}), 400

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    try:
        # dedupe
        cur.execute('SELECT 1 FROM sos WHERE packet_id=?', (data['packet_id'],))
        if cur.fetchone():
            con.close()
            return jsonify({'ok': True, 'status': 'duplicate'}), 200

        # Optional: ensure device exists; if not, insert a placeholder
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

    # TODO: Integrate SMS/Email (Twilio/SMTP). For now, simulate.
    print(f"ALERT: {data['device_id']} at ({data['lat']}, {data['lon']}) message={data['message']}")

    return jsonify({'ok': True}), 200


def format_timestamp(ts):
    try:
        # Convert Unix timestamp to datetime
        dt = datetime.fromtimestamp(int(ts))
        # Format as 24-hour time
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    except:
        return str(ts)  # Fallback if conversion fails

@app.route('/dashboard')
def dashboard():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute('SELECT * FROM sos ORDER BY timestamp DESC LIMIT 200')
    rows = [dict(row) for row in cur.fetchall()]
    con.close()
    
    # Format timestamps for each row
    for row in rows:
        row['formatted_time'] = format_timestamp(row['timestamp'])
    
    return render_template('dashboard.html', alerts=rows)


@app.route('/')
def root():
    return jsonify({'ok': True, 'service': 'ChainSOS'}), 200


if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)


