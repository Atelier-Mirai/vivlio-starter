#!/usr/bin/env node
// ================================================================
// extract_page_mapping.mjs
// ================================================================
// Vivliostyle preview のヘッドレスブラウザから DOM を取得し、
// 各 glossary-link 要素がどのページに配置されたかのマッピングを
// JSON で標準出力する。
//
// 使い方:
//   node extract_page_mapping.mjs <preview_url> [timeout_ms]
//
// 出力 (stdout):
//   {
//     "mappings": [
//       { "anchor_id": "gls-src-08-web-ウェブサイト-4", "href": "...", "page_index": 0, "spine_index": 0 },
//       ...
//     ],
//     "backlink_mappings": [
//       { "href": "08-web.html#gls-src-08-web-ウェブサイト-4", "page_index": 12, "spine_index": 1 },
//       ...
//     ],
//     "total_pages": 42,
//     "extracted_at": "2026-02-06T17:00:00.000Z"
//   }
// ================================================================

import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  // ESM import はスクリプトのディレクトリから node_modules を探すため、
  // gem 内部から実行するとグローバルインストールが見つからない。
  // createRequire を使って CJS 解決にフォールバックする。
  try {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8' }).trim();
    const require = createRequire(globalRoot + '/');
    ({ chromium } = require('playwright'));
  } catch (e) {
    console.error('Error: playwright が見つかりません。npm install -g playwright を実行してください');
    process.exit(1);
  }
}

const PREVIEW_URL = process.argv[2];
const TIMEOUT_MS = parseInt(process.argv[3] || '120000', 10);

if (!PREVIEW_URL) {
  console.error('Usage: node extract_page_mapping.mjs <preview_url> [timeout_ms]');
  process.exit(1);
}

// ページコンテナが全て描画されるまで待機するポーリング関数
// window.coreViewer.readyState が COMPLETE になるまで待機する。
// vivliostyle viewer は window.coreViewer を公開しており、
// readystatechange イベントで COMPLETE を検知できる。
// ポーリングより確実かつ高速（完了の瞬間に処理を開始できる）。
async function waitForRenderComplete(page, timeoutMs) {
  return page.evaluate((timeoutMs) => {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error(`Timeout: レンダリング完了を ${timeoutMs}ms 以内に確認できませんでした`));
      }, timeoutMs);

      function checkAndListen() {
        const viewer = window.coreViewer;
        if (!viewer) {
          // coreViewer がまだ初期化されていない場合は少し待ってリトライ
          setTimeout(checkAndListen, 200);
          return;
        }

        // 既に COMPLETE の場合は即座に解決
        if (viewer.readyState === 'complete') {
          clearTimeout(timer);
          const count = document.querySelectorAll('[data-vivliostyle-page-container]').length;
          resolve(count);
          return;
        }

        // readystatechange イベントを待機
        viewer.addListener('readystatechange', function onReady() {
          if (viewer.readyState === 'complete') {
            viewer.removeListener('readystatechange', onReady);
            clearTimeout(timer);
            const count = document.querySelectorAll('[data-vivliostyle-page-container]').length;
            resolve(count);
          }
        });
      }

      checkAndListen();
    });
  }, timeoutMs);
}

// 指定フレーム（またはページ）内でページコンテナを探す
async function findPageContainers(pageOrFrame) {
  return pageOrFrame.evaluate(() =>
    document.querySelectorAll('[data-vivliostyle-page-container]').length
  ).catch(() => 0);
}

// メインページまたは iframe 内でページコンテナが見つかるフレームを返す
async function findRenderFrame(page) {
  // メインフレームを確認
  const mainCount = await findPageContainers(page);
  if (mainCount > 0) return page;

  // iframe を確認
  for (const frame of page.frames()) {
    const count = await findPageContainers(frame);
    if (count > 0) {
      console.error(`[debug] iframe 内にページコンテナを発見: ${frame.url()}`);
      return frame;
    }
  }
  return null;
}

// ページコンテナが出現するまでポーリングで待機する
// Vivliostyle viewer は networkidle 後も非同期でレンダリングを開始するため必要
const CONTAINER_POLL_INTERVAL = 500;  // 500ms間隔（1秒から短縮）
const CONTAINER_POLL_TIMEOUT = 60000; // 最大60秒

