const { InfluxDB } = require('@influxdata/influxdb-client')

const url = process.env.INFLUX_URL
const token = process.env.INFLUX_TOKEN
const org = process.env.INFLUX_ORG
const bucket = process.env.INFLUX_BUCKET

const influxDB = new InfluxDB({ url, token })
const queryApi = influxDB.getQueryApi(org)

/* Get the latest single data point (all fields) */
async function getPowerData() {

const fluxQuery = `
from(bucket: "${bucket}")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "inverter_data")
  |> last()
`

let data = {}

return new Promise((resolve, reject) => {

queryApi.queryRows(fluxQuery, {

next(row, tableMeta) {

const o = tableMeta.toObject(row)

data[o._field] = o._value

},

error(error) {

reject(error)

},

complete() {

resolve(data)

}

})

})

}

/* Get historical time-series for a single field
   field : e.g. "pv_input_w", "battery_percent", "load_w", "temperature"
   range : e.g. "1h", "6h", "24h"
*/
async function getHistoryData(field, range) {

  range = range || '1h'

  // Aggregate window keeps ~60 data points per chart regardless of range
  const windowMap = { '1h': '1m', '6h': '6m', '24h': '24m' }
  const every = windowMap[range] || '1m'

  const fluxQuery = `
from(bucket: "${bucket}")
  |> range(start: -${range})
  |> filter(fn: (r) => r._measurement == "inverter_data")
  |> filter(fn: (r) => r._field == "${field}")
  |> aggregateWindow(every: ${every}, fn: mean, createEmpty: false)
  |> sort(columns: ["_time"])
`

  const points = []

  return new Promise((resolve, reject) => {
    queryApi.queryRows(fluxQuery, {
      next(row, tableMeta) {
        const o = tableMeta.toObject(row)
        points.push({
          time: o._time,
          value: o._value != null ? parseFloat(o._value.toFixed(2)) : 0
        })
      },
      error(error) { reject(error) },
      complete() { resolve(points) }
    })
  })
}

module.exports = { getPowerData, getHistoryData }