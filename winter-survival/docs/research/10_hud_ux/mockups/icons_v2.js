// VENTISCA v2 · iconos de línea finos (rejilla 24, trazo 1,5 px). Se usan con moderación.
(function () {
  const S = (id, body) => `<symbol id="l-${id}" viewBox="0 0 24 24">${body}</symbol>`;
  const icons = [
    S('heart', '<path d="M12 20c-4.4-3.4-8.6-6.4-8.6-11a4.4 4.4 0 0 1 8.6-1.8A4.4 4.4 0 0 1 20.6 9c0 4.6-4.2 7.6-8.6 11z"/>'),
    S('thermo', '<path d="M10 14.2V5a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z"/><path d="M12 11v6"/>'),
    S('bowl', '<path d="M3.5 12h17a8.5 8.5 0 0 1-17 0z"/><path d="M8.5 8.5c-.8-1 .8-1.8 0-3M12 8.5c-.8-1 .8-1.8 0-3M15.5 8.5c-.8-1 .8-1.8 0-3"/>'),
    S('drop', '<path d="M12 3.5c3.2 4.4 5.4 7.2 5.4 10.1a5.4 5.4 0 0 1-10.8 0c0-2.9 2.2-5.7 5.4-10.1z"/>'),
    S('snow', '<path d="M12 3v18M4.2 7.5l15.6 9M4.2 16.5l15.6-9M9.6 4.8 12 7l2.4-2.2M9.6 19.2 12 17l2.4 2.2"/>'),
    S('wind', '<path d="M3 9h10.5a2.7 2.7 0 1 0-2.7-2.7M3 13h14.5a2.7 2.7 0 1 1-2.7 2.7M3 17h6"/>'),
    S('skull', '<path d="M12 3.5a7.5 7.5 0 0 0-4.4 13.6v2.4c0 .5.4 1 1 1h6.8c.6 0 1-.5 1-1v-2.4A7.5 7.5 0 0 0 12 3.5z"/><circle cx="9.2" cy="11.6" r="1.6"/><circle cx="14.8" cy="11.6" r="1.6"/><path d="M11 20.5v-2M13 20.5v-2"/>'),
    S('flame', '<path d="M12.4 3c.4 3 4.2 4.8 4.9 8.7a5.4 5.4 0 0 1-10.6 1.6c-.3-1.8.3-3.4 1.4-4.8.1 1.4.7 2.4 1.7 2.9-.3-3 1-5.6 2.6-8.4z"/>'),
    S('house', '<path d="M4 11 12 4l8 7M6 9.5V20h12V9.5M10 20v-5h4v5"/>'),
    S('check', '<path d="M5 12.5 9.5 17 19 7"/>'),
    S('boltoff', '<path d="M13 3 6.5 12.5h5L10.5 21 17 11.5h-5z"/><path d="M4 4l16 16"/>'),
    S('radio', '<circle cx="12" cy="12" r="1.6"/><path d="M8.6 8.6a4.8 4.8 0 0 0 0 6.8M15.4 8.6a4.8 4.8 0 0 1 0 6.8M5.8 5.8a8.8 8.8 0 0 0 0 12.4M18.2 5.8a8.8 8.8 0 0 1 0 12.4"/>'),
    S('truck', '<path d="M2.5 6.5h11v9h-11zM13.5 9.5h4l3 3.5v2.5h-7"/><circle cx="6.5" cy="17" r="1.6"/><circle cx="16.5" cy="17" r="1.6"/>'),
    S('blood', '<path d="M10 4c2.8 3.8 4.6 6.3 4.6 8.8a4.6 4.6 0 0 1-9.2 0C5.4 10.3 7.2 7.8 10 4z"/><path d="M17.5 12c1 1.4 1.8 2.4 1.8 3.4a1.8 1.8 0 0 1-3.6 0c0-1 .8-2 1.8-3.4z"/>'),
    S('crack', '<path d="M3 12.5h3.5l2.3-3.2 1.8 4 2.3-5.5 2.1 4.8H20"/>'),
    S('storm', '<path d="M3 8h8.5a2.3 2.3 0 1 0-2.3-2.3M3 12h12.5a2.7 2.7 0 1 1-2.7 2.7M3 16h6"/><path d="M18.5 4v4.5M16.6 5.1l3.8 2.2M16.6 7.4l3.8-2.2"/>'),
    S('ear', '<path d="M7 9a5 5 0 0 1 10 0c0 3-3 3.6-3 6.5a3 3 0 0 1-5.6 1.5"/>'),
    S('talk', '<path d="M4 5.5h16v10H10l-4 3.5v-3.5H4z"/>'),
  ];
  const div = document.createElement('div');
  div.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
  div.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg">${icons.join('')}</svg>`;
  document.body.prepend(div);
})();
function li(id, cls, style) { return `<svg class="li ${cls || ''}" ${style ? `style="${style}"` : ''}><use href="#l-${id}"/></svg>`; }
// anillo fino (40 px, trazo 2 px, sin disco de fondo)
function thinRing(v, color, size, w) {
  size = size || 40; w = w || 2; const r = size / 2 - w, c = 2 * Math.PI * r;
  return `<svg class="r" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <circle cx="${size / 2}" cy="${size / 2}" r="${r + 5}" fill="rgba(4,8,14,.22)" filter="blur(3px)"/>
    <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="rgba(243,248,253,.22)" stroke-width="${w}"/>
    <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${w}" stroke-dasharray="${c * v} ${c}" stroke-linecap="round"/></svg>`;
}
// ?clean=1 oculta las anotaciones de diseño (para la comparativa). La medición la hace render.cjs --measure.
if (new URLSearchParams(location.search).get('clean')) {
  const st = document.createElement('style');
  st.textContent = `.note{display:none!important}`;
  document.head.appendChild(st);
}
