import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
// /api is proxied to the Ruby engine (ruby/bin/railsmith-api, port 8080).
// When no engine is running the proxy errors and the UI falls back to
// its bundled TypeScript engine automatically.
export default defineConfig({base:'./',plugins:[react(),tailwindcss()],server:{host:'0.0.0.0',allowedHosts:true,proxy:{'/api':{target:'http://127.0.0.1:8080',changeOrigin:true}}}});
