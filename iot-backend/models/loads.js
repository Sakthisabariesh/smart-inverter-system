let loads = [
  {
    id: 1,
    name: "Hall Light",
    power: 10,
    priority: 1,
    status: "ON"
  },
  {
    id: 2,
    name: "Bedroom Light",
    power: 10,
    priority: 2,
    status: "ON"
  },
  {
    id: 3,
    name: "Kitchen Light",
    power: 15,
    priority: 3,
    status: "ON"
  }
]

function getLoads() {
  return loads
}

function updateLoad(id, data) {

  loads = loads.map(load => {
    if (load.id === id) {
      return { ...load, ...data }
    }
    return load
  })

  return loads
}

module.exports = { getLoads, updateLoad }