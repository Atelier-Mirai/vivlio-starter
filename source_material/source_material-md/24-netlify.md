# ウェブサイトの公開

:::{.chapter-lead}
従来、ウェブサイトを公開するためには、**サーバー**と呼ばれるコンピュータに適宜様々な設定を施し、運用してきました。安全に運用するためにはそれなりの伎倆が求められるものでしたが、こうした中、台頭してきたのが、各種の**ホスティングサービス**です。簡単にそして安価に運用することができます。
ここでは、Netlify（ネットリファイ） をご紹介します。  
:::



## Netlify（ネットリファイ） でウェブサイトを公開する

Netlify は、「ウェブサイトを構築する最速の方法です」と紹介されているように、HTML / CSS / JavaScript を簡単に配信できるサイトです。


### 簡単公開

[https://app.netlify.com/drop](https://app.netlify.com/drop) をブラウザで開き、ウェブサイト一式を直接アップロードするだけで、全世界に公開できます。

じゃんけんゲームを、例えば「`study`フォルダ」に作成したのであれば、
この「`study`フォルダ」をドラッグ＆ドロップするだけで、世界中に1時間だけ公開できます。

![](drag_and_drop.png)
---
== Netlify（ネットリファイ） に会員登録する


### 会員登録の利点

Netlifyは、小規模利用 [^102]なら無料でサイトを公開できるサービスです。
会員登録せずとも利用可能ですが、登録することにより、

* サイトを永久的に公開できる。
* サイト名を好きな名前に変更できる。
* 問い合わせフォームの投稿を、メールで通知できる。

など、様々な機能が使えるようになりますので、登録がお薦めです。


また、バージョン管理システムとして Git（ギット） や リポジトリサービスである GitHub（ギットハブ）, GitLab（ギットラボ）, Bitbucket（ビットバケット） を使っている方なら、より便利に連携して使うことができます。

[^102]: Starterプラン(無料プラン)は、転送量: 100GB/月まで、容量: 100GB までです。作成した桜吹雪は約700kBの容量があります。単純計算ですが、毎日5000人が見るようになったら、有料プランへの移行を考えると良いでしょう。


### 会員登録の方法

- 1. ブラウザを開いて [Netlify](https://www.netlify.com/) にアクセスします。

![](netlify20.png)

![](netlify21.png)

- 2. 右上の青い「`Sign up`ボタン」を押すと、次の画面になります。 <br>
    GitHub（ギットハブ）, GitLab（ギットラボ）, Bitbucket（ビットバケット） を使っていると、それぞれのアカウントを利用して、Netlifyへの登録ができますが、ここでは一番下の「Email」を押します。

![](netlify21a.png)

- 3. メールアドレスとパスワードを入力し、「`Sign up`ボタン」を押します。

![](netlify22.png)

- 4. 次の画面が表示されます。メールを送ったので確認してくれとのことです。

![](netlify23.png)

- 5. メールソフトを確認すると、Netlifyからのメールが届いていました。緑色の「Verify email」を押します。（不正利用やメールアドレスの入力ミス対策などの為に、良く用いられる仕組みです。）

- 6. 「Verify email」ボタンを押すと、利用者登録の続きを行うことができます。

Nice to meet you! Let's get acquainted.(よろしくお願いします！知り合いになりましょう。)とご挨拶が有り、How ar your planning to use Netlify?(Netlifyの利用予定は？) と尋ねられます。「Personal」「Work」「School」「Client」から、今回は「Personal(個人)」を選びます。

![](netlify24.png)
What kind of site do you want to build first?(まず、どんなサイトを作りたいですか？) との質問には、いくつか選択肢がありますが、「Personal site」にしておきます。

What best describes your role?(あなたの役割は何ですか？) では、「Freelancer」「Hobby Developer」「Other」と選択肢がありますので、「Hobby Developer(趣味の開発者)」にします。

最後に What is the name of your team?(チーム名は何ですか？)と問われます。People who use Netlify for personal work often use a project name or their own name.(個人でNetlifyを使っている人は、プロジェクト名や自分の名前を使うことが多いようです。)と注釈があります。プロジェクト名やご自身の名前などお好みで入力なさってください。

最後に、「Continue to deploy」(デプロイを続ける)ボタンを押します。これで会員登録は完了です。


## Netlify（ネットリファイ） の利用方法


### ログインする

Netlify（ネットリファイ） にログインするには次のようにします。

- 1. ブラウザを開いて [Netlify](https://www.netlify.com/) にアクセスし、右上の青い「`Sign up`ボタン」の左側にある「`Log in`」を押します。

![](netlify25.png)

![](netlify26.png)

- 2. (GitHub等と連携することもできますが) ここでは「Log in with email」を押します。

![](netlify27.png)

- 3. メールアドレスとパスワードを入力して、「Log in」ボタンを押します。

- 4. ログインすると、「Team overview」の画面が開きます。

![](netlify30b.png)
---
=== デプロイ（配備・配信）方法

作成したウェブサイトを公開することを、デプロイ（配備・配信）と呼びます。
Weblio 英和辞典によると `deploy` とは「〈部隊・兵力などを〉展開する，配置する. 」意味の英単語です。IT分野では開発したソフトウェアなどを実用に供することを意味する用語として、用いられています。

作成したウェブサイトを公開・デプロイ・配備・配信するためには次のようにします。

- 1. ログインすると、「Team overview」の画面が開いています。

![](netlify30a.png)
「`Sites`欄」には今まで公開したサイトが表示されますが、今はまだ何も公開したサイトがないので、代わりに公開方法の案内が表示されています。

GitHub（ギットハブ） 等を使っている場合には「Import an existing project(既存のプロジェクトを取り込む)「Import from Git(Gitから取り込む)」ボタンを押すことで デプロイ（配備・配信）できます。 <br>

ここでは、手動で公開することにしましょう。画面中央下の「Drag and drop your site output folder here(サイトの出力フォルダをここにドラッグ＆ドロップしてください)」に、公開したサイト一式を納めたフォルダを、ドラッグ＆ドロップすると公開できます。<br>

- 2. しばらくすると、デプロイ（配備・配信）が完了します。`steady-paletas-13bb99`というサイト名で作成されたようです。

---
公開したウェブサイトへの設定を続けるために、「Get Started(行動に移る)」ボタンを押します。

![](netlify31.png)


### デプロイしたサイト名を変更する

- 1. 「Team overview」の画面になります。チームの活動状況が一覧できる画面です。「`Sites`」を押すと、今までにデプロイしたサイトの一覧画面へと遷移します。

![](netlify32.png)
---
- 2. 「`steady-paletas-13bb99`」と付けられたサイト名は、Netlifyが適宜命名したものなので、改名しましょう。「`steady-paletas-13bb99`」をクリックすると、設定画面へ遷移します。

![](netlify33.png)

- 3. 「`Site settings`」を押すと、「`steady-paletas-13bb99`」に関する様々な設定を行えます。もちろん名称を変更できますので、「`Site settings`」ボタンを押しましょう。

![](netlify34.png)

- 4. 様々な設定を行うことが出来ますが、名称変更の為には 下に表示されている「`Change site name`」ボタンをクリックします。

![](netlify35.png)

- 5. `Site name` 欄に新しいサイト名を入力します。アルファベット数字の他 `-(ハイフン)`が使えます。入力し終えたら、`Save` ボタンを押します。

![](netlify37.png)
---
- 6. サイト名を `joyful-janken.netlify.app` に変更することが出来ました。

![](netlify38a.png)

![](janken01.png)

`joyful-janken.netlify.app` をクリックすると、今まで手元のコンピュータ上で動作確認していた「じゃんけんゲーム」が、今や世界中の人々に見られるように公開されています。

---
=== デプロイしたサイトを更新する

公開したウェブサイトは、次の手順で更新することが出来ます。

- 1. 画面左上の Netlify のロゴマークをクリックします。Team overview の画面に遷移します。

![](netlify61.png)

- 2. `Sites` をクリックします。今まで公開しているサイトの一覧が表示されますので、変更したいサイト(ここでは joyful-janken のみですが)を選び、クリックします。

![](netlify62.png)

- 3. `Site overview` の画面が表示されます。このサイトに関する様々な設定を行うことが出来ます。 `Deploys` をクリックします。

![](netlify63.png)

- 4. 画面中央 `Deploys` の欄に「Need to update your site? Drag and drop your site output folder here.サイトの更新が必要ですか？ サイトの出力フォルダをここにドラッグ＆ドロップしてください。」と表示されていますので、 ドラッグ＆ドロップ すると更新完了です。

![](netlify64a.png)
---
=== 新しいサイトを追加する

今まで公開しているウェブサイトに加えて、また別のウェブサイトを公開したい場合もあると思います。次の手順で追加することが出来ます。

- 1. 画面左上の Netlify のロゴマークをクリックします。Team overview の画面に遷移します。

![](netlify71a.png)

- 2. `Sites` をクリックします。今まで公開しているサイトの一覧が表示されます。<br>

画面中央下に 「Want to deploy a new site without connectiong to Git? Drag and drop your site output folder here. Gitに接続することなく、新しいサイトをデプロイしたいですか？ サイトの出力フォルダをここにドラッグ＆ドロップしてください。」と表示されていますので、 ドラッグ＆ドロップ すると更新完了です。

![](netlify72a.png)
---
=== 公開したサイトを削除する

何らかの理由で今まで公開していたウェブサイトを削除したい場合もあると思います。次の手順で削除することが出来ます。

- 1. 画面左上の Netlify のロゴマークをクリックします。Team overview の画面に遷移します。

![](netlify81a.png)

- 2. `Sites` をクリックします。今まで公開しているサイトの一覧が表示されますので、削除したいサイト(ここでは joyful-janken のみですが)を選び、クリックします。

![](netlify82.png)
---
- 3. `Site overview` の画面が表示されます。このサイトに関する様々な設定を行うことが出来ます。 `Site settings` をクリックします。

![](netlify83.png)

- 4. `Danger one` をクリックします。

![](netlify84.png)
---
- 5. `Delete this site` をクリックします。

![](netlify85.png)

- 6. 注意書きが表示されます。

```
  Are you absolutely sure you want to delete joyful-janken?
If you have submitted a support request about this site, it will be difficult
for Netlify's Support team to help you debug the situation if you delete it.

Remember to remove any DNS records that point to this site's URL.

**This action cannot be undone.**

本当にjoyful-jankenを削除していいのでしょうか？
このサイトについてサポートリクエストを提出している場合、削除してしまうと、
サポートチームが状況をデバッグするのを助けるのが難しくなってしまいます。

このサイトの URL を指す DNS レコードを削除することを忘れないでください。

**この操作は元に戻せません。**
```

---
注意書きを了承した上で、「Type in the name of the site to confirm. 確認のためサイト名を入力します。」と書かれていますので、サイト名を入力します。

![](netlify86.png)

- 7. サイト名を入力すると、「Delete」ボタンが押せるようになりますので、クリックして削除は完了します。復活はできないので注意して使ってください。

![](netlify87.png)
---
=== ログアウトする

- 1. ログアウトするためには、右上の「Ｍ」ボタン（会員登録した名前によって変わります）をクリックします。いろいろなメニューが表示され、様々な設定を行うことができます。一番下の「`Sign out`」をクリックし、終了です。

![](netlify90.png)
