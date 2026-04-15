// # SECCION9 LITE -- PYME Networks Controller

// -- Load PYMEs --
async function loadPymes() {
  const el = document.getElementById('pymes-body');
  try {
    const pymes = await apiFetch('/pymes');
    const online = pymes.filter(p => p.gateway_status === 'online').length;
    const totalClients = pymes.reduce((s, p) => s + (p.assigned_clients || []).length, 0);

    document.getElementById('pyme-total').textContent = pymes.length;
    document.getElementById('pyme-online').textContent = online;
    document.getElementById('pyme-clients').textContent = totalClients;

    if (!pymes.length) {
      el.innerHTML = '<tr><td colspan="6" class="empty">No networks registered</td></tr>';
      return;
    }

    el.innerHTML = pymes.map(p => `<tr>
      <td>
        <div style="font-weight:600">${esc(p.display_name)}</div>
        <div style="font-size:11px;color:var(--tx-3);font-family:var(--mono)">${esc(p.name)}</div>
      </td>
      <td class="ip-c">${esc(p.lan_subnet)}</td>
      <td class="ip-c">${esc(p.gateway_ip)}</td>
      <td>${statusBadge(p.gateway_status)}</td>
      <td>
        <span style="font-size:12px;color:var(--tx-2)">${(p.assigned_clients || []).length} clients</span>
      </td>
      <td><div class="acts">
        <button class="ibtn" title="Manage clients" onclick="showPymeClients('${esc(p.name)}')">&#128101;</button>
        <button class="ibtn" title="Gateway config" onclick="showGatewayConfig('${esc(p.name)}')">&#128196;</button>
        <button class="ibtn" title="Setup guide" onclick="showSetupGuide('${esc(p.name)}')">&#128218;</button>
        ${isAdmin(currentUser.role) ? `<button class="ibtn dng" title="Delete" onclick="deletePyme('${esc(p.name)}')">&#128465;</button>` : ''}
      </div></td>
    </tr>`).join('');
  } catch (e) { toast(e.message, 'error'); }
}

// -- Add PYME --
function showAddPyme() {
  showModal(`
    <h3>New PYME Network</h3>
    <p style="font-size:12px;color:var(--tx-2);margin-bottom:14px;line-height:1.6">
      Register a remote office. A WireGuard gateway config will be generated for their on-site device.
    </p>
    <div class="fg"><label class="fl">Identifier (slug)</label><input class="fi" id="m-pyme-name" placeholder="e.g. acme-corp"></div>
    <div class="fg"><label class="fl">Display name</label><input class="fi" id="m-pyme-display" placeholder="e.g. ACME Corporation"></div>
    <div class="fg"><label class="fl">LAN subnet (CIDR)</label><input class="fi" id="m-pyme-subnet" placeholder="192.168.1.0/24"></div>
    <div class="fg"><label class="fl">Gateway LAN interface</label><input class="fi" id="m-pyme-iface" placeholder="eth0" value="eth0"></div>
    <div class="fg"><label class="fl">LAN DNS server</label><input class="fi" id="m-pyme-dns" placeholder="192.168.1.1" value="192.168.1.1"></div>
    <div class="fg"><label class="fl">Notes (optional)</label><input class="fi" id="m-pyme-notes" placeholder="e.g. Main office Madrid"></div>
    <div class="modal-acts">
      <button class="btn btn-g btn-sm" onclick="closeModal()">Cancel</button>
      <button class="btn btn-p btn-sm" onclick="doAddPyme()">Create</button>
    </div>
  `);
  setTimeout(() => document.getElementById('m-pyme-name')?.focus(), 100);
}

async function doAddPyme() {
  const name = document.getElementById('m-pyme-name').value.trim();
  const display = document.getElementById('m-pyme-display').value.trim();
  const subnet = document.getElementById('m-pyme-subnet').value.trim();
  const iface = document.getElementById('m-pyme-iface').value.trim();
  const dns = document.getElementById('m-pyme-dns').value.trim();
  const notes = document.getElementById('m-pyme-notes').value.trim();
  if (!name || !display || !subnet) { toast('Name, display name and subnet required', 'error'); return; }
  try {
    await apiFetch('/pymes', {
      method: 'POST',
      body: JSON.stringify({
        name: name, display_name: display, lan_subnet: subnet,
        lan_interface: iface || 'eth0', lan_dns: dns || '192.168.1.1', notes: notes,
      }),
    });
    toast('Network added: ' + display);
    closeModal();
    loadPymes();
  } catch (e) { toast(e.message, 'error'); }
}

async function deletePyme(name) {
  if (!confirm('Delete network ' + name + '? This removes gateway peer and unlinks all clients.')) return;
  try {
    await apiFetch('/pymes/' + name, { method: 'DELETE' });
    toast('Network deleted');
    loadPymes();
  } catch (e) { toast(e.message, 'error'); }
}

// -- Client assignment --
async function showPymeClients(pymeName) {
  try {
    const [pyme, allClients] = await Promise.all([
      apiFetch('/pymes/' + pymeName),
      apiFetch('/clients'),
    ]);

    const assigned = pyme.assigned_clients || [];
    const available = allClients.filter(c => !assigned.includes(c.name));

    let html = `
      <h3>Clients: ${esc(pyme.display_name)}</h3>
      <p style="font-size:12px;color:var(--tx-2);margin-bottom:14px">
        Subnet: <span class="ip-c">${esc(pyme.lan_subnet)}</span>
      </p>
    `;

    // Assigned clients
    if (assigned.length) {
      html += `<div style="margin-bottom:14px">
        <div style="font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.8px;color:var(--tx-3);margin-bottom:8px">Assigned (${assigned.length})</div>`;
      html += assigned.map(name => `
        <div class="pyme-client-row">
          <span style="font-weight:600;font-size:13px">${esc(name)}</span>
          ${canManage(currentUser.role) ? `<button class="ibtn dng" title="Remove" onclick="doUnassignClient('${esc(pymeName)}','${esc(name)}')">&#10005;</button>` : ''}
        </div>
      `).join('');
      html += `</div>`;
    } else {
      html += `<div class="empty" style="padding:20px">No clients assigned</div>`;
    }

    // Add client dropdown
    if (canManage(currentUser.role) && available.length) {
      html += `
        <div style="border-top:1px solid var(--border);padding-top:14px;margin-top:14px">
          <div style="display:flex;gap:8px;align-items:flex-end">
            <div class="fg" style="flex:1;margin-bottom:0">
              <label class="fl">Add client</label>
              <select class="fi" id="m-pyme-assign-client">
                ${available.map(c => `<option value="${esc(c.name)}">${esc(c.name)} (${c.ip})</option>`).join('')}
              </select>
            </div>
            <button class="btn btn-p btn-sm" onclick="doAssignClient('${esc(pymeName)}')">Add</button>
          </div>
        </div>
      `;
    } else if (canManage(currentUser.role)) {
      html += `<p style="font-size:12px;color:var(--tx-3);margin-top:10px">All clients already assigned.</p>`;
    }

    html += `<div class="modal-acts"><button class="btn btn-g btn-sm" onclick="closeModal()">Close</button></div>`;
    showModal(html);
  } catch (e) { toast(e.message, 'error'); }
}

async function doAssignClient(pymeName) {
  const sel = document.getElementById('m-pyme-assign-client');
  if (!sel) return;
  const clientName = sel.value;
  if (!clientName) return;
  try {
    await apiFetch('/pymes/' + pymeName + '/clients', {
      method: 'POST',
      body: JSON.stringify({ client_name: clientName }),
    });
    toast(clientName + ' assigned to ' + pymeName);
    showPymeClients(pymeName); // refresh modal
    loadClients(); // refresh clients table
  } catch (e) { toast(e.message, 'error'); }
}

async function doUnassignClient(pymeName, clientName) {
  if (!confirm('Remove ' + clientName + ' from ' + pymeName + '?')) return;
  try {
    await apiFetch('/pymes/' + pymeName + '/clients/' + clientName, { method: 'DELETE' });
    toast(clientName + ' removed from ' + pymeName);
    showPymeClients(pymeName);
    loadClients();
  } catch (e) { toast(e.message, 'error'); }
}

// -- Gateway config --
async function showGatewayConfig(pymeName) {
  try {
    const data = await apiFetch('/pymes/' + pymeName + '/gateway-config');
    showModal(`
      <h3>Gateway Config: ${esc(pymeName)}</h3>
      <p style="font-size:12px;color:var(--tx-2);margin-bottom:10px">
        Install this on the PYME gateway device (Raspberry Pi, mini PC, VM, etc.)
      </p>
      <div class="cfg-blk">${esc(data.config)}</div>
      <div class="modal-acts">
        <button class="btn btn-g btn-sm" onclick="copyText(\`${data.config.replace(/`/g,'\\`').replace(/\\/g,'\\\\')}\`)">Copy</button>
        <button class="btn btn-p btn-sm" onclick="dlGwConfig('${esc(pymeName)}',\`${data.config.replace(/`/g,'\\`').replace(/\\/g,'\\\\')}\`)">Download</button>
        <button class="btn btn-g btn-sm" onclick="closeModal()">Close</button>
      </div>
    `);
  } catch (e) { toast(e.message, 'error'); }
}

function dlGwConfig(name, cfg) {
  const b = new Blob([cfg], { type: 'text/plain' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(b);
  a.download = 'pyme-' + name + '.conf';
  a.click();
}

// -- Setup guide --
async function showSetupGuide(pymeName) {
  try {
    const data = await apiFetch('/pymes/' + pymeName + '/setup-instructions');
    showModal(`
      <h3>Setup Guide: ${esc(pymeName)}</h3>
      <div class="cfg-blk" style="max-height:400px;line-height:1.8">${esc(data.instructions)}</div>
      <div class="modal-acts">
        <button class="btn btn-g btn-sm" onclick="copyText(\`${data.instructions.replace(/`/g,'\\`').replace(/\\/g,'\\\\')}\`)">Copy</button>
        <button class="btn btn-g btn-sm" onclick="closeModal()">Close</button>
      </div>
    `);
  } catch (e) { toast(e.message, 'error'); }
}
