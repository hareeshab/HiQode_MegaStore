import React, { useState } from "react";
import { CreditCard, Tag } from "lucide-react";

const COUPONS = { HIQODE10: 0.10, DEVOPS20: 0.20 };

export default function Checkout({ cart, token, onOrderPlaced, onNeedLogin }) {
  const [form, setForm] = useState({ name:"", address:"", city:"", pincode:"", card:"", cvv:"", coupon:"" })
  const [placing, setPlacing] = useState(false)

  const subtotal = cart.reduce((s,x)=> s + Number(x.price||0), 0)
  const discountPct = COUPONS[form.coupon?.toUpperCase()] || 0
  const discount = Math.round(subtotal * discountPct)
  const total = Math.max(subtotal - discount, 0)

  const onChange = e => setForm({ ...form, [e.target.name]: e.target.value })

  async function placeOrder(e){
    e.preventDefault()
    if (!token) { onNeedLogin(); return }
    if (placing || cart.length === 0) return
    setPlacing(true)
    try{
      const pid = cart[0]._id || "demo"
      const fd = new FormData()
      fd.append("product_id", pid)
      const headers = { Authorization: `Bearer ${token}` }
      const r = await fetch("/api/orders/create", { method:"POST", body: fd, headers })
      const d = await r.json()
      await fetch("/api/pay/charge", { method:"POST", headers: { "Content-Type":"application/json" }, body: JSON.stringify({ order_id: d.order_id, amount: total }) })
      onOrderPlaced(d.order_id)
    } finally {
      setPlacing(false)
    }
  }

  return (
    <section className="max-w-4xl mx-auto px-4 py-10 pb-24">
      <h2 className="text-2xl font-bold mb-6">Checkout</h2>
      <div className="grid md:grid-cols-5 gap-6">
        <form onSubmit={placeOrder} className="md:col-span-3 bg-white rounded-2xl shadow p-5 space-y-4">
          <h3 className="font-semibold">Shipping Details</h3>
          <div className="grid sm:grid-cols-2 gap-3">
            <input className="border rounded px-3 py-2" placeholder="Full Name" name="name" onChange={onChange} required />
            <input className="border rounded px-3 py-2" placeholder="Pincode" name="pincode" onChange={onChange} required />
          </div>
          <input className="border rounded px-3 py-2 w-full" placeholder="Address" name="address" onChange={onChange} required />
          <div className="grid sm:grid-cols-2 gap-3">
            <input className="border rounded px-3 py-2" placeholder="City" name="city" onChange={onChange} required />
            <input className="border rounded px-3 py-2" placeholder="State" name="state" onChange={onChange} />
          </div>

          <h3 className="font-semibold pt-4">Payment</h3>
          <div className="grid sm:grid-cols-3 gap-3">
            <div className="sm:col-span-2">
              <input className="border rounded px-3 py-2 w-full" placeholder="Card Number (demo)" name="card" onChange={onChange} required />
            </div>
            <input className="border rounded px-3 py-2" placeholder="CVV" name="cvv" onChange={onChange} required />
          </div>

          <div className="grid sm:grid-cols-3 gap-3 items-center">
            <div className="sm:col-span-2 flex items-center gap-2">
              <Tag size={16}/><input className="border rounded px-3 py-2 w-full" placeholder="Coupon (HIQODE10 / DEVOPS20)" name="coupon" onChange={onChange} />
            </div>
            <div className="text-right text-sm text-gray-600">{discount ? `-₹${discount}` : ''}</div>
          </div>

          <button className="btn inline-flex items-center gap-2" disabled={placing}>
            <CreditCard size={18}/> {placing ? 'Placing…' : 'Pay & Place Order'}
          </button>
        </form>

        <aside className="md:col-span-2 bg-white rounded-2xl shadow p-5 space-y-3">
          <h3 className="font-semibold">Order Summary</h3>
          {cart.length === 0 && <div className="text-gray-500">Your cart is empty</div>}
          {cart.map((p,i)=>(
            <div key={i} className="flex items-center justify-between text-sm gap-3">
              <img src={p.image || 'https://picsum.photos/seed/megashop/80/60'} alt="" className="w-16 h-12 rounded object-cover border" />
              <div className="flex-1">
                <div className="font-medium">{p.name}</div>
                <div className="text-gray-500">{p.category}</div>
              </div>
              <div>₹{p.price}</div>
            </div>
          ))}
          <div className="flex justify-between text-sm text-gray-600">
            <div>Subtotal</div><div>₹{subtotal}</div>
          </div>
          <div className="flex justify-between text-sm text-green-600">
            <div>Discount</div><div>-₹{discount}</div>
          </div>
          <div className="border-t pt-3 flex justify-between font-semibold">
            <div>Total</div><div>₹{total}</div>
          </div>
        </aside>
      </div>
    </section>
  )
}
