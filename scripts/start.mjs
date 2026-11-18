import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';

const rubyBin = process.platform === 'win32' && existsSync('C:\\Ruby33-x64\\bin\\ruby.exe')
  ? 'C:\\Ruby33-x64\\bin\\ruby.exe'
  : 'ruby';

console.log('Starting RailSmith Ruby engine API on http://localhost:8080...');
const engine = spawn(rubyBin, ['ruby/bin/railsmith-api'], {
  stdio: 'inherit',
  shell: true,
  env: { ...process.env, PORT: process.env.PORT || '8080' }
});

console.log('Starting RailSmith Vite dev server on http://localhost:5173...');
const vite = spawn('npx', ['vite', '--host', '0.0.0.0'], {
  stdio: 'inherit',
  shell: true
});

function cleanup() {
  try { engine.kill(); } catch {}
  try { vite.kill(); } catch {}
  process.exit();
}

process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);
process.on('exit', cleanup);
