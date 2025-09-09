/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: 'multi (direct HTML with TOC)',
  language: 'ja',
  // ルート直下の処理済み HTML を直接入力に使用
  entry: [
    { path: './11-install.html' },
    {
      // 目次テンプレートを使って index.html を生成
      path: 'toc-template.html',
      output: 'index.html',
      rel: 'contents'
    },
    { path: './81-install.html' }
  ],
  output: [ './multi-direct-html.pdf' ],
  size: '182mm 257mm',
  toc: {
    title: '目次',
    // h1〜h3 までの見出しを TOC/PDF ブックマークに含める
    sectionDepth: 3
  },
  outline: true
};
export default vivliostyleConfig;
