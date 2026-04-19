import entries from './entries.js';

// @ts-check
/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: '初めてのウェブアプリ開発 じゃんけんゲームを創ろう', // 書籍のタイトル
  author: 'アトリヱ未來', // 著者名
  language: 'ja', // 言語設定
  size: 'A4', // ページサイズ（book.yml のプリセットから自動設定）
  readingProgression: 'ltr', // 読み進め方向（ltr: 横書き, rtl: 縦書き）
  entry: entries, // 章立て構成（entries.jsから読み込み）
  output: [ // 出力ファイル設定
    './output.pdf' // PDFファイル
  ]
,
vfm: {
  hardLineBreaks: true // VFMハード改行設定
}
};

export default vivliostyleConfig;
