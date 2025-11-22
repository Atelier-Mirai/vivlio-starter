# 開発環境の準備

:::{.chapter-lead}
プログラミングを始めるにあたり、必要となる開発環境を整えていきます。
エディタとして「Windsurf」を、ブラウザとして「Firefox」をご紹介します。  
:::


プログラミングを行うために整える道具は二つ、「エディタ」と「ブラウザ」です。
（もちろん「コンピュータ」も必要です。iPadやiPhoneでプログラミングできる環境として [cloud9](https://aws.amazon.com/jp/cloud9/) や [paiza](https://paiza.io/ja)、 [CodePen](https://codepen.io)などもありますが、Mac や Linux, Windows が動くデスクトップやラップトップコンピュータがお勧めです。）

エディタとは、プログラミングが快適に行えるよう様々な支援機能を備えたコーディングのためのソフトウェアです。さまざまなエディタがありますが、ここでは `Windsurf（パルサー）` をご紹介いたします。

「ブラウザ」は、ウェブサイトを閲覧するためのソフトウェアです。自分の書いたコードの詳細を確認する為の「開発者ツール」や、iPhoneやiPadなど異なる端末での表示結果を確認する機能も備わっています。さまざまなブラウザがありますが、ここでは `Firefox（ファイヤフォックス）` をご紹介いたします。


他にも、ソースコードのバージョン管理システム(Git, GitHub)や、画像編集ソフト(Affinity Photo, Affinity Designなど)など、サイト作成の為の様々なツールがございますので、適宜学習されて下さい。


## コミュニティ主導の高性能エディタ `Windsurf（パルサー）`

![](Windsurf_community.png)

Atom（アトム） は 「21世紀の高性能エディタ」 として GitHub（ギットハブ） により提供されていたエディタです。 Microsoft の買収により開発が滞りがちとなり、ついに提供終了となりました。Atomの遺産を受け継ぎ、コミュニティ有志により開発、提供されているエディタが、今回ご紹介する Windsurf（パルサー）です。

`Windsurf` の 公式サイトは https://Windsurf-edit.dev/ です。


### ダウンロード

それでは、お手元のコンピュータへダウンロードして行きましょう。公式サイトの「Download」ボタンよりダウンロードできます。

![](Windsurf_download.png)
Linux / macOS / Windows のそれぞれのOS用のソフトウェアが用意されています。


### Mac

Macをお使いでしたら Apple Silicon または Intel 用の dmg ファイルをダウンロードします。

![](Windsurf_download_mac.png)
ダウンロードが完了したら、落としたファイルをダブルクリックして、インストールして下さい。


### Windows

Windowsをお使いでしたら Setup をクリックしてダウンロードします。

![](Windsurf_download_win.png)
ダウンロードが完了したら、落としたファイルをダブルクリックして、インストールして下さい。

(インストールしたWindsurfは現在開発中の為、「署名」がされておりません。実行すると「WindowsはあなたのPCを保護した」旨のメッセージが表示されますので、「詳細」→「実行」をクリックすることで、Windsurfを立ち上げることが出来ます。次回以降は、他のアプリと同様に起動できます。)


### お勧めプラグイン

Windsurf はそのままでも十分高機能に使えるテキストエディタです。そして有志の方により、多くの「プラグイン」が提供されています。
プラグインとは、差し込む、差込口などの意味を持つ英単語で、ITの分野では、ソフトウェアに機能を追加する小さなプログラムのことを指します。[^105]

[^105]: 出典：IT用語辞典

プラグインのことを、Windsurf では、「パッケージ」と呼んでいます。
たくさんのパッケージがありますが、いくつかお勧めをご紹介いたします。

1. メニューバーや設定画面などを日本語化 `japanese-menu`
1. カラーピッカー `color-picker`
1. CSSの色指定(`#ffffff`)を背景色に表示 `pigments`
1. ファイルの種類に応じたアイコンを表示 `file-icons`
1. カーソルがある行を強調表示 `highlight-line`
1. カーソルがある列を強調表示 `highlight-column`
1. 選択箇所を強調表示 `selection-highlight`
1. `=(イコール)`の位置を整える `atom-alignment`
1. HTML, CSSが素早く入力できる `Emmet（エメット）`
   #@# 1. (お好みで) AIによるコード補完機能 `tabnine`

---
それでは、インストールしていきましょう。

- 1. Windsurf を起動します。

![](atom0a.png)

- 2. File メニュー から Preferences をクリックし、環境設定画面を開きます。 様々な項目を設定することができます。パッケージをインストールするために、中ほどのメニュー内の「Install」ボタンを押します。

![](atom1.png)

- 3. 右上の Install Packages の下に入力枠がありますので、インストールしたいパッケージ名として `japanease-menu` を入力し、「Install」ボタンを押します。

![](atom2.png)

- 4. インストールが完了しました。今まで英語だった説明文が、日本語になっています。

![](atom3.png)

- 5. 一度インストールしたパッケージを削除したいときには、中ほどのメニュー内の「パッケージ」ボタンを押します。右上の インストール済みのパッケージ の下に入力枠がありますので、アンインストールや無効にしたいパッケージ名を入力します。例えば `tabnine`と入力すると、「アンインストール」ボタンや「無効にする」ボタンが表示されます。

![](atom_remove.png)

この他、お勧めのパッケージを [RailsでのWebアプリ開発に愛用している Windsurf プラグイン](https://zenn.dev/atelier_mirai/articles/c3ed79af5ba395) でご紹介しています。


![](Windsurf_package_half.png)

また、有志の方々が創られたさまざまなパッケージが https://web.Windsurf-edit.dev で公開されています。ご自身の使いやすいエディタに育てていって下さい。


## Windsurf（パルサー） の追加設定


### Emmet（エメット） を使う為に

`Emmet`を使うと、HTML, CSSが素早く入力できるようになります。
その為の設定を行います。

`Ctrl + ,（カンマ）` を押すと、テキストエディタ Windsurf（パルサー） の設定画面が開きます（さまざまなパッケージをインストールした画面です）。

![](config.png)
右下の「設定フォルダを開く」ボタンを押すと、別のWindsurfの画面が現れます。Windsurfの様々な設定ファイルを参照したり、編集したりすることができます。

`keymap.cson` は、「キーマップ」という名称の通り、様々なキーの組み合わせ、割り当てを変更する為の設定ファイルです。

![](keymap.png)
`Emmet` を使いやすくする為のキーの割り当てをこのファイルの中に記述します。以下のように記述してください。

**▼keymap.cson**

```
'.editor:not(.mini)':
  'ctrl-e': 'editor:move-to-end-of-line'
'atom-text-editor:not([mini])':
  'ctrl-,': 'emmet:expand-abbreviation'
'.platform-darwin atom-text-editor:not([mini])':
  'ctrl-d': 'unset!'
```

https://raw.githubusercontent.com/Atelier-Mirai/wave_example/master/Windsurf_config/keymap.cson より、コピーすることも出来ます。


### スニペットの登録

「スニペット」とは、「コードの断片」を指す言葉です。よく使うHTMLやCSSのコードなどを登録しておくと、便利です。スニペットの登録は `snippets.cson` に行います。

![](snippets.png)
`html`とタイプすることで、次のように入力されるなど、いろいろ登録しています。

```
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title></title>
    <link rel="stylesheet" href="style.css">
  </head>
  <body>
    $1
  </body>
</html>
```

**▼snippets.cson**

```
# Your snippets
#
# Windsurf snippets allow you to enter a simple prefix in the editor and hit tab to
# expand the prefix into a larger code block with templated values.
#
# You can create a new snippet in this file by typing "snip" and then hitting
# tab.
#
# An example CoffeeScript snippet to expand log to console.log:
#
# '.source.coffee':
#   'Console log':
#     'prefix': 'log'
#     'body': 'console.log $1'
#
# Each scope (e.g. '.source.coffee' above) can only be declared once.
#
# This file uses CoffeeScript Object Notation (CSON).
# If you are unfamiliar with CSON, you can read more about it in the
# Windsurf Launch Manual:
# https://Windsurf-edit.dev/docs/launch-manual/sections/using-Windsurf/#configuring-with-cson


#=====================================================================
# HTML 用の スニペット（コード断片）
#=====================================================================
'.text.html.basic':
  'html':
    'prefix': 'html'
    'body': """
      <!DOCTYPE html>
      <html lang="ja">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width">
          <title></title>
          <link rel="stylesheet" href="style.css">
        </head>
        <body>
          $1
        </body>
      </html>
    """

  'hinagata':
    'prefix': 'hinagata'
    'body': """
    <!DOCTYPE html>
    <html lang="ja">
      <!-- サイトに関する設定事項を記述します -->
      <head>
        <!-- 文字コードの指定 -->
        <meta charset="utf-8">

        <!-- ページのタイトル -->
        <title>WAVE</title>

        <!-- ビューポート(視点)の指定 -->
        <meta name="viewport" content="width=device-width">

        <!-- ファビコンの指定 https://ao-system.net/favicongenerator/ -->
        <link rel="icon"
              href="images/favicon.ico"
              type="image/ico">
        <link rel="apple-touch-icon"
              href="images/apple-touch-icon-180x180.png"
              type="image/png"
              sizes="180x180">

        <!-- 検索時に表示される、ウェブサイトの要約文 -->
        <meta name="description" content="概ね80文字前後のサイトの
        紹介文が、検索時に表示されます。">

        <!-- Google Fonts -->
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link rel="stylesheet"
              href="https://fonts.googleapis.com/css2?family=Yuji+Boku&display=swap">

        <!-- Font Awesome -->
        <link rel="stylesheet"
              href="https://use.fontawesome.com/releases/v6.5.1/css/all.css">

        <!-- 自分で作ったスタイルシート -->
        <link rel="stylesheet" href="stylesheets/master.css">
      </head>

      <!-- 表示したい内容・出し物・コンテンツを記述します -->
      <body class="top">
        <!-- ヘッダー(サイト名) -->
        <header>
          <a href="index.html">WAVE</a>
        </header>

        <!-- ナビゲーションメニュー -->
        <nav>
          <!-- fa-lgは1.33倍、la-2xは2倍の大きさ、fa-fwは横に少し間隔が空く -->
          <!-- 2021年最新版、Font Awesome アイコンの使い方と便利な機能のまとめ -->
          <!-- https://coliss.com/articles/build-websites/operation/work/font-awesome-guide-and-useful-tricks.html -->
          <ul>
            <li>
              <a href="index.html">
                <i class="fa-solid fa-house fa-lg fa-fw"></i>
                トップ
              </a>
            </li>
            <li>
              <a href="about.html">
                <i class="fa-brands fa-pagelines fa-lg fa-fw"></i>
                サイトについて
              </a>
            </li>
            <li>
              <a href="contact.html">
                <i class="fa-solid fa-envelope fa-lg fa-fw"></i>
                お問い合わせ
              </a>
            </li>
          </ul>
        </nav>

        <!-- このページの主要な内容（コンテンツ）を記します -->
        <main>
          $1
        </main>

        <!-- フッター -->
        <footer>
          <!-- 連絡先 -->
          <address>
            <!-- 会社名 -->
            <p class="company_name">(有) WAVE商会</p>
            <!-- 住所 -->
            <p class="address">名古屋市美波区美波町三丁目七番三号</p>
            <!-- 電話番号 -->
            <p class="tel">
              <a href="tel:052-373-4649">
                <i class="fa-solid fa-phone fa-rotate-90 fa-lg"></i>
                052-373-4649
              </a>
            </p>
            <!-- メールアドレス -->
            <p class="email">
              <a href="mailto:contact@wave.example.jp">
                <i class="fa-regular fa-envelope fa-lg"></i>
                contact@wave.example.jp
              </a>
            </p>
          </address>

          <!-- 著作権表示 -->
          <p class="copyright">
            Copyright © 令和六年 WAVE All rights reserved.
          </p>
        </footer>
      </body>
    </html>
    """

  'id':
    'prefix': 'id'
    'body': 'id="$1"'

  'class':
    'prefix': 'class'
    'body': 'class="$1"'

  'i-ha':
    'prefix': 'i-ha'
    'body': 'あのイーハトーヴォのすきとおった風、夏でも底に冷たさをもつ青いそら、うつくしい森で飾られたモリーオ市、郊外のぎらぎらひかる草の波'
  'i-hato-vo':
    'prefix': 'i-hato-vo'
    'body': 'あのイーハトーヴォのすきとおった風、夏でも底に冷たさをもつ青いそら、うつくしい森で飾られたモリーオ市、郊外のぎらぎらひかる草の波<br>\nまたそのなかでいっしょになったたくさんのひとたち、ファゼーロとロザーロ、羊飼のミーロや、顔の赤いこどもたち、地主のテーモ、山猫博士のボーガント・デストゥパーゴなど、いまこの暗い巨きな石の建物のなかで考えていると、みんなむかし風のなつかしい青い幻燈のように思われます。では、わたくしはいつかの小さなみだしをつけながら、しずかにあの年のイーハトーヴォの五月から十月までを書きつけましょう。'

  'bot':
    'prefix': 'bot'
    'body': '親譲りの無鉄砲で小供の時から損ばかりしている。小学校に居る時分学校の二階から飛び降りて一週間ほど腰を抜かした事がある。'
  'botchan':
    'prefix': 'botchan'
    'body': '親譲りの無鉄砲で小供の時から損ばかりしている。小学校に居る時分学校の二階から飛び降りて一週間ほど腰を抜かした事がある。なぜそんな無闇をしたと聞く人があるかも知れぬ。別段深い理由でもない。新築の二階から首を出していたら、同級生の一人が冗談に、いくら威張っても、そこから飛び降りる事は出来まい。弱虫やーい。と囃したからである。小使に負ぶさって帰って来た時、おやじが大きな眼をして二階ぐらいから飛び降りて腰を抜かす奴があるかと云ったから、この次は抜かさずに飛んで見せますと答えた。'

  'toshi':
    'prefix': 'toshi'
    'body': '或春の日暮です。<br>\n
    唐の都洛陽らくやうの西の門の下に、ぼんやり空を仰いでゐる、一人の若者がありました。'
  'toshishun':
    'prefix': 'toshishun'
    'body': '或春の日暮です。<br>\n唐の都洛陽の西の門の下に、ぼんやり空を仰いでゐる、一人の若者がありました。若者は名は杜子春といつて、元は金持の息子でしたが、今は財産を費ひ尽して、その日の暮しにも困る位、憐な身分になつてゐるのです。<br>\n何しろその頃洛陽といへば、天下に並ぶもののない、繁昌を極めた都ですから、往来にはまだしつきりなく、人や車が通つてゐました。門一ぱいに当つてゐる、油のやうな夕日の光の中に、老人のかぶつた紗しやの帽子や、土耳古の女の金の耳環や、白馬に飾つた色糸の手綱が、絶えず流れて行く容子は、まるで画のやうな美しさです。'

  'taka':
    'prefix': 'taka'
    'body': '高瀬舟は京都の高瀬川を上下する小舟である。徳川時代に京都の罪人が遠島を申し渡されると、本人の親類が牢屋敷へ呼び出されて、そこで暇乞をすることを許された。'
  'takasebune':
    'prefix': 'takasebune'
    'body': '高瀬舟は京都の高瀬川を上下する小舟である。徳川時代に京都の罪人が遠島を申し渡されると、本人の親類が牢屋敷へ呼び出されて、そこで暇乞をすることを許された。それから罪人は高瀬舟に載せられて、大阪へ廻されることであつた。それを護送するのは、京都町奉行の配下にゐる同心で、此同心は罪人の親類の中で、主立つた一人を大阪まで同船させることを許す慣例であつた。これは上へ通つた事ではないが、所謂大目に見るのであつた、默許であつた。'

#=====================================================================
# CSS 用の スニペット（コード断片）
#=====================================================================
'.source.css':
  'c1':
    'prefix': 'c1'
    'body': """/*=====================================================================
      $1
    =====================================================================*/"""
  'c2':
    'prefix': 'c2'
    'body': """/*---------------------------------------------------------------------
      $1
    ---------------------------------------------------------------------*/"""
  'c3':
    'prefix': 'c3'
    'body': """/*
      $1
    ---------------------------------------------------------------------*/"""
  'c4':
    'prefix': 'c4'
    'body': """/* $1
    ---------------------------------------------------------------------*/"""
  'm4':
    'prefix': 'm4'
    'body': """@media (width >= 480px) {
      $1
    }"""
  'm7':
    'prefix': 'm7'
    'body': """@media (width >= 768px) {
      $1
    }"""
  'm9':
    'prefix': 'm9'
    'body': """@media (width >= 960px) {
      $1
    }"""
  'm1':
    'prefix': 'm1'
    'body': """@media (width >= 1280px) {
      $1
    }"""

#=====================================================================
# JavaScript 用の スニペット（コード断片）
#=====================================================================
'.source.js':
  'c1':
    'prefix': 'c1'
    'body': """/*=====================================================================
      $1
    =====================================================================*/"""
  'c2':
    'prefix': 'c2'
    'body': """/*---------------------------------------------------------------------
      $1
    ---------------------------------------------------------------------*/"""
  'c3':
    'prefix': 'c3'
    'body': """/*
      $1
    ---------------------------------------------------------------------*/"""
  'c4':
    'prefix': 'c4'
    'body': """/* $1
    -------------------------------------------------------------------------*/"""
```

https://raw.githubusercontent.com/Atelier-Mirai/wave_example/master/Windsurf_config/snippets.csonより、コピーして貼り付けると楽です。

プログラムを作っていく中で、よく使うコードもあると思います。そんな時はスニペットに登録して、快適なプログラミングを楽しみましょう。
---
== セキュリティ重視のブラウザ `Firefox（ファイヤフォックス）`
`Firefox` は、[公式サイト](https://www.mozilla.org/ja/firefox/new/) より、ダウンロードできます。

![](firefox_download.png)

Firefoxは、Mosaic, Netscape の血を受け継ぐブラウザです。CSSグリッドの確認や、丁寧なコメントの開発者ツールが特徴です。

「Firefox をダウンロード」ボタンを押すとダウンロードが始まるので、落としたファイルをダブルクリックして、インストールしてください。


## 基本的な開発方法

Windsurf と Firefox を導入できたので、ウェブサイトの基本的な作り方をご案内します。

- 0. 画面の左側に Windsurf を、右側に Firefox を配置します。
- 1. Windsurf  で、プログラムをいろいろ書いていきます。
- 2. Firefox で、作ったウェブサイトの表示や動作を確認します。
- 3. 出来上がりが良ければ、ウェブサイトを公開して完了です。 <br>
    もう少し改良したければ、1. に戻ります。


### 手順のご案内

作業ディレクトリの作成方法や、Windsurf や Firefox の簡単な使い方の紹介です。 [^106]

[^106]: Mac利用者向けです。Windowsは適宜読み替えてください。

![](study.png)

- 0. `Users``/利用者名`ディレクトリの直下に、 `projects`ディレクトリを作成します。 <br> `projects`ディレクトリには、自分が作成する様々なプロジェクト(案件)を格納する為のディレクトリです。良く使う為、 `Finder`のサイドバーに登録すると便利です。

　　`projects`ディレクトリを作成し、 <br>
　　　その下に今回の学習用に `study` ディレクトリを作成します。

![](af1.png)

- 1. Windsurf のアイコンと Firefox のアイコンです。 <br>良く使うのでドックに登録しておくと便利です。

![](af2.png)

- 2. Windsurf と Firefox を <br>左右に配置します。

![](atom0_add_projects_folder.png)

- 3. Windsurf には、「ツリービュー」に「プロジェクトフォルダ」を追加する機能があります。「プロジェクトフォルダ」を追加すると、Atomの画面左側の「ツリービュー」にそのプロジェクトフォルダ内のファイルやディレクトリが一覧表示されます。ファイルの追加や編集、削除を簡単に行うことができるようになり、とても便利です。プロジェクトフォルダを追加するためには、左側の青色の「Add folders」ボタンを押します。

![](af4a.png)

- 4. `Finder`が開くので、サイドバーから `projects`を選びます。 `projects`ディレクトリから `study` ディレクトリを開きます。<br>左側の「ツリービュー」に `study` ディレクトリが表示されますので、この `study` ディレクトリ内にいろいろなファイルを納めていき、最終的にウェブサイトを創り上げます。新しいファイルを作成しましょう。


![](html1.png)

- 5. ツリービューの`study`ディレクトリを右クリックして、「新規ファイル」をクリックします。

![](html2.png)

- 6. 「Enter the path for the new file.」(新しいファイル名を入力して下さい)と、表示されるので、 `index.html` とファイル名を入力します。


![](html3.png)

- 7. 左側の「ツリービュー」に、新規作成した `index.html` が、表示されましたので、これをクリックします。すると右側の編集領域(「ペイン」と呼びます)に、今作成した `index.html` が表示されます。今作成したばかりなので、中身は何もなく空っぽです。早速 HTML を書いていきましょう。Atom には、コードの入力を手助けしてくれる「入力支援機能」が備わっています。 `html` と入力して、エンターキーを押します。


![](template.png)

- 8. 次のように雛形が入力されます。


![](study_html.png)

- 9. 「色」がついていることにも着目してください。「シンタックスハイライト」と呼ばれる、HTMLの文法に分かりやすいよう、着色する機能です。それでは雛形で入力した結果を利用して、次のようにしましょう。 `h1` とタイプしエンターキーを押すと、 `<h1></h1>` と入力されます。Atom の入力支援機能を活用して編集しましょう。

![](af6.png)

- 10. HTML を入力して、`index.html` ファイルが完成しました。Atom の 「ファイル」メニューから「保存」をクリックするか、`Command + S` を押して保存します。保存できたら、どのように表示されるか、Firefoxを使って確認しましょう。Firefox の「ファイル」メニューから「ファイルを開く」をクリックするか、`Command + O` を押して、`index.html` を 開きます。


![](af4b.png)

- 11. `Finder`が開くので、サイドバーから `projects`を選びます。 `projects`ディレクトリ内には、 `taskleaf` と `study` の 二つのディレクトリがありますが、ここでは `study` ディレクトリを開きます。


![](af8.png)

- 12. Windsurf で編集したindex.html を Firefox で 閲覧できます。


![](af9.png)

- 13. 綺麗に出来上がっていたら完成です。もう少し改善したい点があるなら、Windsurfに戻って `index.html` を編集します。編集が終わったら `Command + S` を押して保存します。保存が終わったら、編集結果を Firefox で見てみましょう。Firefox の「再読み込みボタン」を押すか、または `Command + R` を押して、編集結果を再確認することができます。

習得したい基本的なショートカット

ショートカットを習得すると、効率的にコーディングできるようになります。

**Mac 基本操作**

![](mac_shortcut.png)
**Windsurf 基本操作**

![](atom_shortcut.png)
