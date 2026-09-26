// Renderiza las maquetas a 1920x1080 con Playwright Chromium (preinstalado).
// Uso (desde la raíz del repo, con un servidor estático en :18731 sirviendo la raíz):
//   python3 -m http.server 18731 --bind 127.0.0.1 &
//   taskset -c 2,3 node docs/research/10_hud_ux/mockups/render.cjs [nombre...]
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const path = require('path');
const PORT = process.env.PORT || 18731;
const BASE = 'http://127.0.0.1:' + PORT + '/docs/research/10_hud_ux/mockups/';
const OUT = path.resolve(__dirname, '..');
const PAGES = [
  ['a_hud_dia', 'a_hud_dia.html'],
  ['b_hud_noche_ventisca', 'b_hud_noche_ventisca.html'],
  ['c1_titulo_region_f1', 'c_titulo_region.html?f=1'],
  ['c2_titulo_region_f2', 'c_titulo_region.html?f=2'],
  ['c3_titulo_region_f3', 'c_titulo_region.html?f=3'],
  ['c_titulo_region_storyboard', 'c_storyboard.html'],
  ['d_misiones_marcadores', 'd_misiones_marcadores.html'],
  ['e_avisos_coop', 'e_avisos_coop.html'],
  ['f_mapa_diario', 'f_mapa_diario.html'],
  ['g_hoja_componentes', 'g_hoja_componentes.html'],
];
(async () => {
  const only = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--disable-gpu', '--font-render-hinting=none'] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  for (const [name, url] of PAGES) {
    if (only.length && !only.includes(name)) continue;
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(700);
    const file = path.join(OUT, name + '.jpg');
    await page.screenshot({ path: file, type: 'jpeg', quality: 88 });
    console.log('ok', name);
  }
  await browser.close();
})();
