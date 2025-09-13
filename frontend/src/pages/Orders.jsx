import React, { useEffect, useState } from "react";

export default function Orders({ token }) {
  const [rows, setRows] = useState([]);
  useEffect(()=>{
    (async()=>{
      const r = await fetch("/api/orders/list", { headers: token ? { Authorization: `Bearer ${token}` } : {} });
      const d = await r.json();
      setRows(Array.isArray(d) ? d : []);
    })();
  }, [token]);

  return (
    <section className="max-w-4xl mx-auto px-4 py-10">
      <h2 className="text-2xl font-bold mb-6">My Orders</h2>
      <div className="bg-white rounded-2xl shadow divide-y">
        {rows.length === 0 && <div className="p-4 text-gray-500">No orders yet.</div>}
        {rows.map(o=>(
          <div key={o.id} className="p-4 flex items-center justify-between text-sm">
            <div>
              <div className="font-medium">Order #{o.id}</div>
              <div className="text-gray-500">{new Date(o.created_at).toLocaleString()}</div>
            </div>
            <div className="uppercase tracking-wide text-xs">{o.status}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
