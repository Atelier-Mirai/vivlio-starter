/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: '11-install (direct with TOC)',
  language: 'ja',
  entry: [ { path: './contents/11-install.md' } ],
  output: [ './11-direct.pdf' ],
  size: '182mm 257mm',
  // 目次の作成（公式ドキュメントの toc オプションに準拠）
  toc: {
    title: '目次',
    depth: 3,
    // include セレクタの例: 'h1, h2, h3'（既定は h1〜h3）
    include: 'h1, h2, h3'
  },
  // 一部バージョンでは outline サポートがあるため、true を指定（未対応版では無視されます）
  outline: true
};
export default vivliostyleConfig;