async function waitForRenderFrame(page) {
  const startTime = Date.now();

  while (Date.now() - startTime < CONTAINER_POLL_TIMEOUT) {
    const target = await findRenderFrame(page);
    if (target) return target;

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    console.error(`[debug] ページコンテナ待機中… (${elapsed}s)`);
    await new Promise(resolve => setTimeout(resolve, CONTAINER_POLL_INTERVAL));
  }
  return null;
}

// メイン処理
async function extractPageMapping() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1200, height: 1600 },
  });
  const page = await context.newPage();

  // ビューアーのコンソールログとエラーをキャプチャ（デバッグ用）
  page.on('console', msg => {
    if (msg.type() === 'error' || msg.type() === 'warning') {
      console.error(`[viewer ${msg.type()}] ${msg.text()}`);
    }
  });
  page.on('pageerror', err => console.error(`[viewer exception] ${err.message}`));

  try {
    // Vivliostyle preview ページにアクセス
    console.error(`[debug] navigating to: ${PREVIEW_URL}`);
    await page.goto(PREVIEW_URL, { waitUntil: 'networkidle', timeout: 60000 });
    console.error(`[debug] page loaded: ${page.url()} title="${await page.title()}"`);

    // coreViewer が初期化されるまで待機（waitForRenderComplete 内で処理）
    // renderTarget はメインページを使用
    let renderTarget = page;

    // デバッグ: coreViewer の存在確認
    const hasCoreViewer = await page.evaluate(() => !!window.coreViewer).catch(() => false);
    if (!hasCoreViewer) {
      console.error('[debug] coreViewer not yet available, will wait inside waitForRenderComplete');
    }

    // 最初のページコンテナが見つかった後、全ページのレンダリング完了を待機
    console.error('[debug] waiting for render to stabilize...');
    const totalPages = await waitForRenderComplete(page, TIMEOUT_MS);
    console.error(`[debug] render complete: ${totalPages} pages`);

    // DOM から glossary-link, glossary-backlink, index-term のマッピングを抽出
    // renderTarget はメインページまたは iframe のフレーム
    const result = await renderTarget.evaluate(() => {
      const mappings = [];
      const backlinkMappings = [];
      const indexMappings = [];

      // 全ページコンテナを走査
      const pageContainers = document.querySelectorAll('[data-vivliostyle-page-container]');

      pageContainers.forEach(pageEl => {
        const pageIndex = parseInt(pageEl.getAttribute('data-vivliostyle-page-index') || '-1', 10);
        const spineIndex = parseInt(pageEl.getAttribute('data-vivliostyle-spine-index') || '0', 10);

        // --- 本文中の glossary-link（†マーク）を収集 ---
        pageEl.querySelectorAll('.glossary-link').forEach(link => {
          const anchorId = link.getAttribute('id') || '';
          const href = link.getAttribute('href') || '';
          // Vivliostyle が付与する内部ID（data-vivliostyle-id）も取得
          const vivId = link.getAttribute('data-vivliostyle-id') || '';

          // id が "gls-src-" で始まるもののみ（本文中のソースリンク）
          if (anchorId.startsWith('gls-src-')) {
            mappings.push({ anchor_id: anchorId, href, page_index: pageIndex, spine_index: spineIndex });
          }
        });

        // --- 用語集ページの glossary-backlink を収集 ---
        pageEl.querySelectorAll('.glossary-backlink').forEach(link => {
          const href = link.getAttribute('href') || '';
          backlinkMappings.push({ href, page_index: pageIndex, spine_index: spineIndex });
        });

        // --- 本文中の index-term（<dfn>/<span> に idx- プレフィックス）を収集 ---
        pageEl.querySelectorAll('.index-term').forEach(el => {
          const anchorId = el.getAttribute('id') || '';
          if (anchorId.startsWith('idx-')) {
            indexMappings.push({ anchor_id: anchorId, page_index: pageIndex, spine_index: spineIndex });
          }
        });
      });

      return { mappings, backlinkMappings, indexMappings };
    });

    // 結果を JSON で出力
    const output = {
      mappings: result.mappings,
      backlink_mappings: result.backlinkMappings,
      index_mappings: result.indexMappings,
      total_pages: totalPages,
      extracted_at: new Date().toISOString(),
    };

    console.log(JSON.stringify(output, null, 2));
  } finally {
    await browser.close();
  }
}

extractPageMapping().catch(err => {
  console.error(`Error: ${err.message}`);
  process.exit(1);
});
