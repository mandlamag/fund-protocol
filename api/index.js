
import express from 'express';
import feed from './db/db';
const app = express();
const PORT=3006;

app.get('/', (req, res) => {
  res.send('ok')
});

app.get('/api/v1/portfolio', (req, res) => {
  res.status(200).send({
    success: 'true',
    message: 'feed retrieved successfully',
    data: feed
  })
});

app.listen(PORT, ()=>{
  console.log("Server listening on: http://localhost:%s", PORT);
});