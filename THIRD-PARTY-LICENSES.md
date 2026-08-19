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

## SudachiDict
- License: Apache License, Version 2.0
- Project: https://github.com/WorksApplications/SudachiDict
- Copyright: (c) 2017-2023 Works Applications Co., Ltd.
- License Text: `LICENSE-APACHE-2.0.txt` (bundled) / https://www.apache.org/licenses/LICENSE-2.0

Notes:
- `lib/vivlio_starter/cli/lint/data/mazegaki.tsv` is a derived work, extracted and filtered from the normalized-form field of SudachiDict. It is used by `vs lint` to detect mixed kana-kanji spellings.
- The upstream data (`mazegaki-source.tsv`) and the script that derives the shipped file (`filter.rb`) sit next to it in the same directory.
- SudachiDict itself bundles UniDic (BSD 3-Clause) and parts of mecab-unidic-NEologd (Apache-2.0). Their notices are reproduced verbatim below, as required by section 4(d).

### 参考訳（日本語・非公式）
- ライセンス: Apache License, Version 2.0
- プロジェクト: https://github.com/WorksApplications/SudachiDict
- 著作権表示: (c) 2017-2023 Works Applications Co., Ltd.
- ライセンス本文: `LICENSE-APACHE-2.0.txt`（同梱）／ https://www.apache.org/licenses/LICENSE-2.0

補足:
- `lib/vivlio_starter/cli/lint/data/mazegaki.tsv` は、SudachiDict の「正規化表記」フィールドから抽出・加工した派生物です。`vs lint` の交ぜ書き検出（第 2 層）で使用します。
- 元データ（`mazegaki-source.tsv`）と、出荷用ファイルを生成するスクリプト（`filter.rb`）は同じディレクトリに置いてあります。
- 第 4 条 (b) が求める改変内容の一覧と、第 4 条 (d) が求める帰属表示（UniDic・NEologd）を、以下に原文のまま収録します。

### 帰属表示と改変内容（Apache License 2.0 第 4 条 (b)(d)）

