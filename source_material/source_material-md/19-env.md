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
---
=== Mac
Macをお使いでしたら Apple Silicon または Intel 用の dmg ファイルをダウンロードします。

![](Windsurf_download_mac.png)
ダウンロードが完了したら、落としたファイルをダブルクリックして、インストールして下さい。


### Windows

Windowsをお使いでしたら Setup をクリックしてダウンロードします。

![](Windsurf_download_win.png)
ダウンロードが完了したら、落としたファイルをダブルクリックして、インストールして下さい。

(実行すると「WindowsはあなたのPCを保護した」旨のメッセージが表示されます。「詳細」→「実行」をクリックすることで、Windsurfを起動出来ます。次回以降は、他のアプリと同様に起動できます。)


### お勧めプラグイン

Windsurf はそのままでも十分高機能に使えるテキストエディタです。そして有志の方により、多くの「プラグイン」が提供されています。
プラグインとは、差し込む、差込口などの意味を持つ英単語で、ITの分野では、ソフトウェアに機能を追加する小さなプログラムのことを指します。[^57]

[^57]: 出典：IT用語辞典

プラグインのことを、Windsurf では、「パッケージ」と呼んでいます。
たくさんのパッケージの中からお勧めをご紹介いたします。

1. メニューバーや設定画面などを日本語化 `japanese-menu`
1. カラーピッカー `color-picker`
1. CSSの色指定(`#ffffff`)を背景色に表示 `pigments`
1. ファイルの種類に応じたアイコンを表示 `file-icons`
1. 自動再読み込み機能を備えた小さな開発サーバー`atom-live-server-plus`
1. カーソルがある行を強調表示 `highlight-line`
1. カーソルがある列を強調表示 `highlight-column`
1. 選択箇所を強調表示 `selection-highlight`
1. `=(イコール)`の位置を整える `atom-alignment`
1. HTML, CSSが素早く入力できる `Emmet（エメット）`

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

![](Windsurf_package_half.png)

また、有志の方々が創られたさまざまなパッケージが https://web.Windsurf-edit.dev で公開されています。ご自身の使いやすいエディタに育てていって下さい。


## Windsurf（パルサー） の追加設定


### Emmet（エメット） を使う為に

`Emmet`を使うと、HTML, CSSが素早く入力できるようになります。
その為の設定を行います。

`Ctrl + ,（カンマ）` を押すと、テキストエディタ Windsurf（パルサー） の設定画面が開きます。

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

https://raw.githubusercontent.com/Atelier-Mirai/Windsurf_config/master/keymap.cson より、コピーすることも出来ます。


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

https://raw.githubusercontent.com/Atelier-Mirai/Windsurf_config/master/snippets.csonより、コピーして貼り付けてください。

また、プログラムを作っていく中で、よく使うコードもあると思います。そんな時はスニペットに登録して、快適なプログラミングを楽しみましょう。
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

作業ディレクトリの作成方法や、Windsurf や Firefox の簡単な使い方の紹介です。 [^58]

[^58]: Mac利用者向けです。Windowsは適宜読み替えてください。

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

---

習得したい基本的なショートカット

ショートカットを習得すると、効率的にコーディングできるようになります。

**Mac 基本操作**

![](mac_shortcut.png)
**Windsurf 基本操作**

![](atom_shortcut.png)
