// # SECCION9 LITE -- App Controller
let currentUser = { username: '', role: 'viewer' };
let currentPage = 'clients';
let _toastTimer = null;

// -- Init --
document.addEventListener('DOMContentLoaded', () => {
  if (localStorage.getItem('token')) {
    initApp();
  }
  document.getElementById('login-form').addEventListener('submit', handleLogin);
});

async function handleLogin(e) {
  e.preventDefault();
  const errEl = document.getElementById('login-err');
  errEl.textContent = '';
  const user = document.getElementById('login-user').value;
  const pass = document.getElementById('login-pass').value;
  try {
    const form = new URLSearchParams();
    form.append('username', user);
    form.append('password', pass);
    const res = await fetch('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
    if (!res.ok) { errEl.textContent = 'Wrong credentials'; return; }
    const data = await res.json();
    localStorage.setItem('token', data.access_token);
    initApp();
  } catch { errEl.textContent = 'Connection error'; }
}

async function initApp() {
  document.body.classList.add('authed');
  try {
    currentUser = await apiFetch('/auth/me');
    document.getElementById('side-username').textContent = currentUser.username;
    document.getElementById('side-role').innerHTML = roleBadge(currentUser.role);
  } catch { logout(); return; }
  buildNav();
  navigate('clients');
}

function buildNav() {
  const items = [
    { id: 'clients', icon: '&#9673;', label: 'Clients' },
    { id: 'invites', icon: '&#128279;', label: 'Invites' },
    { id: 'metrics', icon: '&#9636;', label: 'Metrics' },
    { id: 'server', icon: '&#9881;', label: 'Server' },
    { id: 'pymes', icon: '&#127970;', label: 'Networks' },
  ];
  if (isAdmin(currentUser.role)) items.push({ id: 'users', icon: '&#9679;', label: 'Users' });
  items.push({ id: 'audit', icon: '&#9776;', label: 'Audit' });
  if (isAdmin(currentUser.role)) items.push({ id: 'settings', icon: '&#9881;', label: 'Settings' });

  const nav = document.getElementById('side-nav');
  nav.innerHTML = items.map(i =>
    `<button class="nav-i" data-page="${i.id}" onclick="navigate('${i.id}')">${i.icon} ${i.label}</button>`
  ).join('');
}

function navigate(page) {
  currentPage = page;
  document.querySelectorAll('.nav-i').forEach(el => el.classList.toggle('on', el.dataset.page === page));
  document.querySelectorAll('.page').forEach(el => el.classList.remove('active'));
  const target = document.getElementById('p-' + page);
  if (target) target.classList.add('active');

  const loaders = {
    clients: loadClients,
    invites: loadInvites,
    metrics: loadMetrics,
    server: loadServer,
    users: loadUsers,
    audit: loadAudit,
    settings: loadSettings,
    pymes: loadPymes,
  };
  if (loaders[page]) loaders[page]();
}

function logout() {
  localStorage.removeItem('token');
  document.body.classList.remove('authed');
  location.reload();
}

function toast(msg, type) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'toast ' + (type === 'error' ? 'toast-err' : 'toast-ok');
  el.style.display = 'block';
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => el.style.display = 'none', 3000);
}

function showModal(html) {
  const bg = document.getElementById('modal-bg');
  document.getElementById('modal-content').innerHTML = html;
  bg.style.display = 'flex';
  bg.onclick = (e) => { if (e.target === bg) closeModal(); };
}

function closeModal() {
  document.getElementById('modal-bg').style.display = 'none';
}

function copyText(text) {
  navigator.clipboard.writeText(text);
  toast('Copied to clipboard');
}

