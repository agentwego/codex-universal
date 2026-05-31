#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const httpProxy = require('http-proxy');

const installDir = __dirname;
const fontPath = path.join(installDir, 'fonts', 'CascadiaCode.ttf');
const cssPath = '/__fontproxy/cascadia.css';
const fontRoute = '/__fontproxy/CascadiaCode.ttf';
const injectionMarkup = `<link rel="stylesheet" href="${cssPath}">`;

const proxyHost = process.env.CODE_SERVER_HOST || '0.0.0.0';
const proxyPort = Number.parseInt(process.env.CODE_SERVER_PORT || '8080', 10);
const realHost = process.env.CODE_SERVER_REAL_HOST || '127.0.0.1';
const realPort = Number.parseInt(process.env.CODE_SERVER_REAL_PORT || '17090', 10);
const auth = process.env.CODE_SERVER_AUTH || 'none';
const workdir = process.env.CODE_SERVER_WORKDIR || '/workspace';
const target = `http://${realHost}:${realPort}`;

if (!Number.isInteger(proxyPort) || proxyPort <= 0) {
  throw new Error(`Invalid CODE_SERVER_PORT=${process.env.CODE_SERVER_PORT}`);
}
if (!Number.isInteger(realPort) || realPort <= 0) {
  throw new Error(`Invalid CODE_SERVER_REAL_PORT=${process.env.CODE_SERVER_REAL_PORT}`);
}

const css = `@font-face {
  font-family: 'Cascadia Code Web';
  src: url('${fontRoute}') format('truetype');
  font-display: swap;
}

:root {
  --vscode-editor-font-family: 'Cascadia Code Web', 'Cascadia Code', monospace !important;
}

.monaco-workbench,
.monaco-editor,
.monaco-editor .view-lines,
.monaco-editor .view-line,
.view-lines,
.mtk1,
.xterm,
.xterm-rows,
.terminal,
.integrated-terminal {
  font-family: 'Cascadia Code Web', 'Cascadia Code', monospace !important;
}
`;

let shuttingDown = false;

const codeServer = spawn('code-server', [
  '--bind-addr', `${realHost}:${realPort}`,
  '--auth', auth,
  workdir,
], {
  stdio: ['ignore', 'inherit', 'inherit'],
  env: {
    ...process.env,
    CODE_SERVER_HOST: realHost,
    CODE_SERVER_PORT: String(realPort),
  },
});

codeServer.on('error', (error) => {
  console.error(`[font-proxy] failed to start code-server: ${error.stack || error}`);
  process.exitCode = 1;
  shutdown('SIGTERM');
});

codeServer.on('exit', (code, signal) => {
  if (shuttingDown) return;
  console.error(`[font-proxy] code-server exited unexpectedly code=${code} signal=${signal || ''}`);
  process.exit(code ?? 1);
});

const proxy = httpProxy.createProxyServer({
  target,
  ws: true,
  xfwd: true,
  selfHandleResponse: true,
});

proxy.on('proxyReq', (proxyReq) => {
  proxyReq.setHeader('accept-encoding', 'identity');
});

proxy.on('proxyRes', (proxyRes, req, res) => {
  const headers = { ...proxyRes.headers };
  const contentType = String(headers['content-type'] || '');
  const isHtml = /^text\/html(?:;|$)/i.test(contentType);

  if (!isHtml) {
    res.writeHead(proxyRes.statusCode || 500, headers);
    proxyRes.pipe(res);
    return;
  }

  const chunks = [];
  proxyRes.on('data', (chunk) => chunks.push(chunk));
  proxyRes.on('end', () => {
    const original = Buffer.concat(chunks).toString('utf8');
    const rewritten = original.includes(cssPath)
      ? original
      : original.replace(/<\/head>/i, `${injectionMarkup}\n</head>`);
    const body = Buffer.from(rewritten, 'utf8');

    delete headers['content-length'];
    delete headers['content-encoding'];
    headers['content-type'] = contentType || 'text/html; charset=utf-8';
    headers['content-length'] = String(body.length);

    res.writeHead(proxyRes.statusCode || 200, headers);
    res.end(body);
  });
});

proxy.on('error', (error, req, res) => {
  console.error(`[font-proxy] proxy error for ${req?.method || ''} ${req?.url || ''}: ${error.stack || error}`);
  if (res && !res.headersSent) {
    res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
  }
  if (res && !res.writableEnded) {
    res.end('Bad Gateway: code-server is not ready or is unavailable.\n');
  }
});

function serveCss(res) {
  res.writeHead(200, {
    'content-type': 'text/css; charset=utf-8',
    'cache-control': 'public, max-age=3600',
    'content-length': Buffer.byteLength(css),
  });
  res.end(css);
}

function serveFont(res) {
  fs.stat(fontPath, (statError, stat) => {
    if (statError) {
      console.error(`[font-proxy] font missing at ${fontPath}: ${statError.stack || statError}`);
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('CascadiaCode.ttf not found\n');
      return;
    }

    res.writeHead(200, {
      'content-type': 'font/ttf',
      'cache-control': 'public, max-age=31536000, immutable',
      'content-length': String(stat.size),
    });

    const stream = fs.createReadStream(fontPath);
    stream.on('error', (error) => {
      console.error(`[font-proxy] font stream error: ${error.stack || error}`);
      if (!res.headersSent) {
        res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
      }
      if (!res.writableEnded) {
        res.end('Unable to read CascadiaCode.ttf\n');
      }
    });
    stream.pipe(res);
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', 'http://fontproxy.local');

  if (req.method === 'GET' || req.method === 'HEAD') {
    if (url.pathname === cssPath) {
      if (req.method === 'HEAD') {
        res.writeHead(200, {
          'content-type': 'text/css; charset=utf-8',
          'cache-control': 'public, max-age=3600',
          'content-length': Buffer.byteLength(css),
        });
        res.end();
      } else {
        serveCss(res);
      }
      return;
    }

    if (url.pathname === fontRoute) {
      if (req.method === 'HEAD') {
        fs.stat(fontPath, (statError, stat) => {
          if (statError) {
            res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
          } else {
            res.writeHead(200, {
              'content-type': 'font/ttf',
              'cache-control': 'public, max-age=31536000, immutable',
              'content-length': String(stat.size),
            });
          }
          res.end();
        });
      } else {
        serveFont(res);
      }
      return;
    }
  }

  proxy.web(req, res);
});

server.on('upgrade', (req, socket, head) => {
  proxy.ws(req, socket, head, { target });
});

server.listen(proxyPort, proxyHost, () => {
  console.error(`[font-proxy] listening on ${proxyHost}:${proxyPort}, proxying to ${target}`);
  console.error(`[font-proxy] code-server workdir=${workdir} auth=${auth}`);
});

server.on('error', (error) => {
  console.error(`[font-proxy] server error: ${error.stack || error}`);
  process.exitCode = 1;
  shutdown('SIGTERM');
});

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.error(`[font-proxy] received ${signal}; shutting down`);

  server.close(() => {
    proxy.close();
  });

  if (!codeServer.killed) {
    codeServer.kill(signal);
  }

  const timeout = setTimeout(() => {
    if (!codeServer.killed) {
      codeServer.kill('SIGKILL');
    }
    process.exit(process.exitCode || 0);
  }, 8000);
  timeout.unref();

  codeServer.once('exit', () => {
    clearTimeout(timeout);
    process.exit(process.exitCode || 0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
