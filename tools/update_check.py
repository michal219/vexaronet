#!/usr/bin/env python3
"""Pomůcka pro kupce po aktualizaci kódu: vypíše databázové migrace, které jste ještě nespustili.
Použití: python3 tools/update_check.py          (vypíše nové migrace a změny)
         python3 tools/update_check.py --done   (po spuštění migrací je označí jako provedené)"""
import os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
mig = os.path.join(root, 'db', 'migrations')
mark = os.path.join(root, '.migrace_provedene')
done = set(open(mark, encoding='utf-8').read().split()) if os.path.exists(mark) else set()
allm = sorted(f for f in os.listdir(mig) if f.endswith('.sql') and not f.endswith('_rollback.sql')) if os.path.isdir(mig) else []
new = [f for f in allm if f not in done]
if '--done' in sys.argv:
    open(mark, 'w', encoding='utf-8').write('\n'.join(allm) + '\n'); print('Označeno jako provedené:', len(allm)); sys.exit(0)
print('Verze:', open(os.path.join(root, 'VERSION'), encoding='utf-8').read().strip())
if not new: print('Žádné nové migrace.')
else:
    print('Spusťte v Supabase SQL editoru v tomto pořadí (zálohu databáze si udělejte předem):')
    for f in new: print('  db/migrations/' + f)
    print('Potom: python3 tools/update_check.py --done')
print('Co je nového: CHANGELOG.md')
