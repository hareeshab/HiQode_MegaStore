import React from "react";
import { ShoppingCart } from "lucide-react";

export default function Catalog({ products, onAdd }) {
  return (
    <section id="catalog" className="max-w-6xl mx-auto px-4 py-8">
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
        {products.map(p => (
          <div key={p._id || p.name} className="bg-white rounded-2xl shadow overflow-hidden">
            <div className="h-44">
              <img src={p.image || 'https://picsum.photos/seed/megashop/600/400'} alt=""
                   className="w-full h-full object-cover" />
            </div>
            <div className="p-4">
              <div className="text-xs text-gray-500">{p.category}</div>
              <div className="font-semibold">{p.name}</div>
              <div className="text-brand font-bold mt-1">₹{p.price}</div>
              <button className="btn mt-3" onClick={()=>onAdd(p)}>
                <ShoppingCart size={18}/> Add to cart
              </button>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
