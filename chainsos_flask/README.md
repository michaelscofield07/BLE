# ChainSOS Flask Server

## Setup

1. Create and activate a virtual environment (recommended):
```
python -m venv .venv
. .venv/Scripts/activate
```

2. Install dependencies:
```
pip install -r requirements.txt
```

3. Run the server:
```
python app.py
```

The API will run at `http://127.0.0.1:5000`.

## Endpoints
- POST `/receive` — accepts JSON `{packet_id, device_id, timestamp, lat, lon, message}`
- GET `/dashboard` — HTML dashboard with a map of alerts

## Sample JSON
```
{
  "packet_id": "device-123-1690000000",
  "device_id": "device-123",
  "timestamp": 1690000000,
  "lat": 12.9716,
  "lon": 77.5946,
  "message": "SOS"
}
```

## Notes
- Data stored in `db.sqlite3` (created automatically).
- Twilio/SMTP integration is stubbed; print statements simulate alerts.


