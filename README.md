# Seccion9 — Secure Hub VPN

Solución de conectividad segura basada en **WireGuard** y **OpenVPN** para empresas. Acceso remoto Zero Trust con soporte para pfSense, OPNsense y firewalls corporativos (Cisco, Fortinet, SonicWall).

---

## Arquitectura

```
[Laptop 1] ──┐
[Laptop 2] ──┼── túnel WireGuard/OpenVPN ──► [VPS/VPN Gateway]
[Laptop 3] ──┘                                      │
                                          ┌──────────┴──────────┐
                                          │                     │
                                    [Firewall]               [WAF]
                                          │                     │
                                    [Servidor IT]         [Servidor Web]
```


![Diagrama de Arquitectura](./fotos/image.png)


| Componente | Descripción |
|---|---|
| VPS Gateway | Concentrador VPN central. WireGuard (UDP 51820) + OpenVPN (TCP 443) |
| Firewall cliente | pfSense / OPNsense / Cisco / Fortinet — varía por cliente |
| WAF | Nginx + ModSecurity + OWASP CRS |
| Servidor IT | Recursos internos del cliente |

---

## Protocolo según firewall del cliente

| Firewall del cliente | Protocolo recomendado |
|---|---|
| pfSense / OPNsense / Mikrotik | WireGuard |
| Cisco ASA / Fortinet / SonicWall | OpenVPN (TCP 443) |
| Sin firewall propio (cloud) | WireGuard |

---

## Inicio rápido

### 1. Instalar el servidor VPN
```bash
sudo bash server/install-server.sh
```

### 2. Desplegar el panel de gestión
```bash
cd panel/
# Editar docker-compose.yml con tus valores reales
nano docker-compose.yml
sudo bash deploy.sh
```
Panel accesible en `http://TU_IP:8443`

### 3. Añadir un cliente (tres opciones)

**Opción A — Desde el panel web (recomendado):**

Accede al panel → Añadir cliente → Descargar `.conf` → Enviar al cliente

**Opción B — Desde terminal:**
```bash
sudo bash onboarding/add-client.sh <nombre> <clave_publica> <ip_asignada>
```

**Opción C — Con el script interactivo:**
```bash
sudo ./wg-manager.sh
```

### 4. Configurar cliente Windows
```powershell
# Ejecutar como Administrador en PowerShell
.\clients\setup-windows.ps1 -ClientAddress "10.0.0.2"
```
O importar el `.conf` descargado del panel directamente en la GUI de WireGuard.

### 5. Configurar cliente Linux
```bash
sudo bash clients/setup-linux.sh
```
O copiar el `.conf` del panel a `/etc/wireguard/` y ejecutar `sudo wg-quick up seccion9`.

---

## Panel de gestión web

Dashboard web para gestionar la VPN sin necesidad de terminal. Backend en Python (FastAPI) + Frontend en React, desplegado con Docker.

### Funcionalidades

| Función | Descripción |
|---|---|
| **Añadir cliente** | Genera claves, asigna IP automáticamente, crea `.conf` y código QR |
| **Eliminar cliente** | Revoca acceso VPN inmediatamente |
| **Listar clientes** | Muestra peers con IP, estado en tiempo real (conectado / inactivo / sin conexión) |
| **Descargar config** | Descarga `.conf` o escanea QR desde el panel |
| **Estado del servidor** | Diagnóstico: servicio WireGuard, IP forwarding, UFW, peers conectados |

### Despliegue

```bash
cd panel/

# 1. Configurar variables en docker-compose.yml
#    - ADMIN_USER / ADMIN_PASSWORD → credenciales del panel
#    - SECRET_KEY → clave para JWT (cadena larga y aleatoria)
#    - SERVER_PUBLIC_IP → IP pública del VPS
#    - SERVER_PUBLIC_KEY → clave pública de WireGuard (sudo wg show wg0 public-key)
nano docker-compose.yml

# 2. Desplegar
sudo bash deploy.sh
```

