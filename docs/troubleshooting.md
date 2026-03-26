# Troubleshooting — Problemas conocidos y soluciones

Lecciones aprendidas durante el despliegue real de SECCION9 VPN.

---

## Checklist rápido antes de empezar a depurar

```
[ ] ¿Llegan paquetes UDP al servidor? → sudo tcpdump -i ens6 udp port 51820
[ ] ¿Firewall externo del proveedor abierto? (Ionos, OVH, Hetzner...)
[ ] ¿UFW tiene 51820/udp abierto? → sudo ufw status
[ ] ¿La clave pública del cliente está registrada? → sudo wg show
[ ] ¿La clave pública del servidor en el cliente es correcta? (case-sensitive)
[ ] ¿IP forwarding activo? → cat /proc/sys/net/ipv4/ip_forward
[ ] ¿PostUp/PostDown usa la interfaz de red correcta? (ens6, eth0, enp3s0...)
```

---

## 1. Handshake no completa

**Síntoma:**
```
Handshake for peer did not complete after 5 seconds, retrying (try 2)
```

### Paso 1 — Verificar que los paquetes llegan al servidor
```bash
sudo tcpdump -i ens6 udp port 51820 -v
```
- Si **no aparece nada** mientras el cliente intenta conectar → problema de red o firewall externo.
- Si **aparecen paquetes pero no hay respuesta** → problema de claves o configuración WireGuard.

---

### Paso 2 — Firewall externo del proveedor ⚠️ (causa más común)

Proveedores como **Ionos, OVH, Hetzner o AWS** tienen un firewall a nivel de red **por encima del UFW** del sistema operativo. Los paquetes UDP llegan a su red pero son bloqueados antes de llegar al VPS.

**Síntoma en tracert/traceroute:**
```
9    15 ms    212.227.x.x
10     *        *        *     Tiempo de espera agotado   ← muere aquí
```

**Solución en Ionos:**
1. Panel Ionos → **Red → Políticas de firewall**
2. Editar la política **asignada al servidor** (no crear una nueva)
3. Añadir regla: Protocolo **UDP** / Puerto **51820** / Origen **0.0.0.0/0** / Acción **Allow** / Dirección **Inbound**
4. Guardar y esperar ~30 segundos

> ⚠️ Si creas una política nueva pero no la asignas al servidor, no tiene efecto.

---

### Paso 3 — UFW del sistema operativo
```bash
sudo ufw status verbose
```
Debe aparecer `51820/udp ALLOW IN Anywhere`. Si no:
```bash
sudo ufw allow 51820/udp
sudo ufw reload
```

---

### Paso 4 — Verificar claves (WireGuard es case-sensitive)

WireGuard descarta paquetes silenciosamente si la clave pública del servidor es incorrecta — sin ningún mensaje de error.

```bash
# En el servidor: verificar que la privada del cliente genera la pública registrada
echo "CLAVE_PRIVADA_DEL_CLIENTE" | wg pubkey
# Debe coincidir exactamente con la que aparece en: sudo wg show
```

**Caso real documentado:** una `l` minúscula escrita como `L` mayúscula hace que el handshake falle silenciosamente:
```
# MAL  → VNLKAg0=
# BIEN → VNlKAg0=
```

---

### Paso 5 — Recargar WireGuard en el servidor
```bash
sudo wg-quick down wg0 && sudo wg-quick up wg0
sudo wg show
```

---

## 2. wg-quick.exe no existe en Windows

`wg-quick` no existe en Windows. Opciones:
```cmd
# Opción A — instalar como servicio
wireguard.exe /installtunnelservice "C:\Program Files\WireGuard\tunnel.conf"

# Opción B — usar la GUI
wireguard.exe
# → Importar túnel → seleccionar el .conf → Activar
```

---

## 3. SSH — REMOTE HOST IDENTIFICATION HAS CHANGED

Aparece al reconectar tras reinstalar la VM del servidor:
```cmd
ssh-keygen -R IP_DEL_SERVIDOR
```
Luego reconectar con `ssh usuario@IP` y aceptar la nueva huella.

---

## 4. El cliente conecta pero no tiene internet

IP forwarding no está activo en el servidor:
```bash
cat /proc/sys/net/ipv4/ip_forward
# Si devuelve 0:
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
```

---

## 5. WireGuard activo pero systemd muestra inactive (dead)

El túnel está levantado manualmente pero no arrancará tras un reinicio:
```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

---

## 6. Detectar la interfaz de red correcta del servidor

El `PostUp`/`PostDown` en `wg0.conf` debe usar la interfaz real del servidor, no siempre es `ens6`:
```bash
ip route | grep default
# Ejemplo: default via 212.x.x.1 dev ens6  ← ens6 es la interfaz
```

Si la interfaz es `eth0` o `enp3s0`, actualiza el `wg0.conf` en consecuencia.
