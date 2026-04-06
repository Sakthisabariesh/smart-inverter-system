<div align="center">

# ⚡ Smart Inverter System

### AI-Powered Solar Energy Monitoring, Prediction & Net-Zero Analysis

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/Python-FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![XGBoost](https://img.shields.io/badge/ML-XGBoost-FF6600?style=for-the-badge&logo=python&logoColor=white)](https://xgboost.readthedocs.io)
[![InfluxDB](https://img.shields.io/badge/InfluxDB-Cloud-22ADF6?style=for-the-badge&logo=influxdb&logoColor=white)](https://www.influxdata.com)
[![Docker](https://img.shields.io/badge/Docker-Node--RED-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com)
[![Render](https://img.shields.io/badge/Deployed_on-Render-46E3B7?style=for-the-badge&logo=render&logoColor=white)](https://render.com)

<br/>

> **Green CODE Net-Zero Sprint | Building App Challenge**
> IEEE Student Branch – STB61541 | Sona College of Technology

<br/>

![License](https://img.shields.io/badge/license-ISC-green?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Web%20%7C%20Linux-blue?style=flat-square)
![Version](https://img.shields.io/badge/version-3.0.0-orange?style=flat-square)
![Backend](https://img.shields.io/badge/backend-Python%20FastAPI-brightgreen?style=flat-square)

</div>

---

## 📌 Overview

**Smart Inverter System** is a cross-platform IoT application providing **real-time visibility and AI-powered intelligent analysis** of a solar-powered energy setup. It bridges raw hardware sensor data with actionable, user-friendly energy insights — with **zero hallucination** in predictions.

- ⚡ **Solar energy generation** (Watts) — real-time + 24h AI forecast
- 🔋 **Battery voltage & status** with animated gauge
- 💡 **Load power consumption** — monitored & predicted
- 🌡️ **Ambient temperature** tracking
- 🌿 **Net-Zero status, CO₂ savings, and ROI analytics**
- 🤖 **XGBoost ML predictions** — trained on your real 15-day inverter data

---

## 🏗️ System Architecture

```
[Solar Panels / Battery / Load]
            ↓  (sensor readings)
    [Smart Inverter + IoT Sensors]
            ↓  (MQTT / HTTP)
      [Node-RED — Docker Container]
            ↓  (HTTPS Write API)
    [InfluxDB Cloud — Time-Series DB]  ←── 30-day retention
            ↓  (Flux Query, 8s timeout)
  [Python FastAPI — Render Cloud]
     ├── Background XGBoost Training (every 30 min)
     ├── In-Memory Prediction Cache (<200ms response)
     ├── Physics-Based Solar Model (panel specs)
     └── Weather API Integration
            ↓  (HTTPS / JSON)
   [Flutter App — Android | Web | Windows | Linux]
            ↓
       [End User Dashboard]
```

> 📊 **Full architecture diagram:** [`smart_inverter_architecture.drawio`](./smart_inverter_architecture.drawio) — open with [draw.io](https://app.diagrams.net)

---

## ✨ Key Features

### 🏠 Home Dashboard
| Feature | Description |
|---|---|
| **Live Metrics Grid** | Solar Power (W), Load Power (W), Battery Voltage (V), Temperature (°C) with animated gradient cards |
| **Battery Gauge** | Circular arc gauge with dynamic color (🟢 Green → 🟡 Orange → 🔴 Red) |
| **Solar/Load Donut Chart** | Visual ratio of energy generation vs. consumption |
| **Power Balance Card** | Real-time surplus/deficit indicator with animated energy bar |
| **Historical Trend Chart** | Line chart with 4 overlays (Solar, Load, Battery, Temp) across 1h / 6h / 24h |
| **Auto-refresh** | Live data refreshes every 15 seconds |

### 🤖 AI Forecasts Tab
| Feature | Description |
|---|---|
| **24h Solar Forecast** | XGBoost model trained on 15 days of real inverter data |
| **24h Load Prediction** | Evening-peak-aware prediction with holiday detection |
| **Weather Integration** | Cloud cover attenuation applied to solar forecast |
| **Data Source Badge** | Shows exactly how each prediction was made — no hallucination |
| **10-Day History Chart** | Full 10-day bar chart; missing days shown as dimmed slivers |
| **Anti-Hallucination** | Refuses to guess if no data — shows clear warning instead |

### 🌿 Net-Zero Analysis Screen
| Tab | Feature |
|---|---|
| **Dashboard** | Monthly Savings Bar Chart, CO₂ Reduction Tracker (🌳 tree equivalence), ROI Breakdown |
| **Settings** | ☀️ **Panel Setup** (Wp, count, efficiency, tilt, latitude), Electricity Rate, CO₂ Factor, System Cost, Baseline Load |

---

## 🤖 AI Prediction System

The AI backend uses a **3-tier anti-hallucination architecture**:

| Priority | Source | UI Badge |
|---|---|---|
| 1st | XGBoost trained on 15 days of real inverter readings | 🟢 `Live Data` |
| 2nd | Physics-based curve from your entered panel specs | 🟡 `Panel Specs` |
| 3rd | Derived from observed historical peak per hour | 🔵 `Historical Peak` |
| None | **Refuses to predict** — shows clear warning | 🔴 `No Data` |

**Solar Physics Model (when using panel specs):**
```
output_W = panel_Wp × panel_count × (efficiency%) × hour_factor × 0.80
```
where `hour_factor` is computed from real solar geometry (latitude + tilt angle).

**Performance:**
- Background model refresh: every **30 minutes**
- Prediction endpoint response: **< 200ms** (served from cache)
- InfluxDB query timeout: **8 seconds** (fail-fast)

---

## 🛠️ Tech Stack

| Layer | Technology | Details |
|---|---|---|
| **Frontend** | Flutter (Dart) | Android, Web, Windows, Linux |
| **UI Libraries** | `fl_chart`, `google_fonts`, `shared_preferences` | Charts, typography, local settings |
| **Backend API** | Python + FastAPI | REST API deployed on Render |
| **ML Engine** | XGBoost + scikit-learn | Solar & load 24h forecasting |
| **Database** | InfluxDB Cloud | Time-series, Flux query, 30-day retention |
| **IoT Pipeline** | Node-RED | MQTT/HTTP bridge, runs in Docker |
| **Hosting** | Render (API), InfluxDB Cloud (DB) | Free-tier cloud deployments |

---

## 📁 Project Structure

```
smart-inverter-system/
├── iot-backend-python/           # Python FastAPI backend
│   ├── main.py                   # FastAPI app, background training loop
│   ├── ml_predictor.py           # XGBoost models, physics solar model
│   ├── cache.py                  # Thread-safe in-memory prediction cache
│   ├── influx.py                 # InfluxDB client (8s timeout, 15d queries)
│   ├── settings.py               # Pydantic settings (env vars)
│   ├── requirements.txt          # Python dependencies
│   ├── .env.example              # Environment variable template
│   └── .gitignore                # Excludes .env from git
│
├── smart_inverter_app/           # Flutter frontend
│   ├── lib/
│   │   ├── main.dart             # App entry, dashboard, theme
│   │   ├── ai_insights_tab.dart  # AI forecasts, 10-day history chart
│   │   ├── net_zero_screen.dart  # Net-zero analytics + settings
│   │   └── user_settings.dart   # Panel specs + local settings
│   ├── android/                  # Android build config
│   ├── windows/                  # Windows build config
│   ├── web/                      # Web (PWA) build config
│   ├── linux/                    # Linux build config
│   └── pubspec.yaml              # Flutter dependencies
│
├── .github/
│   └── workflows/
│       └── flutter-build.yml     # CI/CD: APK + Windows builds
│
├── smart_inverter_architecture.drawio   # System architecture diagram
├── render.yaml                          # Render auto-deploy config
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Flutter SDK | ≥ 3.x | Frontend development |
| Python | ≥ 3.11 | Backend API |
| Docker | Latest | Running Node-RED |
| InfluxDB Cloud | — | Time-series database (free tier) |

---

### 1️⃣ Backend Setup (Python FastAPI)

```bash
cd iot-backend-python

# Install dependencies
pip install -r requirements.txt

# Copy environment template and fill in your values
cp .env.example .env
```

Edit `.env`:
```env
INFLUX_URL=https://your-influxdb-cloud-url
INFLUX_TOKEN=your_influxdb_token
INFLUX_ORG=your_org
INFLUX_BUCKET=your_bucket
WEATHER_API_KEY=your_openweathermap_key  # optional
PORT=8000
```

```bash
# Start the API server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

### 2️⃣ Node-RED (IoT Pipeline — Docker)

```bash
docker run -it -p 1880:1880 --name mynodered nodered/node-red
```

Import your Node-RED flow to:
1. Subscribe to MQTT topics from the inverter sensors
2. Transform the payload
3. POST data to InfluxDB Cloud via Write API

---

### 3️⃣ Flutter App Setup

```bash
cd smart_inverter_app

# Install Flutter packages
flutter pub get

# Run on connected device
flutter run

# Build for specific platform
flutter build apk --release --split-per-abi   # Android
flutter build web --release                    # Web
flutter build windows --release                # Windows
flutter build linux --release                  # Linux
```

> **API URL:** The app auto-selects the backend URL per platform:
> - **Web** → Uses deployed Render URL (`_kApiProduction` in `main.dart`)
> - **Mobile/Desktop** → Uses `127.0.0.1:8000` (local dev)

---

## 📊 API Endpoints

Base URL: `https://your-api.onrender.com`

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/` | Health check & version |
| `GET` | `/power` | Latest inverter readings |
| `GET` | `/history` | Time-series data (`field`, `range`, `daily`) |
| `GET` | `/predict/load` | 24h load forecast (XGBoost / fallback) |
| `GET` | `/predict/solar` | 24h solar forecast (XGBoost / physics / historical) |
| `GET` | `/predict/status` | Model cache status, MAE accuracy, data points |
| `GET` | `/weather` | Current weather + solar insight |

**Sample `/predict/status`:**
```json
{
  "is_ready": true,
  "last_refreshed": "4m ago",
  "training_data_points": 360,
  "load_model": { "trained": true, "mae_watts": 3.8 },
  "solar_model": { "trained": true, "mae_watts": 12.1 }
}
```

---

## 🔁 CI/CD Pipeline

```
Push to main
    └─▶ Render (auto-deploy Python API via render.yaml)
    └─▶ GitHub Actions (flutter-build.yml)
            ├─▶ Build Android APK  → Upload as artifact
            └─▶ Build Windows EXE  → Upload as artifact
```

---

## 🌍 SDG Alignment

| SDG | Goal | Our Contribution |
|---|---|---|
| **SDG 7** — Affordable & Clean Energy | Ensure access to sustainable energy | Real-time solar monitoring maximizes renewable energy utilization |
| **SDG 11** — Sustainable Cities | Make cities resilient & sustainable | Smart building-level energy monitoring tools |
| **SDG 13** — Climate Action | Urgent action on climate change | Quantifies and visualizes daily CO₂ emissions avoided through solar |

---

## 🔮 Future Scope

1. 🤖 **Smart Load Scheduling** — Shift non-critical loads to peak solar hours
2. 🚗 **EV Charger Integration** — Prioritize EV charging using excess solar power
3. 🔗 **Peer-to-Peer Energy Trading** — Surplus energy trading in local microgrids
4. 🔔 **Push Notifications** — Overload events, low battery, net-zero milestones
5. 🏢 **Multi-Building Support** — Monitor multiple installations


## 📄 License

This project is licensed under the **ISC License**.

---

<div align="center">

Made with ❤️ by the **Smart Inverter Team** | IEEE STB61541

⭐ Star this repo if you found it helpful!

</div>
