const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
function startServer() {
  return new Promise((resolve, reject) => {
    const root = path.join(__dirname, 'ui');
    const server = http.createServer((req, res) => {
      const name = new URL(req.url, 'http://localhost').pathname;
      const allowed = { '/': 'index.html', '/style.css': 'style.css', '/app.js': 'app.js', '/art.js': 'art.js', '/youtube.js': 'youtube.js', '/assets/glass-turntable.png': 'assets/glass-turntable.png', '/assets/volume-fader.png': 'assets/volume/forge-gpt-image-2-5-sunburst-1.png' };
      if (!allowed[name]) { res.writeHead(404); return res.end(); }
      const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png' };
      res.setHeader('Content-Type', types[path.extname(allowed[name])] + '; charset=utf-8');
      res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
      const stream = fs.createReadStream(path.join(root, allowed[name]));
      stream.on('error', () => { if (!res.headersSent) res.writeHead(404); res.end(); });
      stream.pipe(res);
    });
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` }));
  });
}
module.exports = { startServer };