// -- Clients --
async function loadClients() {
  const el = document.getElementById('clients-body');
  try {
    const [clients, pymes] = await Promise.all([
      apiFetch('/clients'),
      apiFetch('/pymes').catch(() => []),
    ]);
    const online = clients.filter(c => c.status === 'online').length;

    document.getElementById('cl-total').textContent = clients.length;
    document.getElementById('cl-online').textContent = online;

    // Build pyme lookup: client_name -> [pyme names]
    const pymeMap = {};
    for (const p of pymes) {
      for (const cn of (p.assigned_clients || [])) {
        if (!pymeMap[cn]) pymeMap[cn] = [];
        pymeMap[cn].push(p.display_name || p.name);
      }
    }

    if (!clients.length) {
      el.innerHTML = '<tr><td colspan="5" class="empty">No clients registered</td></tr>';
      return;
    }
    el.innerHTML = clients.map(c => {
      const nets = pymeMap[c.name] || [];
      const netBadges = nets.length
        ? nets.map(n => `<span class="b-role b-role-tecnico" style="font-size:9px">${esc(n)}</span>`).join(' ')
        : '<span style="font-size:11px;color:var(--tx-3)">-</span>';
      return `<tr>
        <td style="font-weight:600">${esc(c.name)}</td>
        <td class="ip-c">${c.ip || '-'}</td>
        <td>${netBadges}</td>
        <td>${statusBadge(c.status)}</td>
        <td><div class="acts">
          <button class="ibtn" title="Config" onclick="showClientConfig('${esc(c.name)}')">&#128196;</button>
          ${canManage(currentUser.role) ? `<button class="ibtn" title="Invite" onclick="inviteExisting('${esc(c.name)}')">&#128279;</button>` : ''}
          ${canManage(currentUser.role) ? `<button class="ibtn dng" title="Delete" onclick="deleteClient('${esc(c.name)}')">&#128465;</button>` : ''}
        </div></td>
      </tr>`;
    }).join('');
  } catch (e) { toast(e.message, 'error'); }
}

async function showClientConfig(name) {
  try {
    const [cfg, qr] = await Promise.all([
      apiFetch('/clients/' + name + '/config'),
      apiFetch('/clients/' + name + '/qr-base64'),
    ]);
    showModal(`
      <h3>Config: ${esc(name)}</h3>
      ${qr.qr_base64 ? `<div class="qr-wrap"><img src="${qr.qr_base64}" width="180" height="180"></div>` : ''}
      <div class="cfg-blk">${esc(cfg.config)}</div>
      <div class="modal-acts">
        <button class="btn btn-g btn-sm" onclick="copyText(\`${cfg.config.replace(/`/g,"\\`").replace(/\\/g,"\\\\")}\`)">Copy</button>
        <button class="btn btn-p btn-sm" onclick="dlConfig('${esc(name)}',\`${cfg.config.replace(/`/g,"\\`").replace(/\\/g,"\\\\")}\`)">Download</button>
        <button class="btn btn-g btn-sm" onclick="closeModal()">Close</button>
      </div>
    `);
  } catch (e) { toast(e.message, 'error'); }
}

