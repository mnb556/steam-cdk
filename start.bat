@echo off
cd /d "%~dp0server"
echo === 阿火游戏入库系统 ===
echo.
echo [*] Starting server...
start http://127.0.0.1:5000?token=changeme
pip install flask -q 2>nul
python app.py
pause
