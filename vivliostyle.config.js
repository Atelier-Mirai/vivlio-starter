// 章立てのインポート
// import entries from './entries.js';

// @ts-check
/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: '電気・電子技術への招待 ～古代の叡智から現代AIまで～', // populated into 'publication.json', default to 'title' of the first entry or 'name' in 'package.json'.
  author: 'アトリヱ未來', // default to 'author' in 'package.json' or undefined
  language: 'ja',
  readingProgression: 'rtl', // reading progression direction, 'ltr' or 'rtl'.
  // size: 'A5',
  // size: 'A4',
  // theme: './stylesheets/body.css', // .css or local dir or npm package. default to undefined
  image: 'ghcr.io/vivliostyle/cli:9.5.0',
  entry: '11-gift.html',
    // **required field**
    // 'introduction.md', // 'title' is automatically guessed from the file (frontmatter > first heading)
    // {
    //   path: 'epigraph.md',
    //   title: 'おわりに', // title can be overwritten (entry > file),
    //   theme: '@vivliostyle/theme-whatever' // theme can be set individually. default to root 'theme'
    // },
    // 'glossary.html' // html is also acceptable
    // 'entry' can be 'string' or 'object' if there's only single markdown file

  // entryContext: './manuscripts', // default to '.' (relative to 'vivliostyle.config.js')
  output: [ // path to generate draft file(s). default to '{title}.pdf'
    './output.pdf', // the output format will be inferred from the name.
    // Web Publications
    // {
    //   path: './book',
    //   format: 'webpub'
    // },

    // EPUB
    // {
    //   path: './output.epub',
    //   format: 'epub',
    //   manifestLanguage: 'ja',
    //   // EPUBのページネーション設定
    //   options: {
    //     single: true,
    //     renderAllPages: true,
    //     sectionHeaderTags: ['h1', 'h2', 'h3'],
    //     customMeta: [
    //       { content: 'horizontal', name: 'primary-writing-mode' },
    //       { content: 'ltr', name: 'page-progression-direction' }
    //     ],
    //     readingProgression: 'ltr'
    //   },
    //   // EPUB用の追加スタイル
    //   extraStylesheets: ['./stylesheets/epub-overrides.css']
    // },
  ],
  // workspaceDir: '.vivliostyle', // directory which is saved intermediate files.
  // toc: {
  //   title: '目次',
  //   create: true,
  //   htmlPath: 'index.html',
  // },
  // cover: './cover.png', // cover image. default to undefined.
  // vfm: { // options of VFM processor
  //   replace: [ // specify replace handlers to modify HTML outputs
  //     {
  //       // This handler replaces {current_time} to a current local time tag.
  //       test: /{current_time}/,
  //       match: (_, h) => {
  //         const currentTime = new Date().toLocaleString();
  //         return h('time', { datetime: currentTime }, currentTime);
  //       },
  //     },
  //   ],
  //   hardLineBreaks: true, // converts line breaks of VFM to <br> tags. default to 'false'.
  //   disableFormatHtml: true, // disables HTML formatting. default to 'false'.
  // },
}

export default vivliostyleConfig;
