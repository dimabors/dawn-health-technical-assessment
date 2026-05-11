// Minimal HTTP server using only the Node stdlib (no external deps -> no
// supply-chain noise). Exposes /health for the readinessProbe and / as a
// trivial echo so you can `curl` it after the deployment lands.
const http = require('node:http');

const PORT = process.env.PORT || 8080;
const VERSION = process.env.APP_VERSION || 'dev';

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: VERSION }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ message: 'team-alpha-backend', version: VERSION, path: req.url }));
});

server.listen(PORT, () => {
  console.log(`team-alpha-backend listening on :${PORT} (version=${VERSION})`);
});

// Honour SIGTERM so Kubernetes can roll/cut over cleanly.
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down');
  server.close(() => process.exit(0));
});
