import React, { useState } from "react";

export default function AuthModal({ open, onClose, onAuthed }) {
  const [email, setEmail] = useState("user@hiqode.in");
  const [password, setPassword] = useState("pass123");
  const [msg, setMsg] = useState("");

  if (!open) return null;

  const login = async () => {
    const fd = new FormData();
    fd.append("email", email); fd.append("password", password);
    const r = await fetch("/api/auth/login", { method:"POST", body: fd });
    const d = await r.json();
    if (d?.token){
      onAuthed(d.token, d.user);
      setMsg("Logged in");
      onClose();
    } else {
      setMsg("Invalid credentials");
    }
  };

  return (
    <div className="fixed inset-0 z-50">
      <div className="absolute inset-0 bg-black/40" onClick={onClose}/>
      <div className="absolute inset-0 grid place-items-center p-4">
        <div className="bg-white rounded-2xl shadow max-w-sm w-full p-5 space-y-3">
          <h3 className="font-semibold text-lg">Login</h3>
          <input className="border rounded px-3 py-2 w-full" value={email} onChange={e=>setEmail(e.target.value)} placeholder="Email"/>
          <input className="border rounded px-3 py-2 w-full" type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Password"/>
          <button className="btn w-full" onClick={login}>Sign in</button>
          <div className="text-sm text-gray-500">{msg}</div>
        </div>
      </div>
    </div>
  );
}
