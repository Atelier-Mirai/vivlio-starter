# Third-Party Licenses

This project uses the following third-party software:

## Vivliostyle CLI
- License: AGPLv3
- Project: https://github.com/vivliostyle/vivliostyle
- CLI Package: https://github.com/vivliostyle/vivliostyle-cli
- License Text: https://www.gnu.org/licenses/agpl-3.0.html

Notes:
- Vivliostyle is used as a build tool to generate PDF/HTML outputs. The content of this repository (book manuscript, images, and custom scripts) is licensed separately as stated in `README.md` and corresponding LICENSE files.
- If you redistribute Vivliostyle itself or provide it as part of a network service, please follow the AGPLv3 requirements for Vivliostyle.

### 参考訳（日本語・非公式）
- ライセンス: AGPLv3（GNU Affero General Public License v3）
- プロジェクト: https://github.com/vivliostyle/vivliostyle
- CLI パッケージ: https://github.com/vivliostyle/vivliostyle-cli
- ライセンス本文: https://www.gnu.org/licenses/agpl-3.0.html

補足:
- 本リポジトリでは、Vivliostyle は PDF/HTML を生成するためのビルドツールとして利用しています。原稿や画像、独自スクリプト等のコンテンツは `README.md` や各 LICENSE に記載のとおり別ライセンスで配布しています。
- Vivliostyle 自体を再配布する場合や、ネットワーク越しのサービスとして提供する場合は、AGPLv3 の要件に従ってください。

## PrismJS
- License: MIT
- Project: https://prismjs.com/
- Download/Build: https://prismjs.com/download.html
- Source: https://github.com/PrismJS/prism
- Copyright: (c) 2012-2023 PrismJS and contributors
- License Text: https://opensource.org/licenses/MIT

Notes:
- `stylesheets/prism.css` is a downloaded build from PrismJS. The file header includes the MIT license notice.

### 参考訳（日本語・非公式）
- ライセンス: MIT
- プロジェクト: https://prismjs.com/
- ダウンロード/ビルド: https://prismjs.com/download.html
- ソース: https://github.com/PrismJS/prism
- 著作権表示: (c) 2012-2023 PrismJS and contributors
- ライセンス本文: https://opensource.org/licenses/MIT

補足:
- `stylesheets/prism.css` は PrismJS からダウンロードしたビルド版です。ファイル先頭に MIT ライセンスの注記を含めています。

## 書体 (Fonts)

### HackGen / HackGen35
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://github.com/yuru7/HackGen
- Copyright: (c) 2019, Yuko OTAWARA. with Reserved Font Name "白源", "HackGen"
- License Text: included at `stylesheets/fonts/hackgen35/LICENSE`

Notes:
- 未改変のフォントファイルを本プロジェクトに同梱・再配布することは OFL-1.1 のもとで許可されています（フォント単体販売は不可）。
- 改変（サブセット化・合成など）を行う場合は Reserved Font Name を使用できません。別名にリネームして配布してください。
- 電子出版物や PDF などへの埋め込みは許可されています。

### Noto Serif JP
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://fonts.google.com/noto/specimen/Noto+Serif+JP
- Copyright: (c) 2012 Google Inc. All Rights Reserved.
- License Text: included at `stylesheets/fonts/Noto_Serif_JP/OFL.txt`

Notes:
- `stylesheets/fonts/Noto_Serif_JP/NotoSerifJP-VariableFont_wght.ttf` をバンドルし、本文用フォントなどに利用しています。
- ライセンスの参考訳は `stylesheets/fonts/Noto_Serif_JP/OFL-ja.md` に記載しています。

### Noto Sans JP
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://fonts.google.com/noto/specimen/Noto+Sans+JP
- Copyright: (c) 2014-2021 Adobe (http://www.adobe.com/) with Reserved Font Name "Source"
- License Text: included at `stylesheets/fonts/Noto_Sans_JP/OFL.txt`

Notes:
- `stylesheets/fonts/Noto_Sans_JP/NotoSansJP-VariableFont_wght.ttf` をバンドルし、ノンブル等の sans-serif 体に使用しています。
- ライセンスの参考訳は `stylesheets/fonts/Noto_Sans_JP/OFL-ja.md` に記載しています。

### Zen Maru Gothic
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://fonts.google.com/specimen/Zen+Maru+Gothic
- Copyright: 2021 The Zen Maru Gothic Project Authors
- License Text: included at `stylesheets/fonts/Zen_Maru_Gothic/OFL.txt`

Notes:
- `stylesheets/fonts/Zen_Maru_Gothic/ZenMaruGothic-Regular.ttf` および `.../ZenMaruGothic-Bold.ttf` をバンドルし、本文・見出しのゴシック体に使用しています。
- ライセンスの参考訳は `stylesheets/fonts/Zen_Maru_Gothic/OFL-ja.md` に記載しています。

### Keyboard JP
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://github.com/n-yuji/keyboard-font
- Copyright: (c) 2016 Yuji Nakata
- License Text: https://github.com/n-yuji/keyboard-font/blob/master/LICENSE

Notes:
- `stylesheets/fonts/Keyboard-JP-Regular.otf` をキーボード表記向けフォントとして同梱しています。
