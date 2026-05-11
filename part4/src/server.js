// Minimal HTTP server using only the Node stdlib (no external deps -> no
// supply-chain noise). Exposes /health for the readinessProbe and / as a
// trivial echo so you can `curl` it after the deployment lands.
const http = require('node:http');

const PORT = process.env.PORT || 8080;
const VERSION = process.env.APP_VERSION || 'dev';

// Minimal in-memory dataset — simulates a real patients service without a DB.
const PATIENTS = [
  { id: 'p-001', name: 'Alice Martin',  dob: '1990-04-12', condition: 'hypertension' },
  { id: 'p-002', name: 'Bob Chen',      dob: '1985-09-30', condition: 'diabetes-type-2' },
  { id: 'p-003', name: 'Carol Davis',   dob: '2001-01-07', condition: 'asthma' },
];

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: VERSION }));
    return;
  }

  // GET /api/v1/patients — list all patients (new in v1.1.0)
  if (req.url === '/api/v1/patients') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ version: VERSION, count: PATIENTS.length, patients: PATIENTS }));
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
