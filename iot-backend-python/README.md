# Smart Inverter — Python/FastAPI Backend

Lean IoT backend for the Smart Inverter Flutter app.  
Replaces the previous Node.js/Express backend.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Health check |
| `GET` | `/power` | Latest inverter reading from InfluxDB |
| `GET` | `/history?field=&range=` | Aggregated time-series data |
| `GET` | `/docs` | Auto-generated Swagger UI |

### `field` options
`pv_input_w` · `load_w` · `battery_percent` · `temperature` · `battery_voltage`

### `range` options
`1h` · `6h` · `24h`

---

## Setup

```bash
# 1. Create and activate a virtual environment (optional but recommended)
python -m venv venv
venv\Scripts\activate   # Windows

# 2. Install dependencies
pip install -r requirements.txt

# 3. Configure environment
cp .env.example .env
# Fill in your real INFLUX_* values in .env

# 4. Run
python -m uvicorn main:app --reload --port 8000
```

Open **http://localhost:8000/docs** to explore the API.

---

## Project Structure

```
iot-backend-python/
├── main.py          # FastAPI app — routes + keep-alive loop
├── influx.py        # InfluxDB query helpers
├── settings.py      # Pydantic env settings
├── requirements.txt
├── .env.example
└── README.md
```
