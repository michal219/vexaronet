#!/bin/sh
# Sestaví Vexaronet z kódu a otevře ho v prohlížeči (macOS, Linux). Spuštění: sh spustit.sh
cd "$(dirname "$0")" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "Nenalezen Python 3. Nainstalujte ho z https://www.python.org/downloads/"; exit 1; }
python3 tools/spustit.py
