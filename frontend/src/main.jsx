import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import Navbar from "./components/Navbar";
import Hero from "./components/Hero";
import Catalog from "./pages/Catalog";
import CategoryTabs from "./components/CategoryTabs";
import CartDrawer from "./components/CartDrawer";
import Toast from "./components/Toast";
import Checkout from "./pages/Checkout";
import Orders from "./pages/Orders";
import AuthModal from "./components/AuthModal";

function App(){
  const [route, setRoute] = useState(window.location.hash || "#/");
  const [categories, setCategories] = useState([]);
  const [activeCat, setActiveCat] = useState("All");
  const [products, setProducts] = useState([]);
  const [cart, setCart] = useState(()=> { try { return JSON.parse(localStorage.getItem("cart")||"[]") } catch { return [] }});
  const [drawer, setDrawer] = useState(false);
  const [toast, setToast] = useState("");
  const [token, setToken] = useState(()=> localStorage.getItem("token"));
  const [user, setUser] = useState(()=> { try { return JSON.parse(localStorage.getItem("user")||"null")} catch{ return null } });
  const [loginOpen, setLoginOpen] = useState(false);

  useEffect(()=>{ const onHash = () => setRoute(window.location.hash || "#/"); window.addEventListener("hashchange", onHash); return () => window.removeEventListener("hashchange", onHash); },[]);
  useEffect(()=>{ localStorage.setItem("cart", JSON.stringify(cart)); }, [cart]);
  useEffect(()=>{ if (token) localStorage.setItem("token", token); else localStorage.removeItem("token"); }, [token]);
  useEffect(()=>{ localStorage.setItem("user", JSON.stringify(user)); }, [user]);

  async function loadCategories(){ const r = await fetch("/api/catalog/categories"); const d = await r.json(); setCategories(d||[]); }
  async function loadProducts(cat){ const url = cat && cat !== "All" ? `/api/catalog/products?category=${encodeURIComponent(cat)}` : "/api/catalog/products"; const r = await fetch(url); const d = await r.json(); setProducts(d||[]); }

  useEffect(()=>{ loadCategories(); loadProducts(activeCat); },[]);
  useEffect(()=>{ loadProducts(activeCat); }, [activeCat]);

  const addToCart = (p) => { setCart(prev=>[...prev, p]); setToast(`${p.name} added to cart`); };
  const removeFromCart = (i) => { setCart(prev=>{ const c=[...prev]; c.splice(i,1); return c; }); };

  const goCheckout = () => { setDrawer(false); window.location.hash = "#/checkout"; };
  const onOrderPlaced = (id) => { setCart([]); setToast(`Order placed (#${id}) — check email in MailHog`); window.location.hash = "#/orders"; };

  const onAuthed = (t,u)=>{ setToken(t); setUser(u); };

  const common = (
    <>
      <Navbar onCart={()=>setDrawer(true)} token={token} onLogin={()=>setLoginOpen(true)} onLogout={()=>{setToken(null); setUser(null);}} />
      <CartDrawer open={drawer} items={cart} onClose={()=>setDrawer(false)} onRemove={removeFromCart} onCheckout={goCheckout} total={cart.reduce((s,x)=>s+Number(x.price||0),0)} />
      <Toast message={toast} onClose={()=>setToast("")}/>
      <AuthModal open={loginOpen} onClose={()=>setLoginOpen(false)} onAuthed={onAuthed}/>
    </>
  );

  if (route.startsWith("#/checkout")){
    return (
      <>
        {common}
        <Checkout cart={cart} token={token} onOrderPlaced={onOrderPlaced} onNeedLogin={()=>setLoginOpen(true)} />
      </>
    )
  }

  if (route.startsWith("#/orders")){
    return (<>{common}<Orders token={token}/></>)
  }

  return (
    <>
      {common}
      <Hero />
      <div className="py-6">
        <div className="max-w-6xl mx-auto px-4 mb-4">
          <h2 className="text-2xl font-bold">Shop by Category</h2>
        </div>
        <CategoryTabs categories={categories} active={activeCat} onChange={setActiveCat}/>
      </div>
      <Catalog products={products} onAdd={addToCart}/>
      <footer className="border-t mt-12">
        <div className="max-w-6xl mx-auto px-4 py-8 text-sm text-gray-500">
          © {new Date().getFullYear()} HiQode MegaShop — Demo for DevOps Workshop
        </div>
      </footer>
    </>
  );
}

createRoot(document.getElementById("root")).render(<App/>);
