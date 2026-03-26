# ============================================================
#  SECCION9 — WireGuard Client Setup for Windows
#  Ejecutar como Administrador en PowerShell
#  Uso: .\setup-windows.ps1 -ClientAddress "10.0.0.2"
#
#  ANTES DE DISTRIBUIR: reemplaza ServerPublicKey y ServerEndpoint
#  con los valores reales de tu servidor.
# ============================================================

param(
    [string]$ServerPublicKey = "TU_CLAVE_PUBLICA_SERVIDOR",
    [string]$ServerEndpoint  = "TU_IP_VPS:51820",
    [string]$ClientAddress   = "",
    [string]$TunnelName      = "tunnel-seccion9"
)

$WG_DIR = "C:\Program Files\WireGuard"
$WG_EXE = "$WG_DIR\wg.exe"
$CONF   = "$WG_DIR\$TunnelName.conf"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   SECCION9 - VPN WireGuard Setup Windows  " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Instalar WireGuard si no existe ---
if (-not (Test-Path $WG_EXE)) {
    Write-Host "[!] WireGuard no encontrado. Instalando..." -ForegroundColor Yellow
    $installer = "$env:TEMP\wireguard.msi"
    Invoke-WebRequest -Uri "https://download.wireguard.com/windows-client/wireguard-amd64-0.5.3.msi" -OutFile $installer
    Start-Process msiexec -ArgumentList "/i $installer /quiet" -Wait
    Start-Sleep -Seconds 10
    Write-Host "[+] WireGuard instalado." -ForegroundColor Green
} else {
    Write-Host "[+] WireGuard encontrado." -ForegroundColor Green
}

# --- 2. Pedir IP si no se paso como parametro ---
if ($ClientAddress -eq "") {
    Write-Host ""
    Write-Host "Pregunta a tu administrador de SECCION9 que IP te han asignado."
    $ClientAddress = Read-Host "Introduce tu IP VPN asignada (ej: 10.0.0.2)"
}

# --- 3. Generar claves ---
Write-Host ""
Write-Host "[*] Generando par de claves..." -ForegroundColor Yellow
$privateKey = & "$WG_EXE" genkey
$publicKey  = $privateKey | & "$WG_EXE" pubkey

Write-Host "[+] Clave privada generada (no compartir nunca)." -ForegroundColor Green
Write-Host ""
Write-Host "======================================================" -ForegroundColor Yellow
Write-Host " IMPORTANTE: Envia esta clave publica a SECCION9:" -ForegroundColor Yellow
Write-Host " $publicKey" -ForegroundColor White
Write-Host "======================================================" -ForegroundColor Yellow
Write-Host ""

# --- 4. Crear archivo de configuracion ---
$conf = @"
[Interface]
PrivateKey = $privateKey
Address = $ClientAddress/24
DNS = 8.8.8.8

[Peer]
PublicKey = $ServerPublicKey
Endpoint = $ServerEndpoint
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"@

$conf | Out-File -Encoding ASCII $CONF
Write-Host "[+] Configuracion guardada en: $CONF" -ForegroundColor Green

# --- 5. Abrir GUI de WireGuard ---
Write-Host ""
Start-Process "$WG_DIR\wireguard.exe"

Write-Host "[*] Pasos siguientes:" -ForegroundColor Cyan
Write-Host "    1. Envia tu clave publica a SECCION9 (mostrada arriba)"
Write-Host "    2. Espera confirmacion de que esta registrada en el servidor"
Write-Host "    3. En la GUI de WireGuard: Importar tunel > $CONF > Activar"
Write-Host ""
Write-Host "Listo. El archivo de configuracion esta en: $CONF" -ForegroundColor Green
