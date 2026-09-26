// VENTISCA · iconos de HUD (rejilla 24, silueta rellena + trazo 2 px en los de línea). Maqueta: se inyectan como <symbol>.
(function () {
  const S = (id, body, stroke) => `<symbol id="i-${id}" viewBox="0 0 24 24"${stroke ? ' fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"' : ''}>${body}</symbol>`;
  const icons = [
    S('heart', '<path d="M12 21C7.4 17.5 2.6 14.1 2.6 8.9A4.9 4.9 0 0 1 12 6.3a4.9 4.9 0 0 1 9.4 2.6c0 5.2-4.8 8.6-9.4 12.1z"/>'),
    S('thermo', '<path fill-rule="evenodd" d="M9.4 4.6a2.6 2.6 0 0 1 5.2 0v8.2a5 5 0 1 1-5.2 0zm1.6.1v8.9l-.7.4a3.4 3.4 0 1 0 3.4 0l-.7-.4V4.7a1 1 0 0 0-2 0z"/><circle cx="12" cy="16.9" r="2.1"/><rect x="11.25" y="9.5" width="1.5" height="6.5" rx=".7"/>'),
    S('meat', '<path d="M2.6 11.2h18.8a9.4 9.4 0 0 1-5.4 8.5v.9a1.3 1.3 0 0 1-1.3 1.3H9.3A1.3 1.3 0 0 1 8 20.6v-.9a9.4 9.4 0 0 1-5.4-8.5z"/><path d="M8 8.8c-1.2-1.4 1.2-2.4 0-3.8M12 8.8c-1.2-1.6 1.2-2.8 0-4.6M16 8.8c-1.2-1.4 1.2-2.4 0-3.8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>'),
    S('snow', '<path d="M12 2.5v19M3.8 7.2l16.4 9.6M3.8 16.8l16.4-9.6M9.3 4.2 12 6.6l2.7-2.4M9.3 19.8 12 17.4l2.7 2.4M3.4 10.6l3.4-.9-.9-3.5M20.6 13.4l-3.4.9.9 3.5M5.9 17.8l.9-3.5-3.4-.9M18.1 6.2l-.9 3.5 3.4.9"/>', true),
    S('wind', '<path d="M3 8.5h10.5a3 3 0 1 0-3-3M3 12.5h15.5a3 3 0 1 1-3 3M3 16.5h7"/>', true),
    S('drop', '<path d="M12 2.4c3.7 5.1 6.3 8.4 6.3 11.8a6.3 6.3 0 0 1-12.6 0c0-3.4 2.6-6.7 6.3-11.8z"/>'),
    S('blood', '<path d="M10 3c3.2 4.4 5.4 7.3 5.4 10.2a5.4 5.4 0 0 1-10.8 0C4.6 10.3 6.8 7.4 10 3z"/><path d="M18.6 11.5c1.3 1.8 2.2 3 2.2 4.2a2.2 2.2 0 0 1-4.4 0c0-1.2.9-2.4 2.2-4.2z"/>'),
    S('bandage', '<path fill-rule="evenodd" d="M4.2 14.6 14.6 4.2a4 4 0 0 1 5.7 5.7L9.9 20.3a4 4 0 0 1-5.7-5.7zm6.6-3.8a.9.9 0 1 0 1.3 1.3.9.9 0 0 0-1.3-1.3zm2.4 2.4a.9.9 0 1 0 1.3 1.3.9.9 0 0 0-1.3-1.3zM10.4 13.2a.9.9 0 1 0 1.3 1.3.9.9 0 0 0-1.3-1.3zm2.4-4.8a.9.9 0 1 0 1.3 1.3.9.9 0 0 0-1.3-1.3z"/>'),
    S('weight', '<path fill-rule="evenodd" d="M8.6 7.2a3.4 3.4 0 1 1 6.8 0l-.1.6h1.4a1.6 1.6 0 0 1 1.6 1.3l1.9 9.7A1.6 1.6 0 0 1 18.6 20.7H5.4a1.6 1.6 0 0 1-1.6-1.9l1.9-9.7a1.6 1.6 0 0 1 1.6-1.3h1.4zm1.8.6h3.2l.1-.6a1.7 1.7 0 1 0-3.4 0z"/>'),
    S('fever', '<path fill-rule="evenodd" d="M6.4 4.6a2.6 2.6 0 0 1 5.2 0v8.2a5 5 0 1 1-5.2 0zm1.6.1v8.9l-.7.4a3.4 3.4 0 1 0 3.4 0l-.7-.4V4.7a1 1 0 0 0-2 0z"/><circle cx="9" cy="16.9" r="2.1"/><path d="M15 6.5c1.2-1 2.4 1 3.6 0M15 10.5c1.2-1 2.4 1 3.6 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>'),
    S('frostbite', '<path d="M7 11V5.5a1.5 1.5 0 0 1 3 0V10V4a1.5 1.5 0 0 1 3 0v6V5a1.5 1.5 0 0 1 3 0v6.5V8a1.5 1.5 0 0 1 3 0v6a8 8 0 0 1-8 8h-.6a6 6 0 0 1-5.2-3l-2.8-4.8a1.5 1.5 0 0 1 2.5-1.6z"/><path d="M11 14.5v5M8.8 17h4.4" stroke="#0B111A" stroke-width="1.6" stroke-linecap="round" fill="none"/>'),
    S('skull', '<path fill-rule="evenodd" d="M12 2.5a8.5 8.5 0 0 0-5 15.4v2.3a1.3 1.3 0 0 0 1.3 1.3h7.4a1.3 1.3 0 0 0 1.3-1.3v-2.3A8.5 8.5 0 0 0 12 2.5zM8.6 9.8a2.1 2.1 0 1 0 0 4.2 2.1 2.1 0 0 0 0-4.2zm6.8 0a2.1 2.1 0 1 0 0 4.2 2.1 2.1 0 0 0 0-4.2zM12 14.6l-1.3 2.2h2.6z"/>'),
    S('diamond', '<path d="M12 1.8 22.2 12 12 22.2 1.8 12z"/>'),
    S('diamond-o', '<path fill-rule="evenodd" d="M12 1.8 22.2 12 12 22.2 1.8 12zm0 4L5.8 12l6.2 6.2 6.2-6.2z"/>'),
    S('hex', '<path fill-rule="evenodd" d="M12 1.8l8.8 5.1v10.2L12 22.2l-8.8-5.1V6.9zm0 7.4a2.8 2.8 0 1 0 0 5.6 2.8 2.8 0 0 0 0-5.6z"/>'),
    S('radio', '<circle cx="12" cy="12" r="2.2" fill="currentColor" stroke="none"/><path d="M8.2 8.2a5.4 5.4 0 0 0 0 7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6M5.2 5.2a9.6 9.6 0 0 0 0 13.6M18.8 5.2a9.6 9.6 0 0 1 0 13.6"/>', true),
    S('flag', '<path d="M5 21.5V3.5M5 4.5h11.5l-2.5 4 2.5 4H5"/>', true),
    S('house', '<path d="M2.8 11.2 12 3.2l9.2 8H18.8v9.3h-4.6v-5.8H9.8v5.8H5.2v-9.3z"/>'),
    S('fire', '<path d="M12.6 2.2c.4 3.3 4.6 5.3 5.4 9.6a6.4 6.4 0 0 1-12.6 1.9c-.4-2.2.3-4 1.6-5.7.1 1.6.8 2.8 2 3.4-.4-3.5 1.2-6.6 3.6-9.2zM12 13.6c-1.7 1.6-2.5 2.9-2.2 4.4a2.3 2.3 0 0 0 4.5.1c.3-1.5-.6-3-2.3-4.5z"/>'),
    S('boltoff', '<path d="M13.6 2.5 5.8 13.2h5.6l-1 8.3 7.8-10.7h-5.6z"/><path d="M3.5 3.5l17 17" stroke="#0B111A" stroke-width="4.2" stroke-linecap="round" fill="none"/><path d="M3.5 3.5l17 17" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>'),
    S('bolt', '<path d="M13.6 2.5 5.8 13.2h5.6l-1 8.3 7.8-10.7h-5.6z"/>'),
    S('clock', '<circle cx="12" cy="12" r="9"/><path d="M12 7v5.2l3.4 2"/>', true),
    S('truck', '<path fill-rule="evenodd" d="M1.8 6.2h11.4v9.3h1V9h4.1l3.9 4.6v4.6h-1.7a2.6 2.6 0 0 1-5.1 0H9.3a2.6 2.6 0 0 1-5.1 0H1.8zm14 4.3v3.2h4.1l-2.6-3.2zM6.8 16.9a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6zm10.1 0a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6z"/>'),
    S('crack', '<path d="M2.5 12.5h4l2.6-3.6 2 4.4 2.6-6.1 2.3 5.3h5.5M9.1 8.9 7.7 4.5M11.1 13.3l-1.4 5.9M16 12.5l2.4 5"/>', true),
    S('storm', '<path d="M3 7.5h8.5a2.6 2.6 0 1 0-2.6-2.6M3 11.5h13a3 3 0 1 1-3 3M3 15.5h6"/><path d="M18.5 3.5v5M16.3 4.8l4.4 2.4M16.3 7.2l4.4-2.4"/>', true),
    S('icestorm', '<path d="M6.8 14.5A4.3 4.3 0 0 1 7 6a5.8 5.8 0 0 1 11 1.7 3.4 3.4 0 0 1-.3 6.8z"/><path d="M8 17.2 6.8 21M12 17.2 10.8 21M16 17.2 14.8 21" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>'),
    S('sun', '<circle cx="12" cy="12" r="4.2" fill="currentColor"/><path d="M12 2.5v2.4M12 19.1v2.4M2.5 12h2.4M19.1 12h2.4M5.3 5.3 7 7M17 17l1.7 1.7M5.3 18.7 7 17M17 7l1.7-1.7"/>', true),
    S('moon', '<path d="M20 14.6A8.5 8.5 0 0 1 9.4 4a8.5 8.5 0 1 0 10.6 10.6z"/>'),
    S('check', '<path d="M4.5 12.5 9.5 17.5 19.5 6.5"/>', true),
    S('alert', '<path fill-rule="evenodd" d="M10.3 3.4a2 2 0 0 1 3.4 0l8.4 14.6a2 2 0 0 1-1.7 3H3.6a2 2 0 0 1-1.7-3zM11 9v5.2h2V9zm1 7.1a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4z"/>'),
    S('people', '<circle cx="8.5" cy="7.5" r="3.3"/><circle cx="16.8" cy="8.6" r="2.7"/><path d="M2.3 19.5a6.2 6.2 0 0 1 12.4 0zM14.9 19.5a7.6 7.6 0 0 0-1.9-5.2 5.2 5.2 0 0 1 8.7 5.2z"/>'),
    S('star', '<path d="M12 2.6l2.8 6 6.5.6-4.9 4.4 1.4 6.4L12 16.7 6.2 20l1.4-6.4-4.9-4.4 6.5-.6z"/>'),
    S('map', '<path d="M2.8 5.8 8.5 3.6l7 2.4 5.7-2.2v14.4l-5.7 2.2-7-2.4-5.7 2.2z"/><path d="M8.5 3.6v14.4M15.5 6v14.4" stroke="#0B111A" stroke-opacity=".5" stroke-width="1.4" fill="none"/>'),
    S('book', '<path d="M3 4.5c3.1-1 6-.7 9 1.2 3-1.9 5.9-2.2 9-1.2v14.8c-3.1-1-6-.7-9 1.2-3-1.9-5.9-2.2-9-1.2z"/><path d="M12 5.8v14.4" stroke="#0B111A" stroke-opacity=".45" stroke-width="1.3" fill="none"/>'),
    S('pack', '<path fill-rule="evenodd" d="M9 3.5h6a1 1 0 0 1 1 1V6a5.5 5.5 0 0 1 4 5.3v8.7a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 20v-8.7A5.5 5.5 0 0 1 8 6V4.5a1 1 0 0 1 1-1zm1 1.5v.6h4V5zm-2 9h8v4.5H8z"/>'),
    S('tower', '<path d="M12 7.5 7.3 21.5M12 7.5l4.7 14M9 16.5h6M10.2 12.5h3.6"/><circle cx="12" cy="5.5" r="1.8" fill="currentColor" stroke="none"/><path d="M7.8 2.8a5.9 5.9 0 0 0 0 5.4M16.2 2.8a5.9 5.9 0 0 1 0 5.4"/>', true),
    S('cross', '<path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"/>'),
    S('north', '<path d="M12 2.5 17.5 20 12 16.3 6.5 20z"/>'),
    S('arrowup', '<path d="M12 4 20 14h-5v6H9v-6H4z"/>'),
    S('arrowdn', '<path d="M12 20 4 10h5V4h6v6h5z"/>'),
    S('hammer', '<path d="M13.4 3.2 20.8 10.6l-2.2 2.2-2.4-2.4-9.6 9.6a1.9 1.9 0 0 1-2.7-2.7l9.6-9.6-1.6-1.6z"/>'),
    S('eye', '<path fill-rule="evenodd" d="M12 5c5 0 8.6 4 9.8 7-1.2 3-4.8 7-9.8 7s-8.6-4-9.8-7C3.4 9 7 5 12 5zm0 3.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z"/>'),
    S('ear', '<path d="M7 9a5 5 0 0 1 10 0c0 3-3 3.6-3 6.5a3 3 0 0 1-5.6 1.5"/><path d="M10 9.5a2 2 0 0 1 4 0c0 1.3-1.2 1.8-1.6 2.6"/>', true),
    S('horde', '<path d="M6.5 6.2a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8zM17.5 6.2a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8zM12 4.2a2.7 2.7 0 1 1 0 5.4 2.7 2.7 0 0 1 0-5.4zM7 21l1.2-6.6-2 .6-1-2.2L8.8 11h6.4l3.6 1.8-1 2.2-2-.6L17 21h-2.4l-.9-4.8h-3.4L9.4 21z"/>'),
    S('lock', '<path fill-rule="evenodd" d="M7 10V7.5a5 5 0 0 1 10 0V10h1a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 18 21H6a1.5 1.5 0 0 1-1.5-1.5v-8A1.5 1.5 0 0 1 6 10zm2.2 0h5.6V7.5a2.8 2.8 0 0 0-5.6 0z"/>'),
    S('car', '<path fill-rule="evenodd" d="M5.6 6.8A2 2 0 0 1 7.5 5.5h9a2 2 0 0 1 1.9 1.3l1.5 4.2a2.4 2.4 0 0 1 1.6 2.3V18h-2v1.6a1.2 1.2 0 0 1-2.4 0V18H6.9v1.6a1.2 1.2 0 0 1-2.4 0V18h-2v-4.7A2.4 2.4 0 0 1 4.1 11zM7.8 7.5l-1.2 3.4h10.8l-1.2-3.4zM6 13.2a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6zm12 0a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6z"/>'),
  ];
  const div = document.createElement('div');
  div.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
  div.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg">${icons.join('')}</svg>`;
  document.body.prepend(div);
})();
// rosa de rumbo: aguja (norte en ámbar) girada con la guiñada de cámara
function northRose(deg, size) {
  size = size || 44; const r = size / 2;
  let ticks = '';
  for (let a = 0; a < 360; a += 45) ticks += `<line x1="0" y1="${-r + 3}" x2="0" y2="${-r + (a % 90 ? 6 : 8)}" stroke="rgba(220,235,250,${a % 90 ? .35 : .6})" stroke-width="1.5" transform="rotate(${a + deg})"/>`;
  return `<svg width="${size}" height="${size}" viewBox="${-r} ${-r} ${size} ${size}" style="overflow:visible">
    <circle r="${r - 1}" fill="rgba(8,13,20,.35)" stroke="rgba(220,235,250,.28)" stroke-width="1"/>${ticks}
    <g transform="rotate(${deg})"><path d="M0 ${-r + 9} L5 0 L-5 0Z" fill="#FFB454"/><path d="M0 ${r - 9} L5 0 L-5 0Z" fill="rgba(220,235,250,.75)"/>
    <text x="0" y="${-r - 5}" text-anchor="middle" font-family="Barlow Condensed" font-weight="700" font-size="14" fill="#F3F8FD" transform="rotate(${-deg} 0 ${-r - 10})">N</text></g></svg>`;
}
function ic(id, cls) { return `<svg class="i ${cls || ''}"><use href="#i-${id}"/></svg>`; }
// anillo SVG: valor 0..1, color, grosor
function ringSvg(v, color, size, w, track) {
  size = size || 68; w = w || 5; const r = (size - w) / 2 - 3, c = 2 * Math.PI * r;
  return `<svg class="r" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <circle cx="${size / 2}" cy="${size / 2}" r="${r + w / 2 + 2}" fill="rgba(8,13,20,.55)"/>
    <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${track || 'rgba(220,235,250,.14)'}" stroke-width="${w}"/>
    <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="butt" stroke-dasharray="${c * v} ${c}"/>
    <circle cx="${size / 2}" cy="${size / 2}" r="${r + w / 2 + 2}" fill="none" stroke="rgba(220,235,250,.18)" stroke-width="1"/></svg>`;
}
