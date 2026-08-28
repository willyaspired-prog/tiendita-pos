@echo off
REM Empaqueta main.py en un solo .exe (Windows) con PyInstaller
REM Ejecutar en CMD. Recomendado crear y usar un virtualenv.

REM 1) Crear y activar virtualenv (opcional)
REM python -m venv venv
REM venv\Scripts\activate

REM 2) Instalar PyInstaller
pip install pyinstaller

REM 3) Generar EXE (ventana sin consola)
pyinstaller --onefile --windowed --name TienditaPOS main.py

echo Terminado. El ejecutable estará en dist\TienditaPOS.exe
pause
