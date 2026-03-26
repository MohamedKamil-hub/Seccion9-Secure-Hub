# Seccion9 VPN 

¡Bienvenido al repositorio de **Seccion9  VPN **! Este proyecto implementa una solución de conectividad segura y flexible, diseñada para proteger el acceso a servicios internos y aplicaciones web, con un enfoque especial en la adaptabilidad para empresas en España que manejan diversas infraestructuras de cliente.

##  Visión General del Proyecto

 actúa como un **punto de entrada seguro y orquestado**, garantizando que el tráfico de los usuarios sea inspeccionado y protegido antes de llegar a los recursos internos. Proporciona una solución robusta para el teletrabajo, el acceso a recursos críticos y la protección de aplicaciones web contra amenazas comunes.

Hemos diseñado este sistema para ser versátil, combinando la alta eficiencia de **WireGuard** con la amplia compatibilidad de **OpenVPN**, permitiendo a nuestros clientes elegir el protocolo que mejor se adapte a su infraestructura existente (ya sea un OPNsense moderno o un firewall corporativo más tradicional).

##  Arquitectura del Sistema

El siguiente diagrama ilustra la arquitectura de la solución, destacando el flujo de tráfico desde los usuarios finales hasta las aplicaciones protegidas, pasando por nuestro **VPN/VPS central** y un **WAF** dedicado.

![Diagrama de Arquitectura](./fotos/image.png)

### Componentes Clave:

* **Clientes (Laptops):** Usuarios finales que se conectan de forma segura a la red.
* **VPN / VPS Central (Seccion9 Gateway):** El corazón de nuestra solución. Aquí se aloja el servidor VPN que gestiona las conexiones entrantes de **WireGuard** y **OpenVPN**. Actúa como punto de entrada único para todo el tráfico protegido.
* **Firewall de Red:** Protege los servidores internos de ataques a nivel de red (capas 3 y 4).
* **Servidor IT:** Representa cualquier servidor o recurso interno de la empresa que requiera acceso seguro.
* **WAF (Web Application Firewall):** Un componente crucial que inspecciona, filtra y bloquea el tráfico HTTP/S malicioso (ej. inyección SQL, XSS) *antes* de que llegue a la aplicación web, protegiendo contra ataques a la capa de aplicación.
* **Aplicación Web:** La aplicación o servicio web que se desea proteger y hacer accesible de forma segura.

## Características Principales

* **Soporte Híbrido de VPN:** Integración de **WireGuard** para conexiones de alta velocidad y baja latencia, y **OpenVPN** para máxima compatibilidad con una amplia gama de dispositivos y firewalls (incluyendo OPNsense, pfSense y soluciones empresariales).
* **Seguridad por Capas:** Protección robusta con un firewall de red tradicional y un WAF específico para aplicaciones web.
* **Flexibilidad para Empresas Españolas:** Adaptado a las diversas infraestructuras IT de las PYMES y grandes empresas en España, garantizando que el acceso seguro sea posible sin importar la complejidad del entorno del cliente.
* **Optimización de Recursos:** Diseño pensado para maximizar el rendimiento en el VPS central, incluso con WAF activos, gracias a la eficiencia de WireGuard.
* **Facilidad de Gestión:** Una configuración centralizada que permite administrar las políticas de acceso y seguridad desde un único punto.

##  Tecnologías Utilizadas (Ejemplos)

* **VPN:** WireGuard, OpenVPN
* **Sistema Operativo del VPS:** Debian, Ubuntu Server
* **Firewall de Servidor:** `iptables`, `nftables`, UFW
* **WAF:** Nginx (como proxy inverso) + ModSecurity, OWASP Core Rule Set (CRS)
* **Gestión de Certificados (OpenVPN):** Easy-RSA
* **Orquestación/Contenedores (Opcional):** Docker, Docker Compose

## Primeros Pasos (Próximamente)

Se añadirán guías detalladas sobre cómo desplegar cada componente, configurar los clientes (Laptops y Firewalls), y mantener la solución.

## Contribuciones

Este proyecto es de Seccion9. Si tienes alguna pregunta o sugerencia, por favor abre un 'issue'.

---

**Seccion9 - Conectividad Segura y Avanzada.**

# SECCION9 — VPN WireGuard Server

Documentación de la infraestructura VPN basada en WireGuard desplegada en VPS Ionos para el proyecto SECCION9.

---

## Arquitectura

```
[Cliente Windows/Linux]
        |
        | túnel WireGuard (UDP 51820)
        |
[VPS Ionos - Ubuntu 22.04]
  IP pública: X.X.X.109
  IP VPN:     10.0.0.1/24
        |
        | iptables MASQUERADE
        |
  [Internet / Red interna]
```

### Peers registrados

