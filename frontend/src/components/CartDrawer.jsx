import React from "react";
import { X, Trash2 } from "lucide-react";

export default function CartDrawer({ open, items, onClose, onRemove, onCheckout, total }) {
  return (
    <div className={`fixed inset-0 z-50 ${open ? '' : 'pointer-events-none'}`}>
      <div
        className={`absolute inset-0 bg-black/40 transition-opacity ${open ? 'opacity-100' : 'opacity-0'}`}
        onClick={onClose}
      />
      <aside className={`absolute right-0 top-0 h-full w-full sm:w-[420px] bg-white shadow-xl
        transition-transform ${open ? 'translate-x-0' : 'translate-x-full'} flex flex-col`}>
        <div className="p-4 flex items-center justify-between border-b shrink-0">
          <h3 className="font-semibold text-lg">Your Cart</h3>
          <button onClick={onClose}><X/></button>
        </div>
        <div className="p-4 space-y-3 overflow-y-auto grow">
          {items.length === 0 && <p className="text-gray-500">Cart is empty</p>}
          {items.map((it, i) => (
            <div key={i} className="bg-white rounded-xl shadow border p-4 flex justify-between items-center">
              <div>
                <div className="font-medium">{it.name}</div>
                <div className="text-sm text-gray-500">₹{it.price}</div>
              </div>
              <button className="text-red-600 hover:text-red-700" onClick={()=>onRemove(i)}><Trash2 size={18}/></button>
            </div>
          ))}
        </div>
        <div className="p-4 border-t shrink-0 bg-white">
          <div className="flex items-center justify-between mb-3">
            <span className="text-gray-600">Subtotal</span>
            <span className="font-semibold">₹{total}</span>
          </div>
          <button className="btn w-full" onClick={onCheckout}>Checkout</button>
        </div>
      </aside>
    </div>
  );
}
