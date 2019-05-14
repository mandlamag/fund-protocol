if (!global.fetch) global.fetch = require('node-fetch')
import express from 'express';
const cc = require('cryptocompare');
cc.setApiKey('ULfORchERgARETETYlesTRIngeNTrUbseLa')
const app = express();
const PORT=3006;

app.get('/', (req, res) => {
  res.send('ok')
});
app.get('/api/v1/portfolio', async(req, res) => {
  const prices = await cc.priceMulti(['BTC', 'ETH', 'LTC'], ['USD']);

  res.status(200).send({
    success: 'true',
    data: {value: 10000*(prices.BTC.USD),   //TODO: Fix this to point to the correct exchange the pull the correct portfolio
      usdEth: prices.ETH.USD,
      usdBtc: prices.BTC.USD,
      usdLtc: prices.LTC.USD
    }
  })
});

app.listen(PORT, ()=>{
  console.log("Server listening on: http://localhost:%s", PORT);
});