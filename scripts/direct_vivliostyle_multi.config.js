/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: 'multi (direct with TOC)',
  language: 'ja',
  // 複数章を直接指定。必要に応じてこの配列に追記/編集してください。
  entry: [
    { path: './contents/11-install.md' },
    { path: './contents/81-install.md' }
  ],
  output: [ './multi-direct.pdf' ],
  size: '182mm 257mm',
  toc: {
    title: '目次',
    // 各エントリ内の見出しをブックマーク対象に含める（h1〜h3）
    sectionDepth: 3
  },
  // 一部バージョンでは outline サポートがあるため、true を指定（未対応版では無視されます）
  outline: true
};
export default vivliostyleConfig;
