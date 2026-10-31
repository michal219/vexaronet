// Obal kolem webové aplikace vexaronet.com pro Windows (a další systémy).
const { app, BrowserWindow, shell, Menu } = require('electron');
const START = 'https://vexaronet.com/?app=1';
function ok(u) { try { const h = new URL(u).hostname; return h === 'vexaronet.com' || h.endsWith('.vexaronet.com') || h.endsWith('.supabase.co'); } catch (e) { return false; } }
function create() {
  Menu.setApplicationMenu(null);
  const w = new BrowserWindow({ width: 1280, height: 840, minWidth: 380, minHeight: 600, backgroundColor: '#03040a', title: 'Vexaronet', icon: __dirname + '/icon.png' });
  w.webContents.setWindowOpenHandler(({ url }) => { if (ok(url)) return { action: 'allow' }; shell.openExternal(url); return { action: 'deny' }; });
  w.webContents.on('will-navigate', (e, url) => { if (!ok(url)) { e.preventDefault(); shell.openExternal(url); } });
  w.loadURL(START);
}
if (!app.requestSingleInstanceLock()) app.quit();
app.whenReady().then(create);
app.on('window-all-closed', () => app.quit());
