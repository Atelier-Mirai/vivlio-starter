#!/usr/bin/env node
// ================================================================
// bench/bench_preview_reload.mjs
// ================================================================
// 計測2: vivliostyle preview のリロード所要時間
//
// 1. vivliostyle preview を起動
// 2. Playwright で接続しレンダリング完了を待機
// 3. entries.js を書き換え → page.reload() → レンダリング完了まで計測
// 4. 3回繰り返して平均・最小・最大を報告
//
// 使い方:
//   node bench/bench_preview_reload.mjs
// ================================================================

import { chromium } from 'playwright';
import { spawn } from 'child_process';
import { writeFileSync, mkdtempSync, rmSync, readFileSync, openSync, closeSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import net from 'net';

const PORT = 13200;
const ITERATIONS = 3;

// --- ヘルパー ---

function writeEntries(dir, filenames) {
  const entries = filenames.map(f => `{ path: '${f}' }`).join(',\n  ');
  writeFileSync(join(dir, 'entries.js'),
    `const defined = [\n  ${entries}\n];\nexport default defined;\n`);
}

function writeHtml(dir, name, content) {
  writeFileSync(join(dir, name), `<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8"><title>${name}</title></head>
<body>${content}</body></html>`);
}

function portOpen(port) {
  return new Promise(resolve => {
    const socket = new net.Socket();
    socket.setTimeout(300);
    socket.on('connect', () => { socket.destroy(); resolve(true); });
    socket.on('timeout', () => { socket.destroy(); resolve(false); });
    socket.on('error', () => { socket.destroy(); resolve(false); });
    socket.connect(port, 'localhost');
  });
}

async function waitForPort(port, timeoutMs = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await portOpen(port)) return;
    await new Promise(r => setTimeout(r, 500));
  }
  throw new Error(`Port ${port} did not open within ${timeoutMs}ms`);
}

async function waitForRenderStable(page, timeoutMs = 60000) {
  const start = Date.now();
  let prev = 0, stable = 0;
  while (Date.now() - start < timeoutMs) {
    const count = await page.evaluate(() =>
      document.querySelectorAll('[data-vivliostyle-page-container]').length
    ).catch(() => 0);
    if (count > 0 && count === prev) {
      stable++;
      if (stable >= 3) return count;
    } else {
      stable = 0;
    }
    prev = count;
    await new Promise(r => setTimeout(r, 500));
  }
  throw new Error('Render did not stabilize');
}

// --- メイン ---

const dir = mkdtempSync(join(tmpdir(), 'vs-bench-reload-'));
console.log(`=== 計測2: vivliostyle preview リロード所要時間 ===`);
console.log(`作業ディレクトリ: ${dir}`);
console.log(`反復回数: ${ITERATIONS}\n`);

// HTML ファイル 2 種を作成
writeHtml(dir, 'page_a.html', '<h1>Page A</h1><p>Content A</p>');
writeHtml(dir, 'page_b.html', '<h1>Page B</h1><p>Content B</p>');
writeHtml(dir, 'page_c.html', '<h1>Page C</h1><p>Content C</p>');

// 初期 entries.js（page_a のみ）
writeEntries(dir, ['page_a.html']);

// vivliostyle.config.js
writeFileSync(join(dir, 'vivliostyle.config.js'), `
import entries from './entries.js';
const vivliostyleConfig = {
  title: 'Benchmark Reload',
  language: 'ja',
  entry: entries,
  output: ['./bench_output.pdf']
};
export default vivliostyleConfig;
`);

// preview 起動（ログをファイルにキャプチャして Preview URL を抽出）
console.log('vivliostyle preview を起動中...');
const logPath = join(dir, 'preview.log');
writeFileSync(logPath, '');
const logFd = openSync(logPath, 'a');
const preview = spawn('npx', ['vivliostyle', 'preview', '-c', 'vivliostyle.config.js',
  '--no-open-viewer', '--port', String(PORT)], {
  cwd: dir, stdio: ['ignore', logFd, logFd], detached: true
});

