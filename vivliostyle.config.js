import entries from './entries.js';

// @ts-check
// 自動生成: config/book.yml のビルド設定（手編集しない）
// 生成器: VivlioStarter::CLI::Build::VivliostyleConfigWriter（毎ビルド再生成）
// 設定変更は config/book.yml を編集すること。
// このファイルは vs entries → vs pdf の著者向け手動フロー用。
// ビルドパイプラインは .cache/vs/build/ 配下の用途別 config を使う（P4 §3.2）。
/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: 'はじめての技術書づくり Vivlio Starter 実践ガイド',
  author: '早乙女 遙香',
  language: 'ja',
  size: 'A4',
  readingProgression: 'ltr',
  entry: entries.map((entry) => ({
    ...entry,
    // VFM 設定はエントリーレベルで適用（Vivliostyle CLI 公式推奨・PLANNED 対応）
    vfm: { hardLineBreaks: true }
  })),
  output: [
    './output.pdf'
  ]
};

export default vivliostyleConfig;
