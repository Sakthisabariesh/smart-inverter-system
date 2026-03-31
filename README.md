<div align="center">

# ⚡ Energy Monitoring System

### Real-Time Solar Energy Monitoring & Net-Zero Analysis Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-Express-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org)
[![InfluxDB](https://img.shields.io/badge/InfluxDB-Cloud-22ADF6?style=for-the-badge&logo=influxdb&logoColor=white)](https://www.influxdata.com)
[![Docker](https://img.shields.io/badge/Docker-Node--RED-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com)
[![Render](https://img.shields.io/badge/Deployed_on-Render-46E3B7?style=for-the-badge&logo=render&logoColor=white)](https://render.com)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)](https://github.com/features/actions)

<br/>

> **Green CODE Net-Zero Sprint | Building App Challenge**
> IEEE Student Branch – STB61541 | Sona College of Technology

<br/>

![License](https://img.shields.io/badge/license-ISC-green?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Web-blue?style=flat-square)
![Version](https://img.shields.io/badge/version-1.0.0-orange?style=flat-square)

</div>

---

## 📌 Overview

**Energy Monitoring System** is a cross-platform IoT application that provides **real-time visibility and intelligent analysis** of a solar-powered energy setup. It bridges the gap between raw hardware sensor data and actionable, user-friendly energy insights.

Households and small buildings can actively monitor their:
- ⚡ **Solar energy generation** (Watts)
- 🔋 **Battery voltage & status**
- 💡 **Load power consumption**
- 🌡️ **Ambient temperature**
- 🌿 **Net-Zero status, CO₂ savings, and ROI**

---

## 🏗️ System Architecture

```
[Solar Panels / Battery / Load]
            ↓  (sensor readings)
    [Smart Inverter + IoT Sensors]
            ↓  (MQTT / HTTP)
      [Node-RED — Docker Container]
            ↓  (HTTPS Write API)
    [InfluxDB Cloud — Time-Series DB]
            ↓  (Flux Query)
  [Node.js REST API — Render Cloud]
            ↓  (HTTPS / JSON)
   [Flutter App — Android & Windows]
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
| **Net-Zero Snapshot** | Net-Zero status badge, Daily ₹ Savings, CO₂ avoided — all in one row |

### 🌿 Net-Zero Analysis Screen
| Tab | Feature |
|---|---|
| **Dashboard** | Monthly Savings Bar Chart, CO₂ Reduction Tracker (🌳 tree equivalence), ROI Breakdown, Baseline vs. Solar chart |
| **Settings** | Configurable Electricity Rate (₹/kWh), CO₂ Factor (kg/kWh), System Cost (₹), Baseline Load (kWh) with live preview |

---

## 🛠️ Tech Stack

| Layer | Technology | Details |
|---|---|---|
| **Frontend** | Flutter (Dart) | Cross-platform: Android, Windows, Web |
| **UI Libraries** | `fl_chart`, `google_fonts`, `shared_preferences` | Charts, typography, local settings |
| **Backend API** | Node.js + Express | REST API deployed on Render |
| **Database** | InfluxDB Cloud | Time-series, Flux query language |
| **IoT Pipeline** | Node-RED | MQTT/HTTP bridge, runs in Docker |
| **CI/CD** | GitHub Actions | Android APK + Windows EXE builds |
| **Hosting** | Render (API), InfluxDB Cloud (DB) | Free-tier cloud deployments |

---

## 📁 Project Structure

```
smart-inverter-system/
├── iot-backend/                  # Node.js REST API
│   ├── app.js                    # Express server entry point
│   ├── influx.js                 # InfluxDB client & queries
│   ├── config/                   # Configuration files
│   ├── models/                   # Data models
│   ├── services/                 # Business logic services
│   ├── .env.example              # Environment variable template
│   └── package.json
│
├── smart_inverter_app/           # Flutter frontend
│   ├── lib/
│   │   └── main.dart             # App entry point & all screens
│   ├── android/                  # Android build config
│   ├── windows/                  # Windows build config
│   ├── web/                      # Web build config
│   └── pubspec.yaml              # Flutter dependencies
│
├── .github/
│   └── workflows/
│       └── flutter-build.yml     # CI/CD: APK + EXE builds
│
├── smart_inverter_architecture.drawio   # System architecture diagram
├── render.yaml                          # Render deployment config
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Flutter SDK | ≥ 3.x | Frontend development |
| Dart SDK | ≥ 3.10.3 | Dart language runtime |
| Node.js | ≥ 18.x | Backend API runtime |
| Docker | Latest | Running Node-RED |
| InfluxDB Cloud | — | Time-series database (free tier) |

---

### 1️⃣ Backend Setup (Node.js API)

```bash
# Navigate to backend directory
cd iot-backend

# Install dependencies
npm install

# Copy environment template and fill in your values
cp .env.example .env
```

Edit `.env` with your credentials:

```env
INFLUXDB_URL=https://your-influxdb-cloud-url
INFLUXDB_TOKEN=your_influxdb_token
INFLUXDB_ORG=your_org
INFLUXDB_BUCKET=your_bucket
PORT=3000
```

```bash
# Start the API server
npm start
```

---

### 2️⃣ Node-RED (IoT Pipeline — Docker)

```bash
# Pull and run Node-RED in Docker
docker run -it -p 1880:1880 --name mynodered nodered/node-red
```

Then import your Node-RED flow to:
1. Subscribe to MQTT topics from the inverter sensors
2. Transform the payload
3. POST data to InfluxDB Cloud via Write API

---

### 3️⃣ Flutter App Setup

```bash
# Navigate to Flutter project
cd smart_inverter_app

# Install Flutter packages
flutter pub get

# Run on Android device / emulator
flutter run

# Build Android APK
flutter build apk --release

# Build Windows executable
flutter build windows --release
```

> **API Base URL:** Update the API base URL in `lib/main.dart` to point to your deployed Render backend or `localhost:3000` for local development.

---

## 🔁 CI/CD Pipeline

This project uses **GitHub Actions** to automatically build the app on every push/PR to `main`.

```
Push to main
    └─▶ GitHub Actions (flutter-build.yml)
            ├─▶ Build Android APK  → Upload as artifact
            └─▶ Build Windows EXE  → Upload as artifact
```

The backend is **auto-deployed to Render** on every push to the `main` branch via `render.yaml`.

---

## 📊 API Endpoints

Base URL: `https://your-api.onrender.com`

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/latest` | Fetch the most recent sensor reading |
| `GET` | `/api/history` | Fetch historical time-series data |

**Sample Response (`/api/latest`):**
```json
{
  "solar_power": 1240.5,
  "load_power": 980.2,
  "battery_voltage": 48.6,
  "temperature": 34.1,
  "timestamp": "2026-03-31T07:00:00Z"
}
```

---

## 🌍 SDG Alignment

| SDG | Goal | Our Contribution |
|---|---|---|
| **SDG 7** — Affordable & Clean Energy | Ensure access to sustainable energy | Real-time solar monitoring maximizes renewable energy utilization |
| **SDG 11** — Sustainable Cities | Make cities resilient & sustainable | Smart building-level energy monitoring tools for greener urban infrastructure |
| **SDG 13** — Climate Action | Urgent action on climate change | Quantifies and visualizes daily CO₂ emissions avoided through solar use |

---

## 🔮 Future Scope

1. 🤖 **AI-Based Smart Load Scheduling** — Shift non-critical loads to peak solar hours using ML predictions
2. 🚗 **EV Charger Integration** — Prioritize EV charging using excess solar power
3. 🔗 **Peer-to-Peer Energy Trading** — Blockchain-based surplus energy trading in local microgrids
4. 🔔 **Push Notifications & Alerts** — Overload events, low battery, net-zero milestones
5. 🏢 **Multi-Building Support** — Monitor multiple installations across a campus

---

## 📦 Dependencies

### Flutter (`pubspec.yaml`)
```yaml
dependencies:
  http: ^1.6.0              # REST API calls
  google_fonts: ^6.2.1      # Modern typography
  fl_chart: ^0.69.0         # Charts & graphs
  shared_preferences: ^2.5.5 # Persistent local settings
```

### Node.js (`package.json`)
```json
{
  "@influxdata/influxdb-client": "^1.35.0",
  "express": "^4.22.1",
  "cors": "^2.8.6",
  "dotenv": "^17.3.1",
  "axios": "^1.13.6"
}
```

---

## 👥 Team

> **IEEE STB61541 — Sona College of Technology, Salem**
> Submitted for: *Green CODE Net-Zero Sprint Building App Challenge — April 08, 2026*

| Name | Role |
|---|---|
| _____________________ | Lead Developer |
| _____________________ | IoT & Backend |
| _____________________ | UI/UX Design |
| _____________________ | Data Analysis |

**Department:** _____________________

---

## 📄 License

This project is licensed under the **ISC License**.

---

<div align="center">

Made with ❤️ by the **Smart Inverter Team** | IEEE STB61541

⭐ Star this repo if you found it helpful!

</div>
