require('dotenv').config()

const express = require('express')
const cors = require('cors')
const axios = require('axios')

const { getPowerData, getHistoryData, keepInfluxAlive } = require('./influx')
const { getSystemMode, applyLoadScheduling } = require('./services/scheduler')
const { updateConfig, getConfig } = require('./config/schedulerConfig')
const { getLoads, updateLoad } = require('./models/loads')

const app = express()

app.use(cors())
app.use(express.json())

/* Root check */
app.get('/', (req, res) => {
  res.send("Smart Energy Backend Running")
})

/* Get inverter data */
app.get('/power', async (req, res) => {

  try {

    const data = await getPowerData()

    // Normalise field names for the Flutter client.
    // InfluxDB stores: battery_percent, battery_voltage, pv_input_w, load_w, temperature
    const normalized = {
      ...data,
      battery:     data.battery_percent  ?? 0,
      voltage:     data.battery_voltage  ?? 0,
      power:       data.pv_input_w       ?? 0,
      current:     data.pv_input_w && data.battery_voltage
                     ? parseFloat((data.pv_input_w / data.battery_voltage).toFixed(2))
                     : 0,
      solar_w:     data.pv_input_w       ?? 0,
      load_w:      data.load_w           ?? 0,
      temperature: data.temperature      ?? 0,
    }

    res.json(normalized)

  } catch (error) {

    res.status(500).json({ error: error.message })

  }

})
/* Get historical time-series data
   GET /history?field=pv_input_w&range=1h
   field options : pv_input_w | load_w | battery_percent | temperature
   range options : 1h | 6h | 24h
*/
app.get('/history', async (req, res) => {

  const field = req.query.field || 'pv_input_w'
  const range = req.query.range || '1h'

  // Validate inputs
  const allowedFields = ['pv_input_w', 'load_w', 'battery_percent', 'temperature', 'battery_voltage']
  const allowedRanges = ['1h', '6h', '24h']

  if (!allowedFields.includes(field)) {
    return res.status(400).json({ error: `Invalid field. Allowed: ${allowedFields.join(', ')}` })
  }
  if (!allowedRanges.includes(range)) {
    return res.status(400).json({ error: `Invalid range. Allowed: ${allowedRanges.join(', ')}` })
  }

  try {
    const points = await getHistoryData(field, range)
    res.json({ field, range, points })
  } catch (error) {
    res.status(500).json({ error: error.message })
  }

})

/* Get system status and apply scheduler */
app.get('/system-status', async (req, res) => {

  try {

    const data = await getPowerData()

    const status = getSystemMode(data)

    const loads = applyLoadScheduling(status.mode)

    res.json({
      system: status,
      loads: loads
    })

  } catch (error) {

    res.status(500).json({ error: error.message })

  }

})

/* Get scheduler configuration */
app.get('/scheduler-config', (req, res) => {

  res.json(getConfig())

})

/* Update scheduler configuration */
app.post('/scheduler-config', (req, res) => {

  const newConfig = req.body

  const updated = updateConfig(newConfig)

  res.json(updated)

})

/* Get all loads */
app.get('/loads', (req, res) => {

  res.json(getLoads())

})

/* Update specific load */
app.post('/loads/:id', (req, res) => {

  const id = parseInt(req.params.id)

  const updatedLoads = updateLoad(id, req.body)

  res.json(updatedLoads)

})

/* Solar prediction API */
app.get('/solar-prediction', async (req, res) => {

  try {

    const API_KEY = process.env.WEATHER_API_KEY
    const CITY = "Trichy"

    const url = `https://api.openweathermap.org/data/2.5/forecast?q=${CITY}&appid=${API_KEY}`

    const response = await axios.get(url)

    const cloud = response.data.list[0].clouds.all

    const predictedSolar = Math.max(0, 1000 - (cloud * 8))

    res.json({
      cloud_cover: cloud,
      predicted_solar_w: predictedSolar
    })

  } catch (error) {

    res.status(500).json({ error: error.message })

  }

})

/* Start server */
const PORT = process.env.PORT || 3000

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`)
  
  // Keep Influx Serverless cloud alive
  keepInfluxAlive()
  setInterval(keepInfluxAlive, 10 * 60 * 1000)
})