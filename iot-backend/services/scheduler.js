const { controlRelay } = require('./relayController')
const { getConfig } = require('../config/schedulerConfig')
const { getLoads, updateLoad } = require('../models/loads')

function getSystemMode(data) {

  const config = getConfig()

  const battery = data.battery_percent
  const solar = data.pv_input_w
  const load = data.load_w

  let mode = "NORMAL"

  if (battery < config.battery_power_save && solar < config.solar_power_save) {
    mode = "POWER_SAVE"
  }

  if (battery < config.battery_critical && solar < config.solar_critical) {
    mode = "CRITICAL"
  }

  return {
    battery,
    solar,
    load,
    mode
  }
}


function applyLoadScheduling(systemMode) {

  let loads = getLoads()

  if (systemMode === "NORMAL") {

    loads.forEach(load => {
      updateLoad(load.id, { status: "ON" })
    })

  }

  if (systemMode === "POWER_SAVE") {

    loads.forEach(load => {

      if (load.priority >= 3) {
        updateLoad(load.id, { status: "OFF" })
      }

    })

  }

  if (systemMode === "CRITICAL") {

    loads.forEach(load => {

      if (load.priority > 1) {
        updateLoad(load.id, { status: "OFF" })
      }

    })

  }

  return getLoads()

}

module.exports = { getSystemMode, applyLoadScheduling }