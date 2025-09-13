import React from "react";

export default function Hero() {
  return (
    <section className="relative overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_10%,rgba(11,92,255,0.08),transparent_40%),radial-gradient(circle_at_80%_10%,rgba(99,102,241,0.06),transparent_35%)]"></div>
      <div className="max-w-6xl mx-auto px-4 py-14 relative">
        <div className="grid md:grid-cols-2 gap-10 items-center">
          <div>
            <h1 className="text-4xl md:text-5xl font-extrabold leading-tight">
              DevOps-grade <span className="text-brand">E-Commerce</span> demo
            </h1>
            <p className="mt-4 text-lg text-gray-600">
              Microservices • Gateway • Queues • Emails. Looks like a real store, perfect for workshops.
            </p>
            <a href="#catalog" className="btn mt-6">Browse Products</a>
          </div>
          <div className="hidden md:block">
            {/* Simple SVG illustration */}
            <svg viewBox="0 0 600 400" className="w-full h-auto">
              <rect x="40" y="60" width="520" height="280" rx="22" fill="#fff"/>
              <rect x="40" y="60" width="520" height="60" rx="22" fill="#EFF6FF"/>
              <circle cx="80" cy="90" r="10" fill="#0b5cff"/>
              <circle cx="110" cy="90" r="10" fill="#60a5fa"/>
              <circle cx="140" cy="90" r="10" fill="#93c5fd"/>
              <rect x="80" y="140" width="440" height="160" rx="12" fill="#F9FAFB" stroke="#E5E7EB"/>
              <rect x="100" y="160" width="120" height="120" rx="14" fill="#DBEAFE"/>
              <rect x="240" y="160" width="120" height="120" rx="14" fill="#E0E7FF"/>
              <rect x="380" y="160" width="120" height="120" rx="14" fill="#FDE68A"/>
            </svg>
          </div>
        </div>
      </div>
    </section>
  );
}