| Peer | IP VPN | Clave pública |
|------|--------|---------------|
| Cliente 1 (moham) | 10.0.0.2/32 | `PxA=` |
| Cliente 2 | 10.0.0.3/32 | `` |

---

## Servidor

| Parámetro | Valor |
|-----------|-------|
| SO | Ubuntu 22.04.5 LTS (jammy) |
| Kernel | 5.15.0-173-generic |
| IP pública | X.X.X.109 |
| Proveedor | Ionos (pbiaas) |
| Interfaz red | ens6 |
| Puerto WireGuard | UDP 51820 |

---

## Configuración del servidor `/etc/wireguard/wg0.conf`

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <OCULTA — ver gestor de contraseñas>

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; \
         iptables -A FORWARD -o wg0 -j ACCEPT; \
         iptables -t nat -A POSTROUTING -o ens6 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -D FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o ens6 -j MASQUERADE

# Cliente 1
[Peer]
PublicKey = <CLAVE_PRIVADA>
AllowedIPs = 10.0.0.2/32

# Cliente 2
[Peer]
PublicKey = <CLAVE_PUBLICA>
AllowedIPs = 10.0.0.3/32
```

---

## Configuración del cliente (Windows/Linux)

```ini
[Interface]
PrivateKey = <CLAVE_PRIVADA_DEL_CLIENTE>
Address = 10.0.0.X/24
DNS = 8.8.8.8

[Peer]
PublicKey = <CLAVE_PUBLICA>
Endpoint = 212.227.104.109:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

> Sustituir `10.0.0.X` por la IP asignada al cliente (ver tabla de peers).

### Generar par de claves (Linux)
```bash
wg genkey | tee privatekey | wg pubkey > publickey
cat privatekey
cat publickey
```

### Generar par de claves (Windows PowerShell)
```powershell
cd "C:\Program Files\WireGuard"
wg.exe genkey > private.key
wg.exe pubkey < private.key > public.key
Get-Content private.key
Get-Content public.key
```

---

## Firewall UFW

```
Default: deny (incoming), allow (outgoing), deny (routed)

22/tcp     ALLOW IN   (SSH)
80/tcp     ALLOW IN   (HTTP)
443/tcp    ALLOW IN   (HTTPS)
8001:8050  ALLOW IN   (servicios internos)
51820/udp  ALLOW IN   (WireGuard)
```

### ⚠️ Firewall externo Ionos
Ionos tiene un firewall a nivel de red **por encima del UFW** que hay que configurar desde el panel web.
Reglas necesarias en el panel Ionos:

| Protocolo | Puerto | Origen | Acción |
|-----------|--------|--------|--------|
| UDP | 51820 | 0.0.0.0/0 | Allow |
| TCP | 22 | 0.0.0.0/0 | Allow |
| ICMP | — | 0.0.0.0/0 | Allow |

---

## Comandos de mantenimiento

### Ver estado del túnel
```bash
sudo wg show
```

### Añadir nuevo cliente
```bash
# En el servidor
sudo wg set wg0 peer <CLAVE_PUBLICA_CLIENTE> allowed-ips 10.0.0.X/32
sudo wg-quick save wg0
```

### Eliminar cliente
```bash
sudo wg set wg0 peer <CLAVE_PUBLICA_CLIENTE> remove
sudo wg-quick save wg0
```

### Reiniciar WireGuard
```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
```

### Activar inicio automático
```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

### Ver logs del servicio
```bash
sudo journalctl -u wg-quick@wg0 -f
```

---

## Troubleshooting

### Handshake no completa
1. Verificar que el puerto 51820/udp está abierto en UFW: `sudo ufw status`
2. **Verificar firewall externo de Ionos** (causa más común) — abrir UDP 51820 desde el panel web
3. Verificar que el cliente usa la clave privada correcta
4. Capturar tráfico entrante: `sudo tcpdump -i ens6 udp port 51820`
5. Verificar que la clave pública del cliente está registrada: `sudo wg show`

### Verificar que las claves del cliente son correctas
```bash
# En el servidor, verificar que la privada genera la pública esperada
echo "<CLAVE_PRIVADA>" | wg pubkey
```

### El cliente no tiene internet a través del túnel
```bash
# Verificar que IP forwarding está activo
cat /proc/sys/net/ipv4/ip_forward
# Si devuelve 0, activarlo:
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
```

---

## Red interna

| Interfaz | IP | Descripción |
|----------|----|-------------|
| ens6 | 212.227.104.109/32 | IP pública Ionos |
| wg0 | 10.0.0.1/24 | Túnel WireGuard |
| docker0 | 172.17.0.1/16 | Red Docker (inactiva) |

---

*Documento generado para uso interno de SECCION9 — no compartir claves privadas en repositorios públicos.*
