// # SECCION9 LITE — API Client (vanilla JS)
const API = '/api';

async function apiFetch(path, opts = {}) {
  const token = localStorage.getItem('token');
  const headers = { 'Content-Type': 'application/json', ...opts.headers };
  if (token) headers['Authorization'] = 'Bearer ' + token;
  const res = await fetch(API + path, { ...opts, headers });
  if (res.status === 401) { localStorage.removeItem('token'); location.reload(); return null; }
  if (res.status === 403) { const e = await res.json().catch(() => ({ detail: 'Access denied' })); throw new Error(e.detail || 'Forbidden'); }
  if (!res.ok) { const e = await res.json().catch(() => ({ detail: 'Unknown error' })); throw new Error(e.detail || 'Error ' + res.status); }
  const ct = res.headers.get('content-type');
  if (ct && ct.includes('image')) return URL.createObjectURL(await res.blob());
  return res.json();
}

function canManage(role) { return role === 'admin' || role === 'tecnico'; }
function isAdmin(role) { return role === 'admin'; }

function fmtBytes(b) {
  if (!b) return '0 B';
  const u = ['B','KB','MB','GB','TB'];
  const i = Math.floor(Math.log(b) / Math.log(1024));
  return (b / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0) + ' ' + u[i];
}

function fmtDate(ts) {
  if (!ts) return '-';
  return new Date(ts * 1000).toLocaleString('es-ES', { day:'2-digit', month:'2-digit', year:'2-digit', hour:'2-digit', minute:'2-digit' });
}

function fmtDuration(s) {
  if (!s || s <= 0) return '-';
  if (s < 60) return s + 's';
  if (s < 3600) return Math.floor(s/60) + 'min';
  return Math.floor(s/3600) + 'h ' + Math.floor((s%3600)/60) + 'min';
}

function fmtRemaining(h) {
  if (h <= 0) return 'Expired';
  if (h < 1) return Math.round(h * 60) + 'min';
  return h + 'h';
}

function statusBadge(s) {
  const m = { online: ['b-online','Online'], inactive: ['b-inactive','Inactive'], offline: ['b-offline','Offline'], active: ['b-online','Active'] };
  const [cls, lbl] = m[s] || m.offline;
  return `<span class="badge ${cls}"><span class="b-dot"></span>${lbl}</span>`;
}

function roleBadge(r) {
  return `<span class="b-role b-role-${r||'viewer'}">${r||'viewer'}</span>`;
}

function invBadge(valid, reason) {
  if (valid) return '<span class="badge b-valid"><span class="b-dot"></span>Active</span>';
  if (reason === 'expired') return '<span class="badge b-expired">Expired</span>';
  return '<span class="badge b-used">Used</span>';
}

function esc(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
