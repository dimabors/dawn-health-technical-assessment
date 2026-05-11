// Minimal smoke test using node:test (built-in, no deps).
const test = require('node:test');
const assert = require('node:assert');

test('sanity check', () => {
  assert.strictEqual(1 + 1, 2);
});