function dlConfig(name, cfg) {
  const b = new Blob([cfg], {type:'text/plain'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(b);
  a.download = name + '.conf';
  a.click();
}

function showAddClient() {
  showModal(`
    <h3>New VPN Client</h3>
    <div class="fg"><label class="fl">Client name</label><input class="fi" id="m-cl-name" placeholder="e.g. juan-laptop"></div>
    <div class="modal-acts">
      <button class="btn btn-g btn-sm" onclick="closeModal()">Cancel</button>
      <button class="btn btn-p btn-sm" onclick="doAddClient()">Add</button>
    </div>
  `);
  setTimeout(() => document.getElementById('m-cl-name')?.focus(), 100);
}

async function doAddClient() {
  const name = document.getElementById('m-cl-name').value.trim();
  if (!name) return;
  try {
    await apiFetch('/clients', { method: 'POST', body: JSON.stringify({ name }) });
    toast('Client added: ' + name);
    closeModal();
    loadClients();
  } catch (e) { toast(e.message, 'error'); }
}

async function deleteClient(name) {
  if (!confirm('Delete client ' + name + '?')) return;
  try {
    await apiFetch('/clients/' + name, { method: 'DELETE' });
    toast('Client deleted');
    loadClients();
  } catch (e) { toast(e.message, 'error'); }
}

async function inviteExisting(name) {
  try {
    const data = await apiFetch('/invites', { method: 'POST', body: JSON.stringify({ client_name: name, create_client: false, expire_hours: 24 }) });
    toast('Invite created for ' + name);
    showInviteLink(name, data.url);
  } catch (e) { toast(e.message, 'error'); }
}

function showInviteLink(name, url) {
  showModal(`
    <h3>Invite Created</h3>
    <p style="color:var(--tx-2);margin-bottom:8px">Send this link to <b>${esc(name)}</b>:</p>
    <div class="inv-link"><input readonly value="${esc(url)}" onclick="this.select()"><button onclick="copyText('${url}')">Copy</button></div>
    <p style="font-size:11px;color:var(--yellow);margin-top:6px">Single-use link. Expires automatically.</p>
    <div class="modal-acts"><button class="btn btn-g btn-sm" onclick="closeModal()">Close</button></div>
  `);
}

// -- Invites --
async function loadInvites() {
  try {
    const invites = await apiFetch('/invites');
    const active = invites.filter(i => i.valid).length;
    document.getElementById('inv-active').textContent = active;
    document.getElementById('inv-total').textContent = invites.length;

    const el = document.getElementById('invites-body');
    if (!invites.length) { el.innerHTML = '<tr><td colspan="5" class="empty">No invites</td></tr>'; return; }
    el.innerHTML = invites.map(i => `<tr>
      <td style="font-weight:600">${esc(i.client_name)}</td>
      <td>${invBadge(i.valid, i.reason)}</td>
      <td style="font-size:12px;color:var(--tx-3)">${fmtDate(i.created_at)}</td>
      <td><span class="mono" style="font-size:11px;color:var(--tx-3)">${i.valid ? fmtRemaining(i.remaining_hours) : '-'}</span></td>
      <td><div class="acts">
        ${i.valid ? `<button class="ibtn" title="Copy link" onclick="copyText('${i.url}')">&#128203;</button>` : ''}
        ${canManage(currentUser.role) ? `<button class="ibtn dng" title="Revoke" onclick="revokeInvite('${i.token}')">&#128465;</button>` : ''}
      </div></td>
    </tr>`).join('');
  } catch (e) { toast(e.message, 'error'); }
}

function showCreateInvite() {
  showModal(`
    <h3>New Invite</h3>
    <div class="fg"><label class="fl">Employee / device name</label><input class="fi" id="m-inv-name" placeholder="e.g. juan-laptop"></div>
    <div class="chk-g"><input type="checkbox" id="m-inv-create" checked><label for="m-inv-create">Auto-create VPN profile (new employee)</label></div>
    <div class="fg"><label class="fl">Link expiration</label>
      <select class="fi" id="m-inv-hours">
        <option value="1">1 hour</option><option value="6">6 hours</option><option value="24" selected>24 hours</option><option value="48">48 hours</option><option value="168">7 days</option>
      </select>
    </div>
    <div class="modal-acts">
      <button class="btn btn-g btn-sm" onclick="closeModal()">Cancel</button>
      <button class="btn btn-p btn-sm" onclick="doCreateInvite()">Create</button>
    </div>
  `);
  setTimeout(() => document.getElementById('m-inv-name')?.focus(), 100);
}

async function doCreateInvite() {
  const name = document.getElementById('m-inv-name').value.trim();
  if (!name) return;
  const create = document.getElementById('m-inv-create').checked;
  const hours = parseInt(document.getElementById('m-inv-hours').value);
  try {
    const data = await apiFetch('/invites', { method: 'POST', body: JSON.stringify({ client_name: name, create_client: create, expire_hours: hours }) });
    toast('Invite created for ' + name);
    closeModal();
    showInviteLink(name, data.url);
    loadInvites();
  } catch (e) { toast(e.message, 'error'); }
}

async function revokeInvite(token) {
  try {
    await apiFetch('/invites/' + token, { method: 'DELETE' });
    toast('Invite revoked');
    loadInvites();
  } catch (e) { toast(e.message, 'error'); }
}

// -- Metrics --
let metricsHours = 24;
async function loadMetrics() {
  try {
    const [s, t, c, cn] = await Promise.all([
      apiFetch('/metrics/summary?hours=' + metricsHours),
      apiFetch('/metrics/traffic?hours=' + metricsHours),
      apiFetch('/metrics/clients?hours=' + metricsHours),
      apiFetch('/metrics/connections?hours=' + metricsHours),
    ]);

    document.getElementById('met-conn').textContent = s.total_connections;
    document.getElementById('met-uniq').textContent = s.unique_clients;
    document.getElementById('met-traffic').textContent = fmtBytes(s.total_rx + s.total_tx);
    document.getElementById('met-active').textContent = s.active_sessions;

    const chartEl = document.getElementById('met-chart');
    if (t.length) {
      const maxV = Math.max(...t.map(h => h.total_rx + h.total_tx), 1);
      chartEl.innerHTML = `<div class="chart-bars">${t.map((h,i) => {
        const pct = ((h.total_rx + h.total_tx) / maxV) * 100;
        return `<div class="chart-col" title="${fmtBytes(h.total_rx+h.total_tx)}"><div class="chart-bar" style="height:${Math.max(pct,1)}%"></div></div>`;
      }).join('')}</div>`;
    } else { chartEl.innerHTML = '<div class="empty">No traffic data</div>'; }

    const cnEl = document.getElementById('met-connections');
    if (cn.length) {
      cnEl.innerHTML = `<table><thead><tr><th>Client</th><th>Start</th><th>End</th><th>Duration</th><th>Traffic</th></tr></thead><tbody>${
        cn.map(c => `<tr>
          <td style="font-weight:600">${c.active ? '<span class="b-dot" style="display:inline-block;width:6px;height:6px;border-radius:50%;background:var(--green);margin-right:5px"></span>' : ''}${esc(c.client_name)}</td>
          <td style="font-size:12px;color:var(--tx-3)">${fmtDate(c.connected_at)}</td>
          <td style="font-size:12px;color:var(--tx-3)">${c.active ? '<span style="color:var(--green)">Active</span>' : (c.disconnected_at ? fmtDate(c.disconnected_at) : '-')}</td>
          <td class="mono" style="font-size:12px">${fmtDuration(c.duration_seconds)}</td>
          <td class="mono" style="font-size:11px;color:var(--tx-3)">${fmtBytes(c.bytes_rx)} / ${fmtBytes(c.bytes_tx)}</td>
        </tr>`).join('')
      }</tbody></table>`;
    } else { cnEl.innerHTML = '<div class="empty">No connections</div>'; }
  } catch (e) { toast(e.message, 'error'); }
}

function setMetricsHours(h) { metricsHours = h; loadMetrics(); }

// -- Server --
async function loadServer() {
  try {
    const s = await apiFetch('/server/status');
    document.getElementById('srv-ip').textContent = s.server_ip || '-';
    document.getElementById('srv-uptime').textContent = s.uptime || '-';
    document.getElementById('srv-wg').textContent = s.service === 'active' ? 'Active' : 'Inactive';
    document.getElementById('srv-wg').className = 'stat-v ' + (s.service === 'active' ? 'c-green' : 'c-red');
    document.getElementById('srv-peers').textContent = s.online_clients + ' / ' + s.total_clients;

    const grid = document.getElementById('srv-diag');
    grid.innerHTML = `
      ${_chk('WireGuard', s.service === 'active')}
      ${_chk('IP Forwarding', s.ip_forwarding)}
      ${_chk('Firewall (WG port)', s.ufw_wireguard)}
      <div class="st-item"><span class="st-item-l">WG Port</span><span class="st-item-v">${s.server_port}/udp</span></div>
      <div class="st-item"><span class="st-item-l">Peers Online</span><span class="st-item-v chk-ok">${s.online_clients}</span></div>
      <div class="st-item"><span class="st-item-l">Subnet</span><span class="st-item-v">${s.vpn_subnet}</span></div>
    `;

    document.getElementById('srv-json').textContent = JSON.stringify(s, null, 2);
  } catch (e) { toast(e.message, 'error'); }
}

function _chk(label, ok) {
  return `<div class="st-item"><span class="st-item-l">${label}</span><span class="st-item-v ${ok?'chk-ok':'chk-fail'}">${ok?'OK':'FAIL'}</span></div>`;
}

// -- Users --
async function loadUsers() {
  try {
    const users = await apiFetch('/users');
    document.getElementById('usr-total').textContent = users.length;
    const el = document.getElementById('users-body');
    el.innerHTML = users.map(u => `<tr>
      <td style="font-weight:600">${esc(u.username)}${u.username === currentUser.username ? ' <span style="font-size:10px;color:var(--tx-3)">(you)</span>' : ''}</td>
      <td>${roleBadge(u.role)}</td>
      <td style="font-size:12px;color:var(--tx-3)">${fmtDate(u.created_at)}</td>
      <td><div class="acts">
        <button class="ibtn" title="Reset password" onclick="showResetPass('${esc(u.username)}')">&#128273;</button>
        ${u.username !== currentUser.username ? `<button class="ibtn dng" title="Delete" onclick="deleteUser('${esc(u.username)}')">&#128465;</button>` : ''}
      </div></td>
    </tr>`).join('');
  } catch (e) { toast(e.message, 'error'); }
}

function showAddUser() {
  showModal(`
    <h3>New User</h3>
    <div class="fg"><label class="fl">Username</label><input class="fi" id="m-usr-name" placeholder="e.g. juan"></div>
    <div class="fg"><label class="fl">Password (min 8)</label><input class="fi" id="m-usr-pass" type="password"></div>
    <div class="fg"><label class="fl">Role</label><select class="fi" id="m-usr-role">
      <option value="admin">Admin</option><option value="tecnico">Tecnico</option><option value="viewer" selected>Viewer</option>
    </select></div>
    <div class="modal-acts">
      <button class="btn btn-g btn-sm" onclick="closeModal()">Cancel</button>
      <button class="btn btn-p btn-sm" onclick="doAddUser()">Create</button>
    </div>
  `);
}

async function doAddUser() {
  const name = document.getElementById('m-usr-name').value.trim();
  const pass = document.getElementById('m-usr-pass').value;
  const role = document.getElementById('m-usr-role').value;
  if (!name || !pass) return;
  try {
    await apiFetch('/users', { method: 'POST', body: JSON.stringify({ username: name, password: pass, role }) });
    toast('User created: ' + name);
    closeModal(); loadUsers();
  } catch (e) { toast(e.message, 'error'); }
}

async function deleteUser(name) {
  if (!confirm('Delete user ' + name + '?')) return;
  try {
    await apiFetch('/users/' + name, { method: 'DELETE' });
    toast('User deleted'); loadUsers();
  } catch (e) { toast(e.message, 'error'); }
}

function showResetPass(name) {
  showModal(`
    <h3>Reset password: ${esc(name)}</h3>
    <div class="fg"><label class="fl">New password</label><input class="fi" id="m-rst-pass" type="password" placeholder="Min 8 chars"></div>
    <div class="modal-acts">
      <button class="btn btn-g btn-sm" onclick="closeModal()">Cancel</button>
      <button class="btn btn-p btn-sm" onclick="doResetPass('${esc(name)}')">Reset</button>
    </div>
  `);
}

async function doResetPass(name) {
  const pass = document.getElementById('m-rst-pass').value;
  if (!pass || pass.length < 8) { toast('Min 8 chars', 'error'); return; }
  try {
    await apiFetch('/users/' + name + '/reset-password', { method: 'POST', body: JSON.stringify({ new_password: pass }) });
    toast('Password reset'); closeModal();
  } catch (e) { toast(e.message, 'error'); }
}

function showChangePass() {
  showModal(`
    <h3>Change Password</h3>
    <div class="fg"><label class="fl">Current password</label><input class="fi" id="m-cp-cur" type="password"></div>
    <div class="fg"><label class="fl">New password</label><input class="fi" id="m-cp-new" type="password" placeholder="Min 8 chars"></div>
    <div class="fg"><label class="fl">Confirm</label><input class="fi" id="m-cp-conf" type="password"></div>
    <div class="modal-acts">
      <button class="btn btn-g btn-sm" onclick="closeModal()">Cancel</button>
      <button class="btn btn-p btn-sm" onclick="doChangePass()">Change</button>
    </div>
  `);
}

async function doChangePass() {
  const cur = document.getElementById('m-cp-cur').value;
  const nw = document.getElementById('m-cp-new').value;
  const conf = document.getElementById('m-cp-conf').value;
  if (nw.length < 8) { toast('Min 8 chars', 'error'); return; }
  if (nw !== conf) { toast('Passwords do not match', 'error'); return; }
  try {
    await apiFetch('/auth/change-password', { method: 'POST', body: JSON.stringify({ current_password: cur, new_password: nw }) });
    toast('Password updated'); closeModal();
  } catch (e) { toast(e.message, 'error'); }
}

// -- Audit --
let auditHours = 24;
async function loadAudit() {
  try {
    const logs = await apiFetch('/audit?hours=' + auditHours);
    document.getElementById('aud-count').textContent = logs.length + ' entries';
    const el = document.getElementById('audit-body');
    if (!logs.length) { el.innerHTML = '<tr><td colspan="6" class="empty">No audit entries</td></tr>'; return; }
    el.innerHTML = logs.map(l => `<tr>
      <td style="font-size:11px;font-family:var(--mono);color:var(--tx-3);white-space:nowrap">${fmtDate(l.timestamp)}</td>
      <td style="font-weight:600;font-size:12px">${esc(l.username)}</td>
      <td>${roleBadge(l.role)}</td>
      <td><span style="font-family:var(--mono);font-size:11px;padding:2px 6px;border-radius:3px;background:var(--bg-1)">${esc(l.action)}</span></td>
      <td style="font-size:12px;color:var(--accent)">${esc(l.target) || '-'}</td>
      <td style="font-size:11px;font-family:var(--mono);color:var(--tx-3)">${esc(l.client_ip) || '-'}</td>
    </tr>`).join('');
  } catch (e) { toast(e.message, 'error'); }
}

function setAuditHours(h) { auditHours = h; loadAudit(); }

// -- Settings --
async function loadSettings() {
  try {
    const s = await apiFetch('/settings');
    document.getElementById('set-dns').value = s.dns_servers || '';
  } catch (e) { toast(e.message, 'error'); }
}

async function saveDns() {
  const dns = document.getElementById('set-dns').value.trim();
  try {
    await apiFetch('/settings', { method: 'PUT', body: JSON.stringify({ dns_servers: dns }) });
    toast('DNS updated');
  } catch (e) { toast(e.message, 'error'); }
}
