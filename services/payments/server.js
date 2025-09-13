import express from 'express'
import cors from 'cors'

const app = express()
app.use(cors())
app.use(express.json())

app.post('/charge', (req,res)=>{
  setTimeout(()=> res.json({status:'success', txn_id: 'TXN'+Date.now()}), 300)
})

app.listen(8004, ()=> console.log('Payments on 8004'))
