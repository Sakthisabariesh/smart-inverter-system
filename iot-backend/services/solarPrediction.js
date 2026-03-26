app.get('/solar-prediction', async (req, res) => {

  try {

    const API_KEY = process.env.WEATHER_API_KEY
    const LAT = 10.7905
    const LON = 78.7047

    const url = `https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&appid=${API_KEY}`

    const response = await axios.get(url)

    const cloud = response.data.clouds.all

    const predictedSolar = Math.max(0, 1000 - (cloud * 8))

    res.json({
      cloud_cover: cloud,
      predicted_solar_w: predictedSolar
    })

  } catch (error) {

    res.status(500).json({ error: error.message })

  }

})