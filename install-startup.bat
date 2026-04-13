@echo off
:: install-startup.bat
:: Ejecuta install-startup.ps1 con privilegios de Administrador.
:: Corre esto UNA SOLA VEZ. Desde el proximo login todo arranca solo.

echo.
echo  =============================================
echo   myTraductor - Instalacion de inicio automatico
echo  =============================================
echo.
echo  Se necesita permisos de Administrador.
echo  Windows te pedira confirmacion (cuadro azul UAC).
echo.
pause

powershell -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ""%~dp0install-startup.ps1""' -Verb RunAs -Wait"

echo.
echo  Instalacion completada.
pause
