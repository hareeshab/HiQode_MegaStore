import express from 'express'
import cors from 'cors'
import { MongoClient } from 'mongodb'

const app = express()
app.use(cors())
app.use(express.json())

const url = process.env.MONGO_URL || 'mongodb://mongo:27017/megashop'
const client = new MongoClient(url)
await client.connect()
const db = client.db()
const products = db.collection('products')

// Unique slug
await products.createIndex({ slug: 1 }, { unique: true })

const seedData = [
  { slug:'k8s-tee',        name:'Kubernetes T-Shirt',        price:799,  category:'Clothing',  image:'https://images.unsplash.com/photo-1512436991641-6745cdb1723f?w=1200&q=80' },
  { slug:'devops-hoodie',  name:'DevOps Hoodie',             price:1299, category:'Clothing',  image:'https://images.unsplash.com/photo-1541099649105-f69ad21f3246?w=1200&q=80' },
  { slug:'docker-cap',     name:'Docker Cap',                price:399,  category:'Clothing',  image:'https://images.unsplash.com/photo-1520975922325-24e0ee3f7411?w=1200&q=80' },
  { slug:'cicd-sneakers',  name:'CI/CD Sneakers',            price:2199, category:'Footwear',  image:'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=1200&q=80' },
  { slug:'cloud-flipflops',name:'Cloud Flip-Flops',          price:349,  category:'Footwear',  image:'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=1200&q=80' },
  { slug:'coffee-beans',   name:'Organic Coffee Beans 500g', price:499,  category:'Groceries', image:'https://images.unsplash.com/photo-1503481766315-7a586b20f66f?w=1200&q=80' },
  { slug:'granola',        name:'Protein Granola 750g',      price:599,  category:'Groceries', image:'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=1200&q=80' },
  { slug:'green-tea',      name:'Green Tea (50 bags)',       price:299,  category:'Groceries', image:'https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=1200&q=80' },
];

// Seed helper — conflict-free (only $set)
async function ensureSeed({ reset = false } = {}){
  if (reset) await products.deleteMany({});
  for (const p of seedData){
    await products.updateOne({ slug: p.slug }, { $set: p }, { upsert: true });
  }
}

// Seed on startup if empty
if (await products.countDocuments() === 0) await ensureSeed({ reset: true });

app.get('/seed', async (req,res)=>{
  const reset = String(req.query.reset||'').toLowerCase() === '1'
  await ensureSeed({ reset })
  res.json({ ok:true, reset })
});

app.get('/categories', async (_req,res)=>{
  const cats = await products.distinct('category')
  res.json((cats||[]).sort())
});

app.get('/products', async (req,res)=>{
  const { category } = req.query
  const filter = category && category !== 'All' ? { category } : {}
  const list = await products.find(filter).limit(100).toArray()
  res.json(list)
});

app.listen(8002, ()=> console.log('Catalog on 8002 with seeding & images (conflict-free)'))
