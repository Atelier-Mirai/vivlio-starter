import entries from './entries.js';

// @ts-check
/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: '電気・電子技術への招待 ～古代の叡智から現代AIまで～', // 書籍のタイトル
  author: 'アトリヱ未来', // 著者名
  language: 'ja', // 言語設定
  readingProgression: 'ltr', // 読み進め方向（ltr: 横書き, rtl: 縦書き）
  entry: entries, // 章立て構成（entries.jsから読み込み）
  // entry: '93-appendix-c.html',
  // entry: ["03-toc.html", "11-gift.html", "90-appendices.html"],
  // entry: ["91-appendix-a.html"],
  output: [ // 出力ファイル設定
    './output.pdf' // PDFファイル
  ]
};

export default vivliostyleConfig;

