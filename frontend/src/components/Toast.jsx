import React from "react";
export default function Toast({ message, onClose }) {
  if (!message) return null;
  return (
    <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50">
      <div className="bg-white shadow-smooth border border-gray-200 rounded-xl px-4 py-2 text-sm">
        {message}
        <button onClick={onClose} className="ml-3 text-brand">Dismiss</button>
      </div>
    </div>
  );
}
