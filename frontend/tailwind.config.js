/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./index.html", "./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {
      colors: {
        brand: { DEFAULT: "#0b5cff", dark: "#0a46c4" }
      },
      boxShadow: {
        smooth: "0 8px 30px rgba(0,0,0,0.08)"
      }
    },
  },
  plugins: [],
};