### API REST

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/api/auth/login` | Login, devuelve token JWT |
| GET | `/api/clients` | Lista clientes con estado |
| POST | `/api/clients` | Añade cliente nuevo |
| DELETE | `/api/clients/{name}` | Elimina cliente |
| GET | `/api/clients/{name}/config` | Devuelve el `.conf` |
| GET | `/api/clients/{name}/qr` | QR para móvil (imagen PNG) |
| GET | `/api/server/status` | Estado del servidor |

Documentación interactiva en `http://TU_IP:8443/api/docs`

---

## Gestión por terminal con wg-manager.sh

El script `wg-manager.sh` ofrece las mismas funciones que el panel pero desde terminal. Útil para administración directa por SSH.

```bash
# Copiar al servidor y configurar
scp wg-manager.sh root@TU_IP_VPS:/root/wg-manager.sh
chmod +x /root/wg-manager.sh
nano /root/wg-manager.sh   # → Cambiar SERVER_IP y SERVER_PUBKEY
sudo ./wg-manager.sh
```

```
╔══════════════════════════════════════╗
║   SECCION9 — WireGuard Manager      ║
╠══════════════════════════════════════╣
║  1) Añadir cliente                   ║
║  2) Eliminar cliente                 ║
║  3) Listar clientes y estado         ║
║  4) Ver config de un cliente         ║
║  5) Estado del servidor              ║
║  6) Salir                            ║
╚══════════════════════════════════════╝
```

---

## Estructura del repositorio

```
├── README.md
├── wg-manager.sh                   # Gestión de clientes por terminal
├── server/
│   ├── install-server.sh           # Instala WireGuard en el VPS
│   └── wg0.conf.example            # Plantilla de configuración del servidor
├── clients/
│   ├── setup-windows.ps1           # Setup automático para Windows
│   ├── setup-linux.sh              # Setup automático para Linux
│   └── client.conf.example         # Plantilla de configuración del cliente
├── onboarding/
│   └── add-client.sh               # Registra nuevo peer (modo manual)
├── panel/                           # Panel web de gestión
│   ├── docker-compose.yml          # Orquestación de servicios
│   ├── deploy.sh                   # Script de despliegue
│   ├── backend/                    # API REST (FastAPI + Python)
│   │   ├── main.py                 # Endpoints de la API
│   │   ├── auth.py                 # Autenticación JWT
│   │   ├── config.py               # Variables de configuración
│   │   └── wireguard.py            # Lógica de gestión WireGuard
│   ├── frontend/                   # Dashboard (React)
│   │   └── src/App.js              # Aplicación principal
│   └── nginx/
│       └── nginx.conf              # Proxy reverso
├── docs/
│   └── troubleshooting.md          # Problemas conocidos y soluciones
└── fotos/
    └── image.png                   # Diagrama de arquitectura
```

---

## Comandos de mantenimiento

```bash
# Ver peers conectados y último handshake
sudo wg show

# Reiniciar túnel
sudo wg-quick down wg0 && sudo wg-quick up wg0

# Ver logs en tiempo real
sudo journalctl -u wg-quick@wg0 -f

# Eliminar cliente manualmente
sudo wg set wg0 peer <CLAVE_PUBLICA> remove
sudo wg-quick save wg0

# Ver logs del panel
sudo docker logs seccion9-api --tail 50
sudo docker logs seccion9-web --tail 50

# Reiniciar panel
cd panel/ && sudo docker compose restart
```

---

## ⚠️ Nota sobre proveedores cloud (Ionos, OVH, Hetzner...)

Muchos proveedores tienen un **firewall externo independiente del UFW** que bloquea el tráfico antes de llegar al sistema operativo. Hay que abrir los siguientes puertos desde el **panel web del proveedor**:

| Protocolo | Puerto | Uso |
|---|---|---|
| UDP | 51820 | WireGuard VPN |
| TCP | 8443 | Panel de gestión web |

Ver [`docs/troubleshooting.md`](docs/troubleshooting.md) para el checklist completo.

---

> **Seccion9** — Conectividad segura para empresas.
> info@seccion9.com | 123 456 789
