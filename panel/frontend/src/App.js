import React, { useState, useEffect, useCallback } from 'react';

// ─── API Helper ───────────────────────────────────────────────
const API = '/api';

async function apiFetch(path, options = {}) {
  const token = localStorage.getItem('token');
  const headers = { 'Content-Type': 'application/json', ...options.headers };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(`${API}${path}`, { ...options, headers });
  if (res.status === 401) {
    localStorage.removeItem('token');
    window.location.reload();
    return null;
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: 'Error desconocido' }));
    throw new Error(err.detail || `Error ${res.status}`);
  }
  if (res.headers.get('content-type')?.includes('image')) {
    return URL.createObjectURL(await res.blob());
  }
  return res.json();
}

// ─── Styles ───────────────────────────────────────────────────
const styles = `
  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
  
  :root {
    --bg-primary: #0a0e17;
    --bg-secondary: #111827;
    --bg-card: #1a2233;
    --bg-card-hover: #1e2a3f;
    --border: #2a3550;
    --border-light: #374463;
    --text-primary: #e8edf5;
    --text-secondary: #8896b0;
    --text-muted: #5a6a85;
    --accent: #3b82f6;
    --accent-hover: #2563eb;
    --accent-glow: rgba(59, 130, 246, 0.15);
    --green: #10b981;
    --green-bg: rgba(16, 185, 129, 0.1);
    --yellow: #f59e0b;
    --yellow-bg: rgba(245, 158, 11, 0.1);
    --red: #ef4444;
    --red-bg: rgba(239, 68, 68, 0.1);
    --font-body: 'Plus Jakarta Sans', -apple-system, sans-serif;
    --font-mono: 'JetBrains Mono', monospace;
    --radius: 12px;
    --radius-sm: 8px;
  }

  body {
    font-family: var(--font-body);
    background: var(--bg-primary);
    color: var(--text-primary);
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
  }

  /* ── Login ── */
  .login-wrapper {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: radial-gradient(ellipse at 50% 0%, rgba(59,130,246,0.08) 0%, transparent 60%),
                var(--bg-primary);
  }
  .login-box {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 48px 40px;
    width: 100%;
    max-width: 400px;
    box-shadow: 0 25px 60px rgba(0,0,0,0.4);
  }
  .login-logo {
    font-family: var(--font-mono);
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 3px;
    text-transform: uppercase;
    color: var(--accent);
    margin-bottom: 8px;
  }
  .login-title {
    font-size: 24px;
    font-weight: 700;
    margin-bottom: 32px;
    color: var(--text-primary);
  }
  .form-group { margin-bottom: 20px; }
  .form-label {
    display: block;
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
    margin-bottom: 8px;
    letter-spacing: 0.3px;
  }
  .form-input {
    width: 100%;
    padding: 12px 16px;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    color: var(--text-primary);
    font-family: var(--font-body);
    font-size: 14px;
    outline: none;
    transition: border-color 0.2s;
  }
  .form-input:focus { border-color: var(--accent); }
  .form-input::placeholder { color: var(--text-muted); }

  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 12px 24px;
    border-radius: var(--radius-sm);
    font-family: var(--font-body);
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    border: none;
    transition: all 0.2s;
    text-decoration: none;
  }
  .btn-primary {
    background: var(--accent);
    color: white;
    width: 100%;
  }
  .btn-primary:hover { background: var(--accent-hover); }
  .btn-sm { padding: 8px 16px; font-size: 13px; }
  .btn-danger { background: var(--red); color: white; }
  .btn-danger:hover { background: #dc2626; }
  .btn-ghost {
    background: transparent;
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }
  .btn-ghost:hover { background: var(--bg-card-hover); color: var(--text-primary); }
  .btn-success { background: var(--green); color: white; }

  .error-msg {
    background: var(--red-bg);
    color: var(--red);
    padding: 10px 14px;
    border-radius: var(--radius-sm);
    font-size: 13px;
    margin-bottom: 16px;
    border: 1px solid rgba(239,68,68,0.2);
  }

  /* ── Layout ── */
  .app-layout { display: flex; min-height: 100vh; }
  .sidebar {
    width: 260px;
    background: var(--bg-secondary);
    border-right: 1px solid var(--border);
    padding: 24px 0;
    display: flex;
    flex-direction: column;
    position: fixed;
    top: 0;
    left: 0;
    bottom: 0;
    z-index: 10;
  }
  .sidebar-brand {
    padding: 0 24px 24px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 16px;
  }
  .sidebar-brand h1 {
    font-family: var(--font-mono);
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 3px;
    text-transform: uppercase;
    color: var(--accent);
  }
  .sidebar-brand p {
    font-size: 12px;
    color: var(--text-muted);
    margin-top: 4px;
  }
  .nav-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 24px;
    font-size: 14px;
    font-weight: 500;
    color: var(--text-secondary);
    cursor: pointer;
    transition: all 0.15s;
    border: none;
    background: none;
    width: 100%;
    text-align: left;
  }
  .nav-item:hover { color: var(--text-primary); background: rgba(255,255,255,0.03); }
  .nav-item.active {
    color: var(--accent);
    background: var(--accent-glow);
    border-right: 2px solid var(--accent);
  }
  .nav-icon { font-size: 18px; width: 24px; text-align: center; }
  .sidebar-footer {
    margin-top: auto;
    padding: 16px 24px;
    border-top: 1px solid var(--border);
  }

  .main-content {
    margin-left: 260px;
    flex: 1;
    padding: 32px 40px;
    max-width: 1200px;
  }
  .page-header {
    margin-bottom: 32px;
  }
  .page-title {
    font-size: 28px;
    font-weight: 800;
    color: var(--text-primary);
    letter-spacing: -0.5px;
  }
  .page-subtitle {
    font-size: 14px;
    color: var(--text-secondary);
    margin-top: 4px;
  }

  /* ── Stats Grid ── */
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px;
    margin-bottom: 32px;
  }
  .stat-card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
  }
  .stat-label {
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--text-muted);
    margin-bottom: 8px;
  }
  .stat-value {
    font-size: 28px;
    font-weight: 800;
    font-family: var(--font-mono);
  }
  .stat-value.green { color: var(--green); }
  .stat-value.yellow { color: var(--yellow); }
  .stat-value.blue { color: var(--accent); }

  /* ── Table ── */
  .table-card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    overflow: hidden;
  }
  .table-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 20px 24px;
    border-bottom: 1px solid var(--border);
  }
  .table-header h3 { font-size: 16px; font-weight: 700; }
  table { width: 100%; border-collapse: collapse; }
  thead th {
    text-align: left;
    padding: 12px 24px;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--text-muted);
    border-bottom: 1px solid var(--border);
    background: rgba(0,0,0,0.15);
  }
  tbody td {
    padding: 16px 24px;
    font-size: 14px;
    border-bottom: 1px solid rgba(255,255,255,0.03);
    vertical-align: middle;
  }
  tbody tr:hover { background: rgba(255,255,255,0.02); }
  .ip-cell {
    font-family: var(--font-mono);
    font-size: 13px;
    color: var(--accent);
  }
  .key-cell {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--text-muted);
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* ── Status Badge ── */
  .badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    border-radius: 100px;
    font-size: 12px;
    font-weight: 600;
  }
  .badge-online { background: var(--green-bg); color: var(--green); }
  .badge-inactive { background: var(--yellow-bg); color: var(--yellow); }
  .badge-offline { background: var(--red-bg); color: var(--red); }
  .badge-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }
  .badge-online .badge-dot { animation: pulse 2s infinite; }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }

  /* ── Actions ── */
  .actions-cell { display: flex; gap: 8px; }
  .icon-btn {
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 14px;
    transition: all 0.15s;
  }
  .icon-btn:hover { background: var(--bg-card-hover); color: var(--text-primary); }
  .icon-btn.danger:hover { background: var(--red-bg); color: var(--red); border-color: var(--red); }

  /* ── Modal ── */
  .modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.6);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
    animation: fadeIn 0.15s;
  }
  .modal {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 32px;
    width: 100%;
    max-width: 480px;
    box-shadow: 0 30px 80px rgba(0,0,0,0.5);
    animation: slideUp 0.2s;
  }
  .modal h3 {
    font-size: 18px;
    font-weight: 700;
    margin-bottom: 20px;
  }
  .modal-actions {
    display: flex;
    gap: 12px;
    justify-content: flex-end;
    margin-top: 24px;
  }
  @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
  @keyframes slideUp { from { transform: translateY(10px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }

  /* ── Config Display ── */
  .config-block {
    background: var(--bg-primary);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    padding: 16px;
    font-family: var(--font-mono);
    font-size: 12px;
    line-height: 1.7;
    color: var(--text-secondary);
    white-space: pre-wrap;
    word-break: break-all;
    max-height: 300px;
    overflow-y: auto;
  }

  .qr-container {
    display: flex;
    justify-content: center;
    margin: 16px 0;
  }
  .qr-container img {
    border-radius: var(--radius-sm);
    border: 1px solid var(--border);
  }

  /* ── Server Status ── */
  .status-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    margin-top: 16px;
  }
  .status-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
  }
  .status-item-label {
    font-size: 13px;
    color: var(--text-secondary);
  }
  .status-item-value {
    font-family: var(--font-mono);
    font-size: 13px;
    font-weight: 600;
  }
  .check-ok { color: var(--green); }
  .check-fail { color: var(--red); }

  /* ── Responsive ── */
  @media (max-width: 768px) {
    .sidebar { display: none; }
    .main-content { margin-left: 0; padding: 20px; }
    .stats-grid { grid-template-columns: 1fr 1fr; }
    .status-grid { grid-template-columns: 1fr; }
  }

  /* ── Toast ── */
  .toast {
    position: fixed;
    bottom: 24px;
    right: 24px;
    padding: 14px 20px;
    border-radius: var(--radius-sm);
    font-size: 14px;
    font-weight: 500;
    z-index: 200;
    animation: slideUp 0.2s;
    box-shadow: 0 10px 30px rgba(0,0,0,0.3);
  }
  .toast-success { background: var(--green); color: white; }
  .toast-error { background: var(--red); color: white; }

  .empty-state {
    text-align: center;
    padding: 60px 20px;
    color: var(--text-muted);
  }
  .empty-state p { margin-top: 8px; font-size: 14px; }
`;

