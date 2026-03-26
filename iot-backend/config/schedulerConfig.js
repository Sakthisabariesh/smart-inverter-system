let schedulerConfig = {
  battery_power_save: 40,
  battery_critical: 20,
  solar_power_save: 200,
  solar_critical: 100
}

function getConfig() {
  return schedulerConfig
}

function updateConfig(newConfig) {

  schedulerConfig = {
    ...schedulerConfig,
    ...newConfig
  }

  return schedulerConfig
}

module.exports = { getConfig, updateConfig }