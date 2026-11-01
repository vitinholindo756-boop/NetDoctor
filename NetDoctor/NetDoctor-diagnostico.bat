@echo off
cd /d "%~dp0"
set NETDOCTOR_SHOWCONSOLE=1
echo Abrindo o NetDoctor com o console visivel (para ver erros)...
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0NetDoctor.ps1"
echo.
echo Se apareceu algum erro em vermelho acima, copie o texto e envie para quem te passou o programa.
if exist "%APPDATA%\NetDoctor\erro.log" echo Log de erros: %APPDATA%\NetDoctor\erro.log
pause
