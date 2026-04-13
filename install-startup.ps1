#Requires -RunAsAdministrator
# install-startup.ps1
# Registra LibreTranslate y AutoHotkey como tareas del Task Scheduler.
# Solo necesitás correr esto UNA VEZ. Desde el próximo login arrancan solos.
#
# Para desinstalar: .\install-startup.ps1 -Uninstall

param([switch]$Uninstall)

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskFolder  = "myTraductor"

if ($Uninstall) {
    Write-Host "Eliminando tareas de myTraductor..."
    Unregister-ScheduledTask -TaskName "$taskFolder\LibreTranslate" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "$taskFolder\AHK"            -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Listo. Tareas eliminadas."
    exit 0
}

# ── Rutas ────────────────────────────────────────────────────────
$vbsPath = "$scriptDir\run-libretranslate.vbs"

# Detectar AutoHotkey v1
$ahkCandidates = @(
    "C:\Program Files\AutoHotkey\AutoHotkey.exe",
    "C:\Program Files (x86)\AutoHotkey\AutoHotkey.exe",
    "C:\Program Files\AutoHotkey\v1\AutoHotkey.exe"
)
$ahkExe = $ahkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahkExe) {
    Write-Error "No se encontró AutoHotkey.exe. Instala AHK v1 desde https://www.autohotkey.com/download/1.1/"
    exit 1
}
$ahkScript = "$scriptDir\myTraductor.ahk"

Write-Host ""
Write-Host "Registrando tareas de inicio automatico para myTraductor..."
Write-Host "  LibreTranslate VBS : $vbsPath"
Write-Host "  AutoHotkey         : $ahkExe"
Write-Host "  AHK Script         : $ahkScript"
Write-Host ""

# ── Tarea 1: LibreTranslate (via VBS para que corra oculto) ──────
$ltAction   = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""
$ltTrigger  = New-ScheduledTaskTrigger -AtLogOn
$ltSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 0 `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName  "$taskFolder\LibreTranslate" `
    -Action    $ltAction `
    -Trigger   $ltTrigger `
    -Settings  $ltSettings `
    -RunLevel  Highest `
    -Force | Out-Null

Write-Host "[OK] Tarea LibreTranslate registrada (al iniciar sesion, oculto)"

# ── Tarea 2: AutoHotkey con 3 min de delay (espera que LT levante) ──
$ahkAction  = New-ScheduledTaskAction -Execute $ahkExe -Argument "`"$ahkScript`""
$ahkTrigger = New-ScheduledTaskTrigger -AtLogOn
$ahkTrigger.Delay = "PT3M"   # ISO 8601: 3 minutos

$ahkSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 0 `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName  "$taskFolder\AHK" `
    -Action    $ahkAction `
    -Trigger   $ahkTrigger `
    -Settings  $ahkSettings `
    -RunLevel  Highest `
    -Force | Out-Null

Write-Host "[OK] Tarea AutoHotkey registrada (3 minutos despues de iniciar sesion)"
Write-Host ""
Write-Host "============================================"
Write-Host " Todo listo. Desde el proximo login:"
Write-Host "   - LibreTranslate arranca solo (oculto)"
Write-Host "   - AutoHotkey arranca 3 min despues"
Write-Host "   - F12 funciona en cualquier ventana"
Write-Host ""
Write-Host " Para desinstalar: .\install-startup.ps1 -Uninstall"
Write-Host "============================================"
Write-Host ""

# Ofrecer arrancar ahora mismo sin reiniciar sesion
$resp = Read-Host "Iniciar ambos servicios AHORA sin reiniciar sesion? (s/n)"
if ($resp -match "^[sS]") {
    Write-Host "Iniciando LibreTranslate..."
    Start-ScheduledTask -TaskName "$taskFolder\LibreTranslate"
    Write-Host "LibreTranslate corriendo en background. AutoHotkey arrancara en 3 minutos."
    Write-Host "(O ejecuta myTraductor.ahk manualmente con doble clic si no queres esperar)"
}
