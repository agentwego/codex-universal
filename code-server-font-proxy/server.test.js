'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  buildCodeServerArgs,
  rewriteHtml,
  shouldForceIdentity,
  shouldRewriteHtml,
} = require('./proxy-utils');

test('forces identity encoding for browser document requests', () => {
  assert.equal(shouldForceIdentity({ 'sec-fetch-dest': 'document', accept: '*/*' }), true);
  assert.equal(shouldForceIdentity({ accept: 'text/html,application/xhtml+xml' }), true);
});

test('preserves compression for static resource requests', () => {
  assert.equal(shouldForceIdentity({ 'sec-fetch-dest': 'script', accept: '*/*' }), false);
  assert.equal(shouldForceIdentity({ accept: 'text/css,*/*;q=0.1' }), false);
  assert.equal(shouldForceIdentity({ accept: 'application/javascript' }), false);
});

test('rewrites only identity-encoded HTML responses', () => {
  assert.equal(shouldRewriteHtml('text/html; charset=utf-8', undefined), true);
  assert.equal(shouldRewriteHtml('text/html', 'identity'), true);
  assert.equal(shouldRewriteHtml('text/html', 'gzip'), false);
  assert.equal(shouldRewriteHtml('application/javascript', undefined), false);
});

test('injects the font stylesheet and opts scripts out of Rocket Loader', () => {
  const html = '<html><head><script type="module" src="/workbench.js"></script></head></html>';
  const rewritten = rewriteHtml(html, '<link rel="stylesheet" href="/__fontproxy/cascadia.css">', '/__fontproxy/cascadia.css');

  assert.match(rewritten, /<link rel="stylesheet" href="\/__fontproxy\/cascadia\.css">\n<\/head>/);
  assert.match(rewritten, /<script data-cfasync="false" type="module" src="\/workbench\.js">/);
});

test('HTML rewriting is idempotent', () => {
  const html = '<html><head><link rel="stylesheet" href="/__fontproxy/cascadia.css"><script data-cfasync="false" src="/a.js"></script></head></html>';
  const rewritten = rewriteHtml(html, '<link rel="stylesheet" href="/__fontproxy/cascadia.css">', '/__fontproxy/cascadia.css');

  assert.equal(rewritten, html);
});

test('code-server arguments disable update checks and telemetry', () => {
  assert.deepEqual(buildCodeServerArgs('127.0.0.1', 17090, 'password', '/workspace'), [
    '--bind-addr', '127.0.0.1:17090',
    '--auth', 'password',
    '--disable-update-check',
    '--disable-telemetry',
    '/workspace',
  ]);
});