```text
================================================================================
交ぜ書き訂正辞書（mazegaki.tsv）のライセンス表示
================================================================================

このディレクトリに含まれる mazegaki.tsv は、SudachiDict の「正規化表記」
フィールドから抽出・加工して作成した派生物です。

Vivlio Starter 本体は MIT License ですが、mazegaki.tsv には
Apache License, Version 2.0 が適用されます。


--------------------------------------------------------------------------------
1. 一次著作物
--------------------------------------------------------------------------------

  SudachiDict
  Copyright (c) 2017-2023 Works Applications Co., Ltd.
  https://github.com/WorksApplications/SudachiDict

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

  Apache License 2.0 の全文は、プロジェクトルートの LICENSE-APACHE-2.0.txt に
  収録しています。

  使用した辞書:
    - SudachiDict small (small_lex.csv 由来)  … 出典列 "SudachiDict-small"
    - SudachiDict core  (core_lex.csv 由来)   … 出典列 "SudachiDict-core"


--------------------------------------------------------------------------------
2. 改変の内容（Apache License 2.0 第4条(b)に基づく表示）
--------------------------------------------------------------------------------

mazegaki.tsv は SudachiDict の原データそのものではありません。
以下の加工を行っています。

  a. SudachiDict のシステム辞書から、各エントリの「表記」「正規化表記」
     「読み」「品詞」の4項目のみを抽出した。
  b. 正規化表記が表記と一致するエントリを除外した。
  c. 固有名詞、記号、補助記号、空白、助詞、助動詞、接頭辞、接尾辞、
     代名詞、感動詞、連体詞、接続詞のエントリを除外した。
  d. 活用形が「終止形-一般」「語幹-一般」「*」以外のエントリを除外した。
  e. カタカナ表記の見出し語を除外した。
  f. 見出し語に含まれる漢字が、すべて正規化表記にも含まれるエントリのみを
     採用した。
  g. 見出し語の仮名数が正規化表記の仮名数を上回り、かつ見出し語の異なり
     漢字数が正規化表記のそれを下回るエントリのみを採用した。
  h. 見出し語と正規化表記の文字数差が4を超えるエントリを除外した。
  i. 独自の分類列「種別」（交ぜ書き／かな書き）を追加した。
  j. 独自の「備考」列を追加し、動詞・形容詞のうち見出し語と正規化表記の
     末尾文字が一致しないものに「要確認」を付した。
  k. 独自の「出典」列を追加し、由来する SudachiDict の辞書種別を記録した。
  l. small 辞書に由来するエントリを基礎とし、core 辞書にのみ存在する
     エントリを差分として追加した。

  m. Vivlio Starter として、次の 3 エントリを削除した（2026-08-19）。

       まま       → 媽媽    「そのまま」「雛形のまま」に当たる（本書 200 万字で 401 件）。
                            生成分で、交ぜ書き表記がそのまま別語として読める型。
       障がい     → 障害    本プロジェクトは「障がい → 障碍」を採るため、行き先が逆になる。
                            「障害」を行き先に持つエントリは、複合語も含めて全部落とした
                            （障がい者・障がい者手帳・身体障がい者・精神障がい者・聴覚障がい者
                            ほか計 7 件）。1 語だけ残すと、そこから「害」の字が戻ってしまう。
       しょうがい → 障害    同上。
       障がい者   → 障害者  同上。「障がい者 → 障碍者」を採る。

  ※ 上記に加えて独自にエントリを追加・修正・削除した場合は、
     その旨をここに追記してください。


--------------------------------------------------------------------------------
3. SudachiDict が依拠する第三者データの表示
--------------------------------------------------------------------------------

SudachiDict は UniDic および NEologd の一部を含みます。
本データはその双方に由来するエントリを含むため、以下の表示を引き継ぎます。

--- 3-1. UniDic（small_lex.csv および core_lex.csv の基礎語彙）---------------

  UniDic
  https://unidic.ninjal.ac.jp/

  Copyright (c) 2011-2013, The UniDic Consortium
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met:

   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.

   * Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the
     distribution.

   * Neither the name of the UniDic Consortium nor the names of its
     contributors may be used to endorse or promote products derived
     from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

--- 3-2. NEologd（core_lex.csv に由来するエントリ）--------------------------

  mecab-unidic-neologd
  Copyright (C) 2015-2019 Toshinori Sato (@overlast)
  https://github.com/neologd/mecab-unidic-neologd

    i. 本データは、株式会社はてなが提供するはてなキーワード一覧ファイル
       中の表記、及び、読み仮名の大半を使用している。

       はてなキーワード一覧ファイルの著作権は、株式会社はてなにある。

       はてなキーワード一覧ファイルの使用条件に基づき、また、
       データ使用の許可を頂いたことに対する感謝の意を込めて、
       以下に株式会社はてなおよびはてなキーワードへの参照をURLで示す。

       株式会社はてな : http://hatenacorp.jp/information/outline

       はてなキーワード :
       http://developer.hatena.ne.jp/ja/documents/keyword/misc/catalog

   ii. 本データは、日本郵便株式会社が提供する郵便番号データ中の表記、
       及び、読み仮名を使用している。

       日本郵便株式会社は、郵便番号データに限っては著作権を主張しないと
       述べている。

       日本郵便株式会社の郵便番号データに対する感謝の意を込めて、
       以下に日本郵便株式会社および郵便番号データへの参照をURLで示す。

       日本郵便株式会社 :
         http://www.post.japanpost.jp/about/profile.html

       郵便番号データ :
         http://www.post.japanpost.jp/zipcode/dl/readme.html

  iii. 本データは、スナフキん氏が提供する日本全国駅名一覧中の表記、及び
       読み仮名を使用している。

       日本全国駅名一覧の著作権は、スナフキん氏にある。

       スナフキん氏は 「このデータを利用されるのは自由ですが、その際に
       不利益を被ったりした場合でも、スナフキんは一切責任は負えません
       ことをご承知おき下さい」と述べている。

       スナフキん氏に対する感謝の意を込めて、
       以下に日本全国駅名一覧のコーナーへの参照をURLで示す。

       日本全国駅名一覧のコーナー :
         http://www5a.biglobe.ne.jp/~harako/data/station.htm

   iv. 本データは、工藤拓氏が提供する人名(姓/名)エントリデータ中の、
       漢字表記の姓・名とそれに対応する読み仮名を使用している。

       人名(姓/名)エントリデータは被災者・安否不明者の人名の
       表記揺れ対策として、Mozcの人名辞書を活用できるという
       工藤氏の考えによって提供されている。

       工藤氏に対する感謝の意を込めて、
       以下にデータ本体と経緯が分かる情報への参照をURLで示す。

       人名(姓/名)エントリデータ :
         http://chasen.org/~taku/software/misc/personal_name.zip

       上記データが提供されることになった経緯
         http://togetter.com/li/111529

    v. 本データは、Web上からクロールした大量の文書データから抽出した
       表記とそれに対応する読み仮名のデータを含んでいる。

       抽出した表記とそれに対応する読み仮名の組は、上記の i. から iv.
       の言語資源の組み合わせによって得られる組のみを採録した。

       Web 上に文書データを公開して下さっている皆様に感謝いたします。

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

================================================================================
```
