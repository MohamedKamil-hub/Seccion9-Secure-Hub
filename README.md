# Cloud-Hub VPN — MVP en Containerlab

**SECCIÓN 9** — Laboratorio de demostración del producto *"Pack de Conectividad Blindada"*

---

## ¿Qué es esto?

Un laboratorio completo que simula la arquitectura Cloud-Hub VPN de SECCIÓN 9 en tu portátil. Incluye:

- **Hub VPN central** (simula OPNsense en VPS con WireGuard)
- **3 Spokes** (empleado remoto, PC de oficina, servidor interno)
- **Dashboard web** de monitorización en tiempo real
- **Tests automatizados** de las 3 funcionalidades clave: VPN, segmentación y revocación

## Requisitos

- Linux (Ubuntu 22.04 o 24.04 recomendado)
- Docker
- Containerlab (`bash -c "$(curl -sL https://get.containerlab.dev)"`)
- WireGuard tools (`sudo apt install wireguard-tools`)
- 8 GB RAM mínimo

## Despliegue rápido

```bash
# 1. Clonar/copiar el proyecto
cd ~/clab-cloudhub

# 2. Ejecutar el setup (genera claves, construye imágenes, despliega)
./setup.sh

# 3. Ejecutar los tests
./scripts/test.sh

# 4. Abrir el dashboard
# → http://localhost:3000
```

## Estructura del proyecto

```
clab-cloudhub/
├── setup.sh                 # Script maestro (todo en un comando)
├── topology.yml             # Definición de la topología Containerlab
├── README.md
├── docker/
│   ├── hub/                 # Gateway VPN central
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── firewall.sh
│   │   └── api.py           # Mini API de estado (JSON)
│   ├── spoke/               # Dispositivos del cliente
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   └── dashboard/           # Panel web de monitorización
│       ├── Dockerfile
│       ├── entrypoint.sh
│       └── dashboard.html
├── config/                  # Generado automáticamente por setup.sh
│   ├── *_private.key
│   ├── *_public.key
│   └── *_wg0.conf
└── scripts/
    ├── test.sh              # Tests automatizados (VPN + segmentación + revocación)
    └── destroy.sh           # Destruir el laboratorio
```

## Qué demuestra cada test

| Test | Qué prueba | Equivalente en producción |
|------|-----------|--------------------------|
| **Túneles VPN** | Todos los spokes se conectan al Hub y se ven entre sí | Empleados conectados a la red corporativa |
| **Servicio HTTP** | El servidor interno solo es accesible por la VPN | Recursos corporativos protegidos |
| **Segmentación** | Un spoke pierde acceso al servidor mientras otro lo mantiene | Reglas de firewall en OPNsense |
| **Revocación** | Un spoke pierde todo acceso VPN al instante | Empleado que pierde el dispositivo |

## Dashboard

Accede a `http://localhost:3000` para ver el panel de monitorización en tiempo real. Muestra:

- Estado de cada peer (conectado/desconectado)
- Tráfico por túnel
- Controles de demo para segmentación y revocación

## Comandos útiles

```bash
# Ver estado de WireGuard en el Hub
docker exec clab-cloudhub-vpn-hub wg show

# Entrar en un contenedor
docker exec -it clab-cloudhub-vpn-spoke-01 bash

# Ver logs del Hub
docker logs clab-cloudhub-vpn-hub

# Capturar tráfico en el Hub
docker exec clab-cloudhub-vpn-hub tcpdump -i wg0 -n

# Destruir el lab
./scripts/destroy.sh
```

## Mapeo Lab → Producción

| Lab | Producción |
|-----|-----------|
| Contenedor `hub` | VPS Hetzner CX22 con OPNsense |
| Red `172.20.20.0/24` | Internet público |
| Contenedores `spoke-*` | PCs reales con app WireGuard |
| `iptables` manuales | GUI de OPNsense |
| Dashboard HTML | Panel de OPNsense + monitorización |

---

*SECCIÓN 9 — Ciberseguridad para PYMES*
