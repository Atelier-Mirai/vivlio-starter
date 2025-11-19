= 開発環境の準備

//abstract{
  プログラミングを始めるにあたり、必要となる開発環境を整えていきます。
  エディタとして「Pulsar」を、ブラウザとして「Firefox」をご紹介します。
//}
#@#
プログラミングを行うために整える道具は二つ、「エディタ」と「ブラウザ」です。
@<small>{（もちろん「コンピュータ」も必要です。iPadやiPhoneでプログラミングできる環境として @<href>{https://aws.amazon.com/jp/cloud9/, cloud9} や @<href>{https://paiza.io/ja, paiza}、 @<href>{https://codepen.io,CodePen}などもありますが、Mac や Linux, Windows が動くデスクトップやラップトップコンピュータがお勧めです。）}

エディタとは、プログラミングが快適に行えるよう様々な支援機能を備えたコーディングのためのソフトウェアです。さまざまなエディタがありますが、ここでは @<code>{@<ruby>{Pulsar,パルサー}} をご紹介いたします。

「ブラウザ」は、ウェブサイトを閲覧するためのソフトウェアです。自分の書いたコードの詳細を確認する為の「開発者ツール」や、iPhoneやiPadなど異なる端末での表示結果を確認する機能も備わっています。さまざまなブラウザがありますが、ここでは @<code>{@<ruby>{Firefox,ファイヤフォックス}} をご紹介いたします。

//blankline
@<small>{他にも、ソースコードのバージョン管理システム(Git, GitHub)や、画像編集ソフト(Affinity Photo, Affinity Designなど)など、サイト作成の為の様々なツールがございますので、適宜学習されて下さい。}

== コミュニティ主導の高性能エディタ @<code>{@<ruby>{Pulsar,パルサー}}

//sideimage[pulsar_community][50mm][sep=5mm, side=R]{
@<ruby>{Atom,アトム} は 「21世紀の高性能エディタ」 として @<ruby>{GitHub,ギットハブ} により提供されていたエディタです。 Microsoft の買収により開発が滞りがちとなり、ついに提供終了となりました。Atomの遺産を受け継ぎ、コミュニティ有志により開発、提供されているエディタが、今回ご紹介する @<ruby>{Pulsar,パルサー}です。

@<code>{Pulsar} の 公式サイトは @<href>{https://pulsar-edit.dev/} です。
//}

=== ダウンロード

それでは、お手元のコンピュータへダウンロードして行きましょう。公式サイトの「Download」ボタンよりダウンロードできます。

//image[pulsar_download][][width=85%]

Linux / macOS / Windows のそれぞれのOS用のソフトウェアが用意されています。
---
=== Mac
Macをお使いでしたら Apple Silicon または Intel 用の dmg ファイルをダウンロードします。
//image[pulsar_download_mac][][width=85%]

ダウンロードが完了したら、落としたファイルをダブルクリックして、インストールして下さい。

=== Windows
Windowsをお使いでしたら Setup をクリックしてダウンロードします。
//image[pulsar_download_win][][width=85%]

ダウンロードが完了したら、落としたファイルをダブルクリックして、インストールして下さい。

@<small>{(実行すると「WindowsはあなたのPCを保護した」旨のメッセージが表示されます。「詳細」→「実行」をクリックすることで、Pulsarを起動出来ます。次回以降は、他のアプリと同様に起動できます。)}

=== お勧めプラグイン
Pulsar はそのままでも十分高機能に使えるテキストエディタです。そして有志の方により、多くの「プラグイン」が提供されています。
プラグインとは、差し込む、差込口などの意味を持つ英単語で、ITの分野では、ソフトウェアに機能を追加する小さなプログラムのことを指します。@<fn>{1}
//footnote[1][出典：IT用語辞典]

プラグインのことを、Pulsar では、「パッケージ」と呼んでいます。
たくさんのパッケージの中からお勧めをご紹介いたします。

 1. メニューバーや設定画面などを日本語化 @<code>{japanese-menu}
 1. カラーピッカー @<code>{color-picker}
 1. CSSの色指定(@<code>{#ffffff})を背景色に表示 @<code>{pigments}
 1. ファイルの種類に応じたアイコンを表示 @<code>{file-icons}
 1. 自動再読み込み機能を備えた小さな開発サーバー@<code>{atom-live-server-plus}
 1. カーソルがある行を強調表示 @<code>{highlight-line}
 1. カーソルがある列を強調表示 @<code>{highlight-column}
 1. 選択箇所を強調表示 @<code>{selection-highlight}
 1. @<code>{=(イコール)}の位置を整える @<code>{atom-alignment}
 1. HTML, CSSが素早く入力できる @<code>{@<ruby>{Emmet,エメット}}

それでは、インストールしていきましょう。

 - 1. Pulsar を起動します。
//image[atom0a][][width=65%]

 - 2. File メニュー から Preferences をクリックし、環境設定画面を開きます。 様々な項目を設定することができます。パッケージをインストールするために、中ほどのメニュー内の「Install」ボタンを押します。
//image[atom1][][width=65%]

 - 3. 右上の Install Packages の下に入力枠がありますので、インストールしたいパッケージ名として @<code>{japanease-menu} を入力し、「Install」ボタンを押します。
//image[atom2][][width=65%]

 - 4. インストールが完了しました。今まで英語だった説明文が、日本語になっています。
//image[atom3][][width=65%]

 - 5. 一度インストールしたパッケージを削除したいときには、中ほどのメニュー内の「パッケージ」ボタンを押します。右上の インストール済みのパッケージ の下に入力枠がありますので、アンインストールや無効にしたいパッケージ名を入力します。例えば @<code>{tabnine}と入力すると、「アンインストール」ボタンや「無効にする」ボタンが表示されます。
//image[atom_remove][][width=65%]

//blankline

#@# この他、お勧めのパッケージを @<href>{https://zenn.dev/atelier_mirai/articles/c3ed79af5ba395, RailsでのWebアプリ開発に愛用している Pulsar プラグイン} でご紹介しています。
#@#
#@# //blankline

//sideimage[pulsar_package_half][55mm][sep=5mm, side=R]{
また、有志の方々が創られたさまざまなパッケージが @<href>{https://web.pulsar-edit.dev} で公開されています。ご自身の使いやすいエディタに育てていって下さい。
//}

#@# @<fn>{plugin_install_error}
#@# //footnote[plugin_install_error][Pulsarは開発中の為、ネットワークの状況等によって、プラグインのインストールに失敗することがあります。翌日に行うなど、時間をおいて実行してみて下さい。]

== @<ruby>{Pulsar,パルサー} の追加設定

=== @<ruby>{Emmet,エメット} を使う為に

@<code>{Emmet}を使うと、HTML, CSSが素早く入力できるようになります。
その為の設定を行います。

@<code>{Ctrl + @<ruby>{,,カンマ}} を押すと、テキストエディタ @<ruby>{Pulsar,パルサー} の設定画面が開きます。
//image[config][][width=55%]

右下の「設定フォルダを開く」ボタンを押すと、別のPulsarの画面が現れます。Pulsarの様々な設定ファイルを参照したり、編集したりすることができます。

@<file>{keymap.cson} は、「キーマップ」という名称の通り、様々なキーの組み合わせ、割り当てを変更する為の設定ファイルです。

//image[keymap][][width=55%]

@<code>{Emmet} を使いやすくする為のキーの割り当てをこのファイルの中に記述します。以下のように記述してください。

//list[][keymap.cson]{
'.editor:not(.mini)':
  'ctrl-e': 'editor:move-to-end-of-line'
'atom-text-editor:not([mini])':
  'ctrl-,': 'emmet:expand-abbreviation'
'.platform-darwin atom-text-editor:not([mini])':
  'ctrl-d': 'unset!'
//}

@<href>{https://raw.githubusercontent.com/Atelier-Mirai/pulsar_config/master/keymap.cson} より、コピーすることも出来ます。

=== スニペットの登録

「スニペット」とは、「コードの断片」を指す言葉です。よく使うHTMLやCSSのコードなどを登録しておくと、便利です。スニペットの登録は @<file>{snippets.cson} に行います。

//image[snippets][][width=55%]

@<code>{html}とタイプすることで、次のように入力されるなど、いろいろ登録しています。

//list[][]{
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
//}

@<href>{https://raw.githubusercontent.com/Atelier-Mirai/pulsar_config/master/snippets.cson}より、コピーして貼り付けてください。

また、プログラムを作っていく中で、よく使うコードもあると思います。そんな時はスニペットに登録して、快適なプログラミングを楽しみましょう。
---
== セキュリティ重視のブラウザ @<code>{@<ruby>{Firefox,ファイヤフォックス}}
@<code>{Firefox} は、@<href>{https://www.mozilla.org/ja/firefox/new/, 公式サイト} より、ダウンロードできます。

//sideimage[firefox_download][55mm][sep=5mm,side=R]{
  Firefoxは、Mosaic, Netscape の血を受け継ぐブラウザです。CSSグリッドの確認や、丁寧なコメントの開発者ツールが特徴です。

  「Firefox をダウンロード」ボタンを押すとダウンロードが始まるので、落としたファイルをダブルクリックして、インストールしてください。
//}

== 基本的な開発方法

Pulsar と Firefox を導入できたので、ウェブサイトの基本的な作り方をご案内します。

 - 0. 画面の左側に Pulsar を、右側に Firefox を配置します。
 - 1. Pulsar  で、プログラムをいろいろ書いていきます。
 - 2. Firefox で、作ったウェブサイトの表示や動作を確認します。
 - 3. 出来上がりが良ければ、ウェブサイトを公開して完了です。 @<br>{}
      もう少し改良したければ、1. に戻ります。

=== 手順のご案内

作業ディレクトリの作成方法や、Pulsar や Firefox の簡単な使い方の紹介です。 @<fn>{mac}
#@# @<fn>{atom_book}
//footnote[mac][Mac利用者向けです。Windowsは適宜読み替えてください。]

//sideimage[study][55mm][sep=5mm,side=R]{
 - 0. @<code>{Users}@<code>{/利用者名}ディレクトリの直下に、 @<code>{projects}ディレクトリを作成します。 @<br>{} @<code>{projects}ディレクトリには、自分が作成する様々なプロジェクト(案件)を格納する為のディレクトリです。良く使う為、 @<code>{Finder}のサイドバーに登録すると便利です。

//}
　　@<code>{projects}ディレクトリを作成し、 @<br>{}
　　　その下に今回の学習用に @<code>{study} ディレクトリを作成します。

//vspace[latex][2mm]
//sideimage[af1][20mm][sep=5mm,side=R]{
 - 1. Pulsar のアイコンと Firefox のアイコンです。 @<br>{}良く使うのでドックに登録しておくと便利です。
//}

//sideimage[af2][55mm][sep=5mm,side=R]{
 - 2. Pulsar と Firefox を @<br>{}左右に配置します。
//}

//sideimage[atom0_add_projects_folder][20mm][sep=5mm,side=R]{
 - 3. Pulsar には、「ツリービュー」に「プロジェクトフォルダ」を追加する機能があります。「プロジェクトフォルダ」を追加すると、Atomの画面左側の「ツリービュー」にそのプロジェクトフォルダ内のファイルやディレクトリが一覧表示されます。ファイルの追加や編集、削除を簡単に行うことができるようになり、とても便利です。プロジェクトフォルダを追加するためには、左側の青色の「Add folders」ボタンを押します。
//}

//sideimage[af4a][55mm][sep=5mm,side=R]{
 - 4. @<code>{Finder}が開くので、サイドバーから @<code>{projects}を選びます。 @<code>{projects}ディレクトリから @<code>{study} ディレクトリを開きます。@<br>{}左側の「ツリービュー」に @<code>{study} ディレクトリが表示されますので、この @<code>{study} ディレクトリ内にいろいろなファイルを納めていき、最終的にウェブサイトを創り上げます。新しいファイルを作成しましょう。
//}

//blankline
//sideimage[html1][55mm][sep=5mm,side=R]{
 - 5. ツリービューの@<code>{study}ディレクトリを右クリックして、「新規ファイル」をクリックします。
//}

//sideimage[html2][55mm][sep=5mm,side=R]{
 - 6. 「Enter the path for the new file.」(新しいファイル名を入力して下さい)と、表示されるので、 @<code>{index.html} とファイル名を入力します。
//}
//blankline

//sideimage[html3][55mm][sep=5mm,side=R]{
 - 7. 左側の「ツリービュー」に、新規作成した @<code>{index.html} が、表示されましたので、これをクリックします。すると右側の編集領域(「ペイン」と呼びます)に、今作成した @<code>{index.html} が表示されます。今作成したばかりなので、中身は何もなく空っぽです。早速 HTML を書いていきましょう。Atom には、コードの入力を手助けしてくれる「入力支援機能」が備わっています。 @<code>{html} と入力して、エンターキーを押します。
//}
//blankline

//sideimage[template][55mm][sep=5mm,side=R]{
 - 8. 次のように雛形が入力されます。
//}
//blankline

//sideimage[study_html][55mm][sep=5mm,side=R]{
 - 9. 「色」がついていることにも着目してください。「シンタックスハイライト」と呼ばれる、HTMLの文法に分かりやすいよう、着色する機能です。それでは雛形で入力した結果を利用して、次のようにしましょう。 @<code>{h1} とタイプしエンターキーを押すと、 @<code>{<h1></h1>} と入力されます。Atom の入力支援機能を活用して編集しましょう。
//}

//sideimage[af6][55mm][sep=5mm,side=R]{
 - 10. HTML を入力して、@<file>{index.html} ファイルが完成しました。Atom の 「ファイル」メニューから「保存」をクリックするか、@<code>{Command + S} を押して保存します。保存できたら、どのように表示されるか、Firefoxを使って確認しましょう。Firefox の「ファイル」メニューから「ファイルを開く」をクリックするか、@<code>{Command + O} を押して、@<file>{index.html} を 開きます。
//}
//blankline

//sideimage[af4b][55mm][sep=5mm,side=R]{
 - 11. @<code>{Finder}が開くので、サイドバーから @<code>{projects}を選びます。 @<code>{projects}ディレクトリ内には、 @<code>{taskleaf} と @<code>{study} の 二つのディレクトリがありますが、ここでは @<code>{study} ディレクトリを開きます。
//}
//blankline

//sideimage[af8][55mm][sep=5mm,side=R]{
 - 12. Pulsar で編集したindex.html を Firefox で 閲覧できます。
//}
//blankline

//sideimage[af9][55mm][sep=5mm,side=R]{
 - 13. 綺麗に出来上がっていたら完成です。もう少し改善したい点があるなら、Pulsarに戻って @<code>{index.html} を編集します。編集が終わったら @<code>{Command + S} を押して保存します。保存が終わったら、編集結果を Firefox で見てみましょう。Firefox の「再読み込みボタン」を押すか、または @<code>{Command + R} を押して、編集結果を再確認することができます。
//}
---

習得したい基本的なショートカット

ショートカットを習得すると、効率的にコーディングできるようになります。
//vspace[latex][7mm]

**Mac 基本操作**
#@# === Mac 基本操作
//image[mac_shortcut][][width=100%]

**Pulsar 基本操作**
#@# === Atom 基本操作
//image[atom_shortcut][][width=65%]
