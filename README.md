# ChainSOS (Flutter + Flask)

Emergency SOS system that works online (HTTP) and offline via BLE mesh simulation.

## Repo Structure
- `chain_sos_flutter/` – Flutter mobile app
- `chainsos_flask/` – Flask backend (API + Dashboard)

## Run Backend
```
cd chainsos_flask
python -m venv .venv
. .venv/Scripts/activate
pip install -r requirements.txt
python app.py
```

Server: `http://127.0.0.1:5000` → endpoints: `/`, `/receive`, `/dashboard`

## Run Flutter App
```
cd chain_sos_flutter
flutter pub get
flutter run
```

## Packet Format
```
{
  "packet_id": "<device_id>-<timestamp_rounded_30s>",
  "device_id": "string",
  "timestamp": 1690000000,
  "lat": 12.9716,
  "lon": 77.5946,
  "message": "SOS"
}
```

## Notes
- BLE is simulated for development. Real BLE can be integrated later with `flutter_blue_plus` APIs.
- SQLite DB `db.sqlite3` is created automatically by Flask on first run.
