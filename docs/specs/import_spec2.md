# import_spec.md に関する補足

1. vivlio-starter側の `contentes/*.md` には、Starter側の`*.re`ファイルを変換して配置される。
vs import コマンド内で、`scripts/review_to_vivlio_md.rb`相当の追従変換を実施しているが、さらに、次の変換操作も併せて実行せよ。


- codeブロック
<span class="caption">▼janken.css</span>

```
/* じゃんけんの説明文を対象に */
.note {
  grid-area: note;      /* computer領域に配置する */
  text-align: center;   /* 文字は中央揃えにする */
}
```

=>

```css:janken.css
/* じゃんけんの説明文を対象に */
.note {
  grid-area: note;      /* computer領域に配置する */
  text-align: center;   /* 文字は中央揃えにする */
}
```

- dl, dt, dd タグの変換
<dl>
<dt>コンピュータ</dt>
<dd>
    なんといってもコンピュータの代表です。いろいろなウェブサイトを見たり、書類作成などお仕事に活用したり、そして「プログラミング」など。
</dd>
<dt>衣服</dt>
<dd>
    「天衣無縫」-「天人や天女の着物には縫い目がないという意から、詩文などが、よけいな修飾がなく、自然でわざとらしくなく完成されていること。また、人柄が純真で素直で、まったく嫌みがないさま。物事が完全無欠であることの形容(goo辞書)」
    衣食住は、人が生きる上で生活の基盤となる要素です。大麻、木綿、絹糸、古（いにしえ）の昔から日本人の身を纏（まと）う衣服に用いられてきました。
</dd>
</dl>

=>

- **コンピュータ**
    なんといってもコンピュータの代表です。いろいろなウェブサイトを見たり、書類作成などお仕事に活用したり、そして「プログラミング」など。

- **衣服**
    「天衣無縫」-「天人や天女の着物には縫い目がないという意から、詩文などが、よけいな修飾がなく、自然でわざとらしくなく完成されていること。また、人柄が純真で素直で、まったく嫌みがないさま。物事が完全無欠であることの形容(goo辞書)」  
    衣食住は、人が生きる上で生活の基盤となる要素です。大麻、木綿、絹糸、古（いにしえ）の昔から日本人の身を纏（まと）う衣服に用いられてきました。

※ 文末の `goo辞書)」\n`のあとを`goo辞書)」\n  `(半角スペース2つ)を挿入し、別々の文章として認識させるようにする。

- table タグの変換

<div class="table">
<p class="caption">じゃんけんの勝敗表</p>
<table>
<tr class="hline"><th></th><th>グー   0</th><th>チョキ 1</th><th>パー   2</th></tr>
<tr class="hline"><td>グー   0</td><td>相子</td><td>勝ち</td><td>負け</td></tr>
<tr class="hline"><td>チョキ 1</td><td>負け</td><td>相子</td><td>勝ち</td></tr>
<tr class="hline"><td>パー   2</td><td>勝ち</td><td>負け</td><td>相子</td></tr>
</table>
</div>

=>

**じゃんけんの勝敗表**

|      | グー 0 | チョキ 1 | パー 2 |
| ---- | ------ | -------- | ------ |
| グー 0 | 相子 | 勝ち | 負け |
| チョキ 1 | 負け | 相子 | 勝ち |
| パー 2 | 勝ち | 負け | 相子 |

※ 独自実装するほか、nokogiri、reverse_markdown を用いても良い(外部gemを利用する場合、vs doctorコマンドの自動インストール機能へも追加すること)。クラス名は破棄して良い。

<div class="table table-nohline">
<table>
<tr class="hline"><th>記述例</th><th> 説明</th></tr>
<tr class="hline"><td>`<!-- コメント --> `</td><td> コメント</td></tr>
</table>
</div>

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<html>`</td><td> HTML 文書においてルート (基点) となる要素 (トップレベル要素) であり、ルート要素とも呼ばれます。他の全ての要素は、この要素の子孫として配置します。</td></tr>
</table>
</div>

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<head>`</td><td> 文書に関する機械可読な情報 (metadata)、たとえば題名、スクリプト、スタイルシートなどを含みます。</td></tr>
<tr class="hline"><td>`<link>`</td><td> 外部リソースへのリンク要素です。現在の文書と外部のリソースとの関係を指定します。この要素はCSSへのリンクに最もよく使用されますが、サイトのアイコン (favicon スタイルのアイコンと、モバイル端末のホーム画面やアプリのアイコンの両方) の確立や、その他のことにも使用されます。</td></tr>
<tr class="hline"><td>`<meta>`</td><td> 他のメタ関連要素 (base / link / script / style / title) で表すことができない任意のmetadataを提示します。</td></tr>
<tr class="hline"><td>`<style>`</td><td> 文書あるいは文書の一部分のスタイル情報を含みます。</td></tr>
<tr class="hline"><td>`<title>`</td><td> 題名要素です。ブラウザのタイトルバーやページのタブに表示される文書の題名を定義します。</td></tr>
</table>
</div>

これらも、クラス名は破棄して良いので、マークダウン形式の表に変換せよ。`<head>` など、`(バッククォート)を付けているhtmlタグは、そのまま残すが、誤って解釈されることのないよう、`<`を`&lt;`、`>`を`&gt;`に置換する。


- るびへの変換

民は督促（とくそく）もされない
=>
民は{督促|とくそく}もされない

当初は紅殻（ベンガラ）など

=>

当初は紅殻（ベンガラ）など

※ ふりがなは直前の漢字達に付けられるものと限定して良い。これにより{民は督促|とくそく}のように、ふりがなの開始位置が不明となる事態を防止できる。ふりがなを「カタカナ」で付けている場合も同様に処理する。


- 画像パス名の破棄
![](./images/31-netlify/netlify20.png)

=>

![](netlify20.webp)


2. `starter/*.yml` を `vivlio-starter/config/*.yml` へ取り込む際、vivlio-starter のコメントは残すようにせよ。

3. vivlio-starter/images/ に配置する画像は、変換後の webp 画像のみで良い（元のjpg / gif / png は削除してよい）

4. あらかじめ 利用者が starter側で rake markdown を実行することは期待できないので、vs import コマンド内で自動で実行する。

5. rake markdown を実行すると starter/janken-md/ディレクトリが作成されるが、これはimportしようとするreview starterプロジェクトによって生成されるディレクトリ名が異なる。
starter/config.yml内の bookname: janken に、`-md` を付加して、`janken-md` となったディレクトリ名が、rake markdown コマンドで生成されるディレクトリ名である。
異なるプロジェクトであっても、import出来るようにせよ。

6. import作業が終了したら、janken-md/ディレクトリを削除する。

7. Starter の `config.yml` から値を抽出し、 vivlio-starter の `book.yml` に投入する。

import_spec.mdでは、キーの指定に誤りがあったので、以下のように修正する。

| Starter キー | vivlio-starter キー | 備考 |
| --- | --- | --- |
| `booktitle` | `book.main_title` |  |
| `subtitle` | `book.subtitle` |  |
| `language` | `book.language` |  |
| `bookname` | `project.name` |  |
| `aut` | `book.author` |  |
| `additional.key: 発行者` | `book.publisher` | 値のみを移す |
| `additional.key: 連絡先` | `book.contact` | メールアドレスのみ |
| `history[0]` | `book.release` | 最初の履歴を採用 |
| `pubevent_name` | `book.series` |  |

