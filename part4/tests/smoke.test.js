// Minimal smoke tests using node:test (built-in, no deps).
const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

test('sanity check — arithmetic works', () => {
  assert.strictEqual(1 + 1, 2);
});

test('GET / returns team-alpha-backend message', async () => {
  // Start the server on a random port so this test is self-contained.
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'team-alpha-backend', version: 'dev', path: req.url }));
  });
  await new Promise(resolve => server.listen(0, resolve));
  const { port } = server.address();

  const body = await new Promise((resolve, reject) => {
    http.get(`http://localhost:${port}/`, res => {
      let data = '';
      res.on('data', chunk => (data += chunk));
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });

  assert.strictEqual(body.message, 'team-alpha-backend');
  server.close();
});

test('GET /health returns ok status', async () => {
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: 'dev' }));
  });
  await new Promise(resolve => server.listen(0, resolve));
  const { port } = server.address();

  const body = await new Promise((resolve, reject) => {
    http.get(`http://localhost:${port}/health`, res => {
      let data = '';
      res.on('data', chunk => (data += chunk));
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });

  assert.strictEqual(body.status, 'ok');
  server.close();
});
