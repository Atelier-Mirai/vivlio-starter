#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'fs';

const entries = [
  { href: '11-install.html' },
  { href: '81-install.html' }
];

function extractTitle(html) {
  const m = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  if (!m) return 'Untitled';
  // strip tags inside h1
  return m[1].replace(/<[^>]+>/g, '').trim();
}

const items = entries.map(({ href }) => {
  try {
    const html = readFileSync(href, 'utf8');
    const title = extractTitle(html) || href;
    return { href, title };
  } catch (e) {
    return { href, title: href };
  }
});

const doc = `<!doctype html>
<html lang="ja">
  <head>
    <meta charset="utf-8" />
    <title>目次</title>
    <link href="publication.json" rel="publication" type="application/ld+json" />
    <link href="stylesheets/11.css" rel="stylesheet" type="text/css" />
  </head>
  <body>
    <h1>目次</h1>
    <nav id="toc" role="doc-toc">
      <h2>Table of Contents</h2>
      <ol>
        ${items.map(it => `          <li><a href="${it.href}">${it.title}</a></li>`).join('\n')}
      </ol>
    </nav>
  </body>
</html>`;

writeFileSync('index.html', doc);
console.log('Wrote index.html with', items.length, 'entries');