async function extractPreviewUrl(logFile, timeoutMs = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const content = readFileSync(logFile, 'utf-8');
    const match = content.match(/Preview URL:\s*(\S+)/);
    if (match) return match[1];
    await new Promise(r => setTimeout(r, 500));
  }
  // フォールバック
  return `http://localhost:${PORT}/__vivliostyle-viewer/index.html#src=http://localhost:${PORT}/vivliostyle/publication.json&bookMode=true&renderAllPages=true`;
}

try {
  await waitForPort(PORT);
  console.log(`preview サーバーが応答可能になりました (port: ${PORT})`);

  const previewUrl = await extractPreviewUrl(logPath);
  console.log(`Preview URL: ${previewUrl}\n`);

  // Playwright 接続
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1200, height: 1600 } });
  const page = await context.newPage();

  // 初回アクセス + レンダリング待機
  console.log('初回アクセス + レンダリング待機...');
  await page.goto(previewUrl, { waitUntil: 'networkidle', timeout: 120000 });

  // iframe 内のフレームを探す
  async function findRenderFrame(pg) {
    let count = await pg.evaluate(() =>
      document.querySelectorAll('[data-vivliostyle-page-container]').length
    ).catch(() => 0);
    if (count > 0) return pg;
    for (const frame of pg.frames()) {
      count = await frame.evaluate(() =>
        document.querySelectorAll('[data-vivliostyle-page-container]').length
      ).catch(() => 0);
      if (count > 0) return frame;
    }
    return null;
  }

  let renderTarget = await findRenderFrame(page);
  if (!renderTarget) {
    // #src= 付き URL で再試行
    const hashUrl = `${previewUrl}/#src=vivliostyle.config.js`;
    await page.goto(hashUrl, { waitUntil: 'networkidle', timeout: 60000 });
    renderTarget = await findRenderFrame(page);
  }

  if (!renderTarget) {
    throw new Error('ページコンテナが見つかりません');
  }

  const initPages = await waitForRenderStable(renderTarget);
  console.log(`初回レンダリング完了: ${initPages} ページ\n`);

  // --- リロード計測 ---
  const configs = [
    { label: 'A→A+B (2ページ)', files: ['page_a.html', 'page_b.html'] },
    { label: 'A+B→A (1ページ)', files: ['page_a.html'] },
    { label: 'A→A+B+C (3ページ)', files: ['page_a.html', 'page_b.html', 'page_c.html'] },
  ];

  const timings = [];

  for (let i = 0; i < ITERATIONS; i++) {
    const cfg = configs[i % configs.length];

    // entries.js を書き換え
    writeEntries(dir, cfg.files);

    // リロード + 計測
    const start = performance.now();
    await page.reload({ waitUntil: 'networkidle', timeout: 60000 });

    // レンダリング完了待機（リロード後にフレームが変わる可能性）
    renderTarget = await findRenderFrame(page) || page;
    const pageCount = await waitForRenderStable(renderTarget);
    const elapsed = (performance.now() - start) / 1000;

    timings.push(elapsed);
    console.log(`  Run ${i + 1} (${cfg.label}): ${elapsed.toFixed(3)}s → ${pageCount} ページ`);
  }

  console.log();
  console.log(`  平均: ${(timings.reduce((a, b) => a + b, 0) / timings.length).toFixed(3)}s`);
  console.log(`  最小: ${Math.min(...timings).toFixed(3)}s`);
  console.log(`  最大: ${Math.max(...timings).toFixed(3)}s`);

  await browser.close();

} finally {
  // preview プロセス停止
  try { closeSync(logFd); } catch {}
  try { process.kill(-preview.pid, 'SIGTERM'); } catch {}
  // 少し待ってからクリーンアップ
  await new Promise(r => setTimeout(r, 1000));
  try { rmSync(dir, { recursive: true, force: true }); } catch {}
  console.log('\nクリーンアップ完了');
}
