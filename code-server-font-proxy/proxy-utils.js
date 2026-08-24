'use strict';

function headerValue(headers, name) {
  const value = headers?.[name];
  if (Array.isArray(value)) return value.join(',');
  return String(value || '');
}

function shouldForceIdentity(headers) {
  const destination = headerValue(headers, 'sec-fetch-dest').toLowerCase();
  const accept = headerValue(headers, 'accept').toLowerCase();
  return destination === 'document' || /(?:^|[,;\s])text\/html(?:[,;\s]|$)/.test(accept);
}

function shouldRewriteHtml(contentType, contentEncoding) {
  const isHtml = /^text\/html(?:;|$)/i.test(String(contentType || ''));
  const encoding = String(contentEncoding || 'identity').trim().toLowerCase();
  return isHtml && (!encoding || encoding === 'identity');
}

function rewriteHtml(html, injectionMarkup, cssPath) {
  let rewritten = html.replace(
    /<script\b(?![^>]*\bdata-cfasync\s*=)/gi,
    '<script data-cfasync="false"',
  );
  if (!rewritten.includes(cssPath)) {
    rewritten = rewritten.replace(/<\/head>/i, `${injectionMarkup}\n</head>`);
  }
  return rewritten;
}

function buildCodeServerArgs(host, port, auth, workdir) {
  return [
    '--bind-addr', `${host}:${port}`,
    '--auth', auth,
    '--disable-update-check',
    '--disable-telemetry',
    workdir,
  ];
}

module.exports = {
  buildCodeServerArgs,
  rewriteHtml,
  shouldForceIdentity,
  shouldRewriteHtml,
};
