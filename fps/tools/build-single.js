/* Gera dist/mirage-protocol.html: um único arquivo HTML com CSS, Three.js e todo o código embutidos.
 *   node tools/build-single.js
 * O arquivo resultante funciona offline e pode ser aberto direto no navegador ou servido por HTTP. */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
let html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');

html = html.replace(/<link rel="stylesheet" href="([^"]+)">/g, (m, href) => {
  const css = fs.readFileSync(path.join(ROOT, href), 'utf8');
  return '<style>\n' + css + '\n</style>';
});
let count = 0;
html = html.replace(/<script src="([^"]+)"><\/script>/g, (m, src) => {
  const js = fs.readFileSync(path.join(ROOT, src), 'utf8').replace(/<\/script/gi, '<\\/script');
  count++;
  return '<script>/* ' + src + ' */\n' + js + '\n</script>';
});
const out = path.join(ROOT, 'dist', 'mirage-protocol.html');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
console.log(`Gerado ${path.relative(ROOT, out)} (${count} scripts embutidos, ${(Buffer.byteLength(html) / 1024).toFixed(0)} KB)`);