// ─── Components ───────────────────────────────────────────────

function StatusBadge({ status }) {
  const map = {
    online: { cls: 'badge-online', label: 'Conectado' },
    inactive: { cls: 'badge-inactive', label: 'Inactivo' },
    offline: { cls: 'badge-offline', label: 'Sin conexión' },
  };
  const s = map[status] || map.offline;
  return (
    <span className={`badge ${s.cls}`}>
      <span className="badge-dot" />
      {s.label}
    </span>
  );
}

function Toast({ message, type, onClose }) {
  useEffect(() => {
    const t = setTimeout(onClose, 3000);
    return () => clearTimeout(t);
  }, [onClose]);
  return <div className={`toast toast-${type}`}>{message}</div>;
}

// ─── Login Screen ─────────────────────────────────────────────

function LoginScreen({ onLogin }) {
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const form = new URLSearchParams();
      form.append('username', user);
      form.append('password', pass);
      const res = await fetch(`${API}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: form,
      });
      if (!res.ok) {
        setError('Usuario o contraseña incorrectos');
        return;
      }
      const data = await res.json();
      localStorage.setItem('token', data.access_token);
      onLogin();
    } catch {
      setError('Error de conexión');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-wrapper">
      <form className="login-box" onSubmit={handleSubmit}>
        <div className="login-logo">SECCION9</div>
        <h2 className="login-title">VPN Manager</h2>
        {error && <div className="error-msg">{error}</div>}
        <div className="form-group">
          <label className="form-label">Usuario</label>
          <input className="form-input" placeholder="admin" value={user}
            onChange={(e) => setUser(e.target.value)} autoFocus />
        </div>
        <div className="form-group">
          <label className="form-label">Contraseña</label>
          <input className="form-input" type="password" placeholder="••••••••"
            value={pass} onChange={(e) => setPass(e.target.value)} />
        </div>
        <button className="btn btn-primary" type="submit" disabled={loading}>
          {loading ? 'Conectando...' : 'Iniciar sesión'}
        </button>
      </form>
    </div>
  );
}

// ─── Dashboard ────────────────────────────────────────────────

function Dashboard() {
  const [page, setPage] = useState('clients');
  const [clients, setClients] = useState([]);
  const [serverStatus, setServerStatus] = useState(null);
  const [showAddModal, setShowAddModal] = useState(false);
  const [showConfigModal, setShowConfigModal] = useState(null);
  const [showDeleteModal, setShowDeleteModal] = useState(null);
  const [newName, setNewName] = useState('');
  const [toast, setToast] = useState(null);
  const [loading, setLoading] = useState(true);

  const notify = (message, type = 'success') => setToast({ message, type });

  const loadClients = useCallback(async () => {
    try {
      const data = await apiFetch('/clients');
      setClients(data || []);
    } catch (e) {
      notify(e.message, 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  const loadServerStatus = useCallback(async () => {
    try {
      const data = await apiFetch('/server/status');
      setServerStatus(data);
    } catch (e) {
      notify(e.message, 'error');
    }
  }, []);

  useEffect(() => {
    loadClients();
    loadServerStatus();
    const interval = setInterval(() => {
      loadClients();
      loadServerStatus();
    }, 15000);
    return () => clearInterval(interval);
  }, [loadClients, loadServerStatus]);

  const handleAdd = async () => {
    if (!newName.trim()) return;
    try {
      await apiFetch('/clients', {
        method: 'POST',
        body: JSON.stringify({ name: newName.trim() }),
      });
      notify(`Cliente '${newName}' añadido`);
      setShowAddModal(false);
      setNewName('');
      loadClients();
    } catch (e) {
      notify(e.message, 'error');
    }
  };

  const handleDelete = async (name) => {
    try {
      await apiFetch(`/clients/${name}`, { method: 'DELETE' });
      notify(`Cliente '${name}' eliminado`);
      setShowDeleteModal(null);
      loadClients();
    } catch (e) {
      notify(e.message, 'error');
    }
  };

  const handleShowConfig = async (name) => {
    try {
      const [confData, qrData] = await Promise.all([
        apiFetch(`/clients/${name}/config`),
        apiFetch(`/clients/${name}/qr-base64`),
      ]);
      setShowConfigModal({
        name,
        config: confData?.config,
        qr: qrData?.qr_base64,
      });
    } catch (e) {
      notify(e.message, 'error');
    }
  };

  const copyConfig = (config) => {
    navigator.clipboard.writeText(config);
    notify('Config copiada al portapapeles');
  };

  const downloadConfig = (name, config) => {
    const blob = new Blob([config], { type: 'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${name}.conf`;
    a.click();
  };

  const logout = () => {
    localStorage.removeItem('token');
    window.location.reload();
  };

  const online = clients.filter((c) => c.status === 'online').length;
  const inactive = clients.filter((c) => c.status === 'inactive').length;

  return (
    <div className="app-layout">
      {/* Sidebar */}
      <aside className="sidebar">
        <div className="sidebar-brand">
          <h1>SECCION9</h1>
          <p>VPN Manager</p>
        </div>
        <button className={`nav-item ${page === 'clients' ? 'active' : ''}`}
          onClick={() => setPage('clients')}>
          <span className="nav-icon">👥</span> Clientes
        </button>
        <button className={`nav-item ${page === 'server' ? 'active' : ''}`}
          onClick={() => setPage('server')}>
          <span className="nav-icon">🖥</span> Servidor
        </button>
        <div className="sidebar-footer">
          <button className="btn btn-ghost btn-sm" style={{ width: '100%' }}
            onClick={logout}>
            Cerrar sesión
          </button>
        </div>
      </aside>

      {/* Main */}
      <main className="main-content">
        {page === 'clients' && (
          <>
            <div className="page-header">
              <h2 className="page-title">Clientes VPN</h2>
              <p className="page-subtitle">
                Gestiona los accesos VPN de tu organización
              </p>
            </div>

            <div className="stats-grid">
              <div className="stat-card">
                <div className="stat-label">Total clientes</div>
                <div className="stat-value blue">{clients.length}</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Conectados</div>
                <div className="stat-value green">{online}</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Inactivos</div>
                <div className="stat-value yellow">{inactive}</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Sin conexión</div>
                <div className="stat-value" style={{ color: 'var(--red)' }}>
                  {clients.length - online - inactive}
                </div>
              </div>
            </div>

            <div className="table-card">
              <div className="table-header">
                <h3>Peers registrados</h3>
                <button className="btn btn-primary btn-sm"
                  onClick={() => setShowAddModal(true)}>
                  + Añadir cliente
                </button>
              </div>
              {loading ? (
                <div className="empty-state"><p>Cargando...</p></div>
              ) : clients.length === 0 ? (
                <div className="empty-state">
                  <p style={{ fontSize: '32px' }}>📡</p>
                  <p>No hay clientes registrados</p>
                </div>
              ) : (
                <table>
                  <thead>
                    <tr>
                      <th>Nombre</th>
                      <th>IP VPN</th>
                      <th>Clave pública</th>
                      <th>Estado</th>
                      <th>Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {clients.map((c) => (
                      <tr key={c.name}>
                        <td style={{ fontWeight: 600 }}>{c.name}</td>
                        <td className="ip-cell">{c.ip}</td>
                        <td className="key-cell" title={c.public_key}>
                          {c.public_key}
                        </td>
                        <td><StatusBadge status={c.status} /></td>
                        <td>
                          <div className="actions-cell">
                            <button className="icon-btn" title="Ver config"
                              onClick={() => handleShowConfig(c.name)}>
                              📄
                            </button>
                            <button className="icon-btn danger" title="Eliminar"
                              onClick={() => setShowDeleteModal(c.name)}>
                              🗑
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </>
        )}

        {page === 'server' && (
          <>
            <div className="page-header">
              <h2 className="page-title">Estado del servidor</h2>
              <p className="page-subtitle">Diagnóstico del servidor VPN</p>
            </div>
            {serverStatus && (
              <>
                <div className="stats-grid">
                  <div className="stat-card">
                    <div className="stat-label">IP pública</div>
                    <div className="stat-value blue" style={{ fontSize: 18 }}>
                      {serverStatus.server_ip}
                    </div>
                  </div>
                  <div className="stat-card">
                    <div className="stat-label">Puerto</div>
                    <div className="stat-value" style={{ fontSize: 18 }}>
                      {serverStatus.server_port}/udp
                    </div>
                  </div>
                  <div className="stat-card">
                    <div className="stat-label">Subred</div>
                    <div className="stat-value" style={{ fontSize: 18 }}>
                      {serverStatus.vpn_subnet}
                    </div>
                  </div>
                  <div className="stat-card">
                    <div className="stat-label">Uptime</div>
                    <div className="stat-value green" style={{ fontSize: 16 }}>
                      {serverStatus.uptime}
                    </div>
                  </div>
                </div>
                <div className="table-card" style={{ padding: 24 }}>
                  <h3 style={{ marginBottom: 4 }}>Checks del sistema</h3>
                  <div className="status-grid">
                    <div className="status-item">
                      <span className="status-item-label">Servicio WireGuard</span>
                      <span className={`status-item-value ${serverStatus.service === 'active' ? 'check-ok' : 'check-fail'}`}>
                        {serverStatus.service === 'active' ? '● Activo' : '● Inactivo'}
                      </span>
                    </div>
                    <div className="status-item">
                      <span className="status-item-label">IP Forwarding</span>
                      <span className={`status-item-value ${serverStatus.ip_forwarding ? 'check-ok' : 'check-fail'}`}>
                        {serverStatus.ip_forwarding ? '● Activo' : '● Inactivo'}
                      </span>
                    </div>
                    <div className="status-item">
                      <span className="status-item-label">UFW (51820/udp)</span>
                      <span className={`status-item-value ${serverStatus.ufw_wireguard ? 'check-ok' : 'check-fail'}`}>
                        {serverStatus.ufw_wireguard ? '● Permitido' : '● Bloqueado'}
                      </span>
                    </div>
                    <div className="status-item">
                      <span className="status-item-label">Clientes conectados</span>
                      <span className="status-item-value check-ok">
                        {serverStatus.online_clients} / {serverStatus.total_clients}
                      </span>
                    </div>
                  </div>
                </div>
              </>
            )}
          </>
        )}
      </main>

      {/* ── Modals ── */}

      {showAddModal && (
        <div className="modal-overlay" onClick={() => setShowAddModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Añadir cliente</h3>
            <div className="form-group">
              <label className="form-label">Nombre del cliente</label>
              <input className="form-input" placeholder="ej: oficina-bcn"
                value={newName} onChange={(e) => setNewName(e.target.value)}
                autoFocus onKeyDown={(e) => e.key === 'Enter' && handleAdd()} />
            </div>
            <p style={{ fontSize: 13, color: 'var(--text-muted)' }}>
              Se generarán claves automáticamente y se asignará la siguiente IP libre.
            </p>
            <div className="modal-actions">
              <button className="btn btn-ghost btn-sm"
                onClick={() => setShowAddModal(false)}>Cancelar</button>
              <button className="btn btn-primary btn-sm"
                onClick={handleAdd}>Añadir</button>
            </div>
          </div>
        </div>
      )}

      {showConfigModal && (
        <div className="modal-overlay" onClick={() => setShowConfigModal(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: 540 }}>
            <h3>Config — {showConfigModal.name}</h3>
            <div className="config-block">{showConfigModal.config}</div>
            {showConfigModal.qr && (
              <div className="qr-container">
                <img src={showConfigModal.qr} alt="QR Config" width={200} height={200} />
              </div>
            )}
            <div className="modal-actions">
              <button className="btn btn-ghost btn-sm"
                onClick={() => copyConfig(showConfigModal.config)}>
                Copiar
              </button>
              <button className="btn btn-success btn-sm"
                onClick={() => downloadConfig(showConfigModal.name, showConfigModal.config)}>
                Descargar .conf
              </button>
              <button className="btn btn-ghost btn-sm"
                onClick={() => setShowConfigModal(null)}>Cerrar</button>
            </div>
          </div>
        </div>
      )}

      {showDeleteModal && (
        <div className="modal-overlay" onClick={() => setShowDeleteModal(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Eliminar cliente</h3>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.6 }}>
              ¿Seguro que quieres eliminar a <strong>{showDeleteModal}</strong>?
              Se revocará su acceso VPN inmediatamente.
            </p>
            <div className="modal-actions">
              <button className="btn btn-ghost btn-sm"
                onClick={() => setShowDeleteModal(null)}>Cancelar</button>
              <button className="btn btn-danger btn-sm"
                onClick={() => handleDelete(showDeleteModal)}>
                Eliminar
              </button>
            </div>
          </div>
        </div>
      )}

      {toast && (
        <Toast message={toast.message} type={toast.type}
          onClose={() => setToast(null)} />
      )}
    </div>
  );
}

// ─── App Root ─────────────────────────────────────────────────

export default function App() {
  const [authed, setAuthed] = useState(!!localStorage.getItem('token'));

  return (
    <>
      <style>{styles}</style>
      {authed ? <Dashboard /> : <LoginScreen onLogin={() => setAuthed(true)} />}
    </>
  );
}
