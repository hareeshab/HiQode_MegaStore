import React from "react";
export default function CategoryTabs({ categories, active, onChange }) {
  return (
    <div className="max-w-6xl mx-auto px-4">
      <div className="scroll-row flex gap-2">
        {['All', ...(categories||[])].map(cat => {
          const isActive = (active || 'All') === cat
          return (
            <button
              key={cat}
              onClick={() => onChange(cat)}
              className={
                "px-3 py-1.5 rounded-full text-sm whitespace-nowrap " +
                (isActive ? "bg-brand text-white" : "bg-white border text-gray-700 hover:bg-gray-50")
              }>
              {cat}
            </button>
          )
        })}
      </div>
    </div>
  )
}
