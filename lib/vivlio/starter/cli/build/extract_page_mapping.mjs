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

import { chromium } from 'playwright';

const PREVIEW_URL = process.argv[2];
const TIMEOUT_MS = parseInt(process.argv[3] || '120000', 10);

if (!PREVIEW_URL) {
  console.error('Usage: node extract_page_mapping.mjs <preview_url> [timeout_ms]');
  process.exit(1);
}

// ページコンテナが全て描画されるまで待機するポーリング関数
async function waitForRenderComplete(page, timeoutMs) {
  const startTime = Date.now();
  let previousCount = 0;
  let stableCount = 0;
  const STABLE_THRESHOLD = 3; // 3回連続で同数なら完了とみなす
  const POLL_INTERVAL = 2000; // 2秒間隔

  while (Date.now() - startTime < timeoutMs) {
    const currentCount = await page.evaluate(() => {
      return document.querySelectorAll('[data-vivliostyle-page-container]').length;
    });

    if (currentCount > 0 && currentCount === previousCount) {
      stableCount++;
      if (stableCount >= STABLE_THRESHOLD) {
        return currentCount;
      }
    } else {
      stableCount = 0;
    }
    previousCount = currentCount;
    await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL));
  }

  throw new Error(`Timeout: レンダリング完了を ${timeoutMs}ms 以内に確認できませんでした`);
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

// メイン処理
async function extractPageMapping() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1200, height: 1600 },
  });
  const page = await context.newPage();

  try {
    // Vivliostyle preview ページにアクセス
    console.error(`[debug] navigating to: ${PREVIEW_URL}`);
    await page.goto(PREVIEW_URL, { waitUntil: 'networkidle', timeout: 60000 });
    console.error(`[debug] page loaded: ${page.url()} title="${await page.title()}"`);

    // ページコンテナを探す（メインフレーム → iframe）
    let renderTarget = await findRenderFrame(page);

    // 見つからなければ #src= 付き URL で再試行
    if (!renderTarget) {
      const hashUrl = `${PREVIEW_URL}/#src=vivliostyle.config.js`;
      console.error(`[debug] page containers not found, retrying: ${hashUrl}`);
      await page.goto(hashUrl, { waitUntil: 'networkidle', timeout: 60000 });
      console.error(`[debug] page loaded: ${page.url()} title="${await page.title()}"`);
      renderTarget = await findRenderFrame(page);
    }

    if (!renderTarget) {
      // デバッグ: ページの構造をダンプ
      const bodySnippet = await page.evaluate(() =>
        document.body ? document.body.innerHTML.substring(0, 500) : '(no body)'
      );
      console.error(`[debug] body snippet: ${bodySnippet}`);
      throw new Error('ページコンテナが見つかりません。vivliostyle preview の URL/設定を確認してください');
    }

    // 最初のページコンテナが見つかった後、全ページのレンダリング完了を待機
    console.error('[debug] waiting for render to stabilize...');
    const totalPages = await waitForRenderComplete(renderTarget, TIMEOUT_MS);
    console.error(`[debug] render complete: ${totalPages} pages`);

    // DOM から glossary-link と glossary-backlink のマッピングを抽出
    // renderTarget はメインページまたは iframe のフレーム
    const result = await renderTarget.evaluate(() => {
      const mappings = [];
      const backlinkMappings = [];

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
      });

      return { mappings, backlinkMappings };
    });

    // 結果を JSON で出力
    const output = {
      mappings: result.mappings,
      backlink_mappings: result.backlinkMappings,
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
