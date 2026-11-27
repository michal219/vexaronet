@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Sestavuji Vexaronet z kodu...
where py >nul 2>nul && (py -3 tools\spustit.py & goto konec)
where python >nul 2>nul && (python tools\spustit.py & goto konec)
echo Nenalezen Python 3. Nainstalujte ho z https://www.python.org/downloads/ (zaskrtnete "Add python.exe to PATH") a spustte tento soubor znovu.
:konec
pause
