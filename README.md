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

### 2. Añadir un cliente nuevo
```bash
sudo bash onboarding/add-client.sh <nombre> <clave_publica> <ip_asignada>
# Ejemplo:
sudo bash onboarding/add-client.sh moham CMvCw4g...= 10.0.0.2
```

### 3. Configurar cliente Windows
```powershell
# Ejecutar como Administrador en PowerShell
.\clients\setup-windows.ps1 -ClientAddress "10.0.0.2"
```

### 4. Configurar cliente Linux
```bash
sudo bash clients/setup-linux.sh
```

---

## Gestión de clientes con wg-manager.sh

El script `wg-manager.sh` centraliza toda la gestión de clientes VPN desde el servidor. Genera claves, asigna IPs automáticamente y crea los archivos `.conf` listos para enviar al cliente.

### Instalación

```bash
# Copiar al servidor
scp wg-manager.sh root@TU_IP_VPS:/root/wg-manager.sh

# En el servidor: editar las variables de configuración
nano /root/wg-manager.sh
# → Cambiar SERVER_IP y SERVER_PUBKEY por los valores reales

# Dar permisos y ejecutar
chmod +x /root/wg-manager.sh
sudo ./wg-manager.sh
```

### Menú principal

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

### Funcionalidades

| Opción | Descripción |
|---|---|
| **1) Añadir cliente** | Genera claves automáticamente, asigna la siguiente IP libre, crea el `.conf` completo listo para enviar |
| **2) Eliminar cliente** | Revoca el acceso VPN, elimina el peer y borra su `.conf` |
| **3) Listar clientes** | Muestra todos los peers con IP y estado (conectado / inactivo / sin conexión) |
| **4) Ver config** | Muestra el `.conf` de un cliente para reenviárselo |
| **5) Estado del servidor** | Diagnóstico rápido: servicio, IP forwarding, UFW, peers, `wg show` |

Los archivos `.conf` de cada cliente se guardan en `/etc/wireguard/clientes/`.
Las acciones quedan registradas en `/var/log/seccion9-vpn.log`.

### Ejemplo de uso: añadir un cliente

```bash
sudo ./wg-manager.sh
# → Opción 1
# → Nombre: oficina-bcn
# → El script genera todo automáticamente y muestra el .conf
```

Salida:

```
[*] Registrando cliente: oficina-bcn
    IP asignada:    10.0.0.2
    Clave pública:  abc123...=

[+] Cliente 'oficina-bcn' registrado correctamente.

  ARCHIVO .conf PARA ENVIAR AL CLIENTE
  [Interface]
  PrivateKey = xyz789...
  Address = 10.0.0.2/24
  DNS = 8.8.8.8

  [Peer]
  PublicKey = TU_CLAVE_PUBLICA_SERVIDOR
  AllowedIPs = 0.0.0.0/0
  Endpoint = TU_IP_VPS:51820
  PersistentKeepalive = 25
```

> **Nota:** El método manual con `add-client.sh` sigue disponible para casos donde el cliente genera sus propias claves.

---

## Estructura del repositorio

```
├── wg-manager.sh               # Gestión centralizada de clientes VPN
├── server/
│   └── install-server.sh       # Instala WireGuard en el VPS desde cero
├── clients/
│   ├── setup-windows.ps1       # Setup automático para Windows
│   └── setup-linux.sh          # Setup automático para Linux
├── onboarding/
│   └── add-client.sh           # Registra nuevo peer en el servidor
└── docs/
    └── troubleshooting.md      # Problemas conocidos y soluciones
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

# Eliminar cliente
sudo wg set wg0 peer <CLAVE_PUBLICA> remove
sudo wg-quick save wg0
```

---

## ⚠️ Nota sobre proveedores cloud (Ionos, OVH, Hetzner...)

Muchos proveedores tienen un **firewall externo independiente del UFW** que bloquea el tráfico antes de llegar al sistema operativo. Hay que abrir el puerto UDP 51820 desde el **panel web del proveedor**, no solo desde UFW.

Ver [`docs/troubleshooting.md`](docs/troubleshooting.md) para el checklist completo.

---

> **Seccion9** — Conectividad segura para empresas.
> info@seccion9.com | 123 456 789
