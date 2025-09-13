import React from 'react'
import { Home, ListOrdered, Send, LogOut, ShoppingBag, ShoppingCart, User } from 'lucide-react'

export default function Navbar({ onCart, token, onLogin, onLogout }){
  return (
    <header className="bg-white sticky top-0 z-40 shadow-sm">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <a href="#/" className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-xl bg-brand/10 text-brand grid place-items-center">
            <ShoppingBag size={20}/>
          </div>
          <span className="font-semibold text-lg">HiQode MegaShop</span>
        </a>
        <nav className="flex items-center gap-4 text-sm">
          <a href="#/" className="hover:text-brand">Home</a>
          <a href="#/catalog" className="hover:text-brand">Catalog</a>
          <a href="#/orders" className="hover:text-brand">Orders</a>
          <button className="btn" onClick={onCart}><ShoppingCart size={18}/> Cart</button>
          {!token ? (
            <button className="px-3 py-1.5 rounded border" onClick={onLogin}><User size={16}/> Login</button>
          ) : (
            <button className="px-3 py-1.5 rounded border" onClick={onLogout}><LogOut size={16}/> Logout</button>
          )}
        </nav>
      </div>
    </header>
  )
}
