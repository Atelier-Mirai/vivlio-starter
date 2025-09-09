/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: '81-install (direct with TOC)',
  language: 'ja',
  entry: [ { path: './contents/81-install.md' } ],
  output: [ './81-direct.pdf' ],
  size: '182mm 257mm',
  toc: {
    title: '目次',
    depth: 3,
    include: 'h1, h2, h3'
  },
  outline: true
};
export default vivliostyleConfig;
