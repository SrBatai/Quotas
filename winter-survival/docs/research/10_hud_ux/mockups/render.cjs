// Renderiza las maquetas a 1920x1080 con Playwright Chromium (preinstalado).
// Uso (desde la raíz del repo, con un servidor estático en :18731 sirviendo la raíz):
//   python3 -m http.server 18731 --bind 127.0.0.1 &
//   taskset -c 2,3 node docs/research/10_hud_ux/mockups/render.cjs [nombre...]
//   taskset -c 2,3 node docs/research/10_hud_ux/mockups/render.cjs --measure [nombre...]
//       → capa de HUD sola (sin mundo, efectos de pantalla completa, velos ni anotaciones) en PNG con alfa,
//         en mockups/cov/<nombre>.png; después: python3 docs/research/10_hud_ux/mockups/measure_coverage.py
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const path = require('path');
const fs = require('fs');
const PORT = process.env.PORT || 18731;
const BASE = 'http://127.0.0.1:' + PORT + '/docs/research/10_hud_ux/mockups/';
const OUT = path.resolve(__dirname, '..');
const COV = path.resolve(__dirname, 'cov');
const PAGES = [
  // v1 «ESCARCHA»
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
  // v2 «SUSURRO» (minimal, recomendada)
  ['v2_a_explorando_vacio', 'v2_a_explorando_vacio.html'],
  ['v2_b_accion', 'v2_b_accion.html'],
  ['v2_c_titulo_zona', 'v2_c_titulo_zona.html'],
  ['v2_c_titulo_zona_solo', 'v2_titulo.html?f=2'],
  ['v2_d_noche_ventisca', 'v2_d_noche_ventisca.html'],
  ['v2_e_coop_derribado', 'v2_e_coop_derribado.html'],
  ['v2_f_mision_abierta', 'v2_f_mision_abierta.html'],
  ['v2_comparativa', 'v2_comparativa.html'],
];
// páginas que se miden (las hojas de presentación no)
const MEASURE = ['a_hud_dia', 'b_hud_noche_ventisca', 'd_misiones_marcadores', 'e_avisos_coop',
  'v2_a_explorando_vacio', 'v2_b_accion', 'v2_c_titulo_zona_solo', 'v2_d_noche_ventisca', 'v2_e_coop_derribado', 'v2_f_mision_abierta'];
// en la medición se ocultan el mundo, los efectos de pantalla completa, los velos de degradado y las anotaciones
const HIDE = `.bg,.fx,.note,.frame-tag,#snow,.scrim,.fog,.glow,.vig-cold,.vig-dmg,.dark,.veil,.under,.under2,.hit
  { display: none !important; } html, body, .stage { background: transparent !important; }`;
(async () => {
  const args = process.argv.slice(2);
  const measure = args.includes('--measure');
  const only = args.filter(a => !a.startsWith('--'));
  const browser = await chromium.launch({ args: ['--disable-gpu', '--font-render-hinting=none'] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  if (measure) fs.mkdirSync(COV, { recursive: true });
  for (const [name, url] of PAGES) {
    if (only.length && !only.includes(name)) continue;
    if (measure && !MEASURE.includes(name)) continue;
    if (!measure && name === 'v2_c_titulo_zona_solo') continue;
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    if (measure) await page.addStyleTag({ content: HIDE });
    await page.waitForTimeout(700);
    if (measure) {
      await page.screenshot({ path: path.join(COV, name + '.png'), omitBackground: true });
    } else {
      await page.screenshot({ path: path.join(OUT, name + '.jpg'), type: 'jpeg', quality: 88 });
    }
    console.log('ok', name, measure ? '(medición)' : '');
  }
  await browser.close();
})();
