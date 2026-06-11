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

### Zen Old Mincho
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://fonts.google.com/specimen/Zen+Old+Mincho
- Source: https://github.com/googlefonts/zen-oldmincho
- Copyright: 2021 The Zen Old Mincho Project Authors
- License Text: https://openfontlicense.org/open-font-license-official-text/

Notes:
- `stylesheets/fonts/Zen_Old_Mincho/ZenOldMincho-Regular.ttf` および `.../ZenOldMincho-Bold.ttf` をバンドルし、本文用の明朝体（CSS ファミリ名 "Noto Serif JP" の実体）として使用しています。
- Chromium が CFF ベース OTF / 可変フォントを Type 3 として PDF に埋め込む問題を避けるため、TrueType アウトラインの静的 TTF を採用しています。

### Zen Kaku Gothic New
- License: SIL Open Font License 1.1 (OFL-1.1)
- Project: https://fonts.google.com/specimen/Zen+Kaku+Gothic+New
- Source: https://github.com/googlefonts/zen-kakugothic
- Copyright: 2021 The Zen Kaku Gothic Project Authors
- License Text: https://openfontlicense.org/open-font-license-official-text/

Notes:
- `stylesheets/fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Regular.ttf` および `.../ZenKakuGothicNew-Bold.ttf` をバンドルし、見出し・ノンブル等のゴシック体（CSS ファミリ名 "Noto Sans JP" の実体）として使用しています。

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

## スペルチェック辞書 (Spellcheck Dictionaries)

### cspell-dicts（技術用語辞書）
- License: MIT
- Project: https://github.com/streetsidesoftware/cspell-dicts
- Copyright: (c) Street Side Software
- License Text: https://opensource.org/licenses/MIT

以下の辞書ファイルを `config/spellcheck_dictionaries/` に同梱しています:

```
aws, bash-words, basic, cobol, coding-compound-terms, computing-acronyms,
cpp, csharp, css, django, docker, dotnet, fonts, fortran, git, go,
html, java-additional-terms, java-terms, javascript, kotlin, latex,
networkingTerms, node, npm, objective-c, php, placeholder-words,
python-common, ruby, rust, scala, smalltalk, software-tools,
softwareTerms, sql-common-terms, sql, swift, tsql, webServices
```

### 参考訳（日本語・非公式）
- ライセンス: MIT
- プロジェクト: https://github.com/streetsidesoftware/cspell-dicts
- 著作権表示: (c) Street Side Software
- ライセンス本文: https://opensource.org/licenses/MIT

補足:
- 上記辞書ファイルは cspell-dicts リポジトリから取得し、スペルチェック機能に使用しています。
- 各辞書ファイルのライセンスは MIT です。

---

### SCOWL（英単語辞書）
- License: MIT (SCOWL and Friends)
- Project: http://wordlist.aspell.net/
- Source: https://github.com/en-wl/wordlist
- Copyright: (c) 2000-2018 Kevin Atkinson

以下のファイルを `config/spellcheck_dictionaries/` に同梱しています:

```
english-words-10.txt, english-words-20.txt
```

### 参考訳（日本語・非公式）
- ライセンス: MIT（SCOWL and Friends）
- プロジェクト: http://wordlist.aspell.net/
- ソース: https://github.com/en-wl/wordlist
- 著作権表示: (c) 2000-2018 Kevin Atkinson

補足:
- `english-words-10.txt` および `english-words-20.txt` は SCOWL（Spell Checker Oriented Word Lists）から生成された一般英単語リストです。
- ライセンスは MIT です。

---

### 自作辞書（Vivlio Starter 独自）
- License: MIT
- Copyright: (c) Atelier Mirai

以下のファイルを `config/spellcheck_dictionaries/` に同梱しています:

```
abbreviations.txt, brand-names.txt, companies-dict.txt, css-properties.txt,
error-messages.txt, famous-people.txt, math-terms.txt, network-terms.txt,
products.txt, tech-terms.txt
```

### 参考訳（日本語・非公式）
- ライセンス: MIT
- 著作権表示: (c) Atelier Mirai

補足:
- 上記ファイルは本プロジェクト向けに独自に作成した辞書です。略語・ブランド名・著名人名・CSS プロパティ・技術用語・数学用語・ネットワーク用語・エラーメッセージ・製品名を収録しています。

## Twemoji（絵文字 SVG 画像）

### コード
- License: MIT
- Project: https://github.com/twitter/twemoji
- Copyright: (c) 2021 Twitter
- License Text: https://opensource.org/licenses/MIT

### グラフィックス（SVG ファイル）
- License: CC BY 4.0 (Creative Commons Attribution 4.0 International)
- Copyright: (c) Twitter, Inc and other contributors
- License Text: https://creativecommons.org/licenses/by/4.0/

Notes:
- `stylesheets/twemoji/` 配下の SVG ファイルは、公式リポジトリ twitter/twemoji v14.0.2 の `assets/svg/` から取得しています。
- Techbook モード（`output.pdf.techbook: true`）で、カラー絵文字を SVG 画像に差し替える際に使用します。
- CC BY 4.0 に基づき、書籍のリーガルページ（`legal.twemoji`）にクレジット表記を行います。

### 参考訳（日本語・非公式）

#### コード
- ライセンス: MIT
- プロジェクト: https://github.com/twitter/twemoji
- 著作権表示: (c) 2021 Twitter
- ライセンス本文: https://opensource.org/licenses/MIT

#### グラフィックス（SVG ファイル）
- ライセンス: CC BY 4.0（クリエイティブ・コモンズ 表示 4.0 国際）
- 著作権表示: (c) Twitter, Inc and other contributors
- ライセンス本文: https://creativecommons.org/licenses/by/4.0/

補足:
- `stylesheets/twemoji/` 配下の SVG ファイルは、公式リポジトリ twitter/twemoji v14.0.2 から取得した絵文字画像です。
- Techbook モードでカラー絵文字を印刷品質の SVG に差し替える目的で同梱しています。
- CC BY 4.0 の帰属表示義務を満たすため、書籍のリーガルページにクレジットを記載してください（`book.yml` の `legal.twemoji` で設定）。
