const axios = require('axios')

const NODE_RED_URL = "http://localhost:1880"

async function controlRelay(loadName, action) {

  try {

    const url = `${NODE_RED_URL}/relay/${loadName}/${action}`

    const response = await axios.post(url)

    return response.data

  } catch (error) {

    console.error("Relay control error:", error.message)

    return null

  }

}

module.exports = { controlRelay }