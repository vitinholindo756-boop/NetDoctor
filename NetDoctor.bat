@echo off
cd /d "%~dp0"
rem Abre o NetDoctor. O console do PowerShell e escondido pelo proprio programa; so a janela dele fica na barra de tarefas.
rem conhost.exe garante o console classico (no Windows 11 o Terminal ignoraria o ocultar). Se nao abrir, use NetDoctor-diagnostico.bat
start "" /min conhost.exe powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0NetDoctor.ps1"
