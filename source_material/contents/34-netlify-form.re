= 投稿フォーム

//abstract{
Netlify での投稿フォームについて、説明します。
//}

== ソースコード(HTML)

form 部分を抜粋しています。完全版は
@<href>{https://github.com/Atelier-Mirai/wave_example/blob/master/contact.html} にアクセスし、コピーしてください。

//list[][contact.html][]{
<!-- お問い合わせフォーム -->
<!-- 各種属性の意味は次の通り -->
<!--  name="contact"    サーバ処理時に、contact という名前のフォームとして扱う
      action="/success" 送信ボタンを押すと、success.html を表示する
      method="POST"     form送信の際の約束事として、こう記述する
      netlify-honeypot="bot-field"   ボット対策(プログラムによる自動投稿対策)
      data-netlify-recaptcha="true"  車の絵を選べなどの「キャプチャ」機能を用いる
      data-netlify="true">           Netlify でフォーム処理を行う -->
<form
  name="contact"
  action="/success"
  method="POST"
  netlify-honeypot="bot-field"
  data-netlify-recaptcha="true"
  data-netlify="true">

  <!-- Netlify honeypot -->
  <!-- hidden(隠し)クラスにしているので、人の目からはこの入力枠は見えない。
       それでも入力枠に文字入力されているならば、ボット（コンピュータプログラム）
       による投稿なので、Netlify により、スパム(迷惑)として扱われる -->
  <p class="hidden">
    <label>Don’t fill this out if you're human:
      <input name="bot-field">
    </label>
  </p>

  <!-- メール通知用の隠し枠 -->
  <!-- Netlifyから送られるメールの「件名」と
      「問い合わせ前に見ていたURL」を指定している -->
  <input type="hidden"
         id="subject"
         name="subject"
         data-remove-prefix="true"
         value="Webサイトから「お問い合わせ」がありました。">
  <label class="hidden" for="subject">件名</label>
  <input type="hidden" id="referrer_url" name="referrer_url">
  <label class="hidden" for="referrer_url">お問い合わせ前に見ていたURL</label>
  <script>
    document.getElementById("referrer_url").value = document.referrer
  </script>

  <p>
    <!-- 長文用の文字入力枠 -->
    <!-- 各種属性の意味は次の通り -->
    <!-- autocapitalize="none" 自動的に先頭文字を大文字にしない
          autocorrect="off"    自動的に綴校正(スペルチェック)を行わない
          id="message"         id属性をmesseageにする。
                               labelのfor属性に for="message" と書き、
                               入力枠とラベルの対応関係を明確にする
          name="message"       サーバ側で、message という名前の入力枠として扱う
          placeholder="とっても為になりました。ありがとうございます。" 入力例 required="required"  required属性。送信ボタンを押すには入力必須 -->

    <textarea
      autocapitalize="none"
      autocorrect="off"
      id="message"
      name="message"
      placeholder="とっても為になりました。ありがとうございます。" required="required"></textarea>
    <label for="message">お問い合わせ内容</label>
  </p>

  <p>
    <!-- 文字入力枠 -->
    <!-- 各種属性の意味は次の通り -->
    <!-- type="text" 文字入力用の枠 通常のキーボードが表示される
         autocomplete="name" iPhone の連絡先から自分の名前が自動入力できる -->
    <input
      type="text"
      autocomplete="name"
      id="name"
      name="name"
      placeholder="山田 太郎"
      required="required">
    <label for="name">お名前</label>
  </p>

  <p>
    <!-- 文字入力枠 -->
    <!-- 各種属性の意味は次の通り -->
    <!-- type="email" メール入力用の枠 メール用のキーボードが表示される
         autocomplete="email" iPhone で自分のメールアドレスが自動入力できる -->
    <input
      type="email"
      autocomplete="email"
      id="email"
      name="email"
      placeholder="taro@example.com"
      required="required">
    <label for="email">メールアドレス</label>
  </p>

  <p>
    <!-- 文字入力枠 -->
    <!-- 各種属性の意味は次の通り -->
    <!-- type="tel" 電話入力用の枠 電話用のキーボードが表示される
         autocomplete="tel" iPhone で自分の電話番号が自動入力できる
         maxlength="13" 最大13桁
         minlength="7"  最小 7桁
         pattern="^(\d|-|\(|\))*$" 「正規表現」数字か - か () が入力可 -->
    <input
      type="tel"
      autocomplete="tel"
      id="tel"
      maxlength="13"
      minlength="7"
      name="tel"
      pattern="^(\d|-|\(|\))*$"
      placeholder="0523734649">
    <label for="tel">電話番号</label>
  </p>

  <!-- Netlify が提供する「キャプチャ機能」を用いるには以下のコードを記述する
       (「キャプチャ」機能とは、車の絵を選べなど、人であるかの確認機能のこと -->
  <div data-netlify-recaptcha="true"></div>

  <!-- 送信ボタン -->
  <!-- type="submit" で、送信ボタンになる -->
  <input type="submit" value="送信">
</form>
//}

== ソースコード(CSS)
以下のコードは、
@<href>{https://github.com/Atelier-Mirai/wave_example/blob/master/stylesheets/_form.css} にあります。タイプし理解を深めても良いです。

//list[][_form.css][1]{
/*=============================================================================
  問い合わせフォーム
=============================================================================*/

/* Google Fonts より Hachi Maru Pop 書体 を 読み込む */
@import url("https://fonts.googleapis.com/css2?family=Hachi+Maru+Pop&display=swap");

/* form 要素を対象に 装飾指定する */
form {
  padding-top: 30px;    /* 上に空白を設ける */

  /* form 内の p 要素を対象に 装飾指定する */
  p {
    margin-bottom: 20px;
  }

  /* hidden(隠し)クラス属性を付けた要素を対象に 装飾指定する */
  .hidden {
    display: none;      /* 非表示にする */
  }

  /* 入力枠、長文入力枠への装飾指定 */
  input,
  textarea {
    width: 100%;            /* 幅 */
    box-sizing: border-box; /* padding込で幅を指定する */
    padding: 10px;          /* 空白を設ける */
    font-size: 16px;        /* iOS では 16px 未満だと自動拡大されるため、
                               書体の大きさを 16px に設定 */
    font-family: 'Hachi Maru Pop', cursive; /* はちまるポップ体 */
  }

  /* 入力欄に表示される入力例の文字(プレイスホルダ) */
  input::placeholder,
  textarea::placeholder {
    font-family: 'Hachi Maru Pop', cursive; /* はちまるポップ体 */
  }

  textarea {
    height: 120px;
  }

  /* <input type="submit"> の要素を対象に装飾を指定 */
  input[type="submit"] {
    background: var(--shinonomeiro);  /* 東雲色 */
    border: none;                     /* 枠線無し */
    -webkit-appearance: none;         /* ブラウザによる送信ボタン装飾無し */

    /* 画面幅が768px以上なら */
    @media (width >= 768px) {
      width: 240px;
    }
  }

  /* required 属性のある要素 に「~(チルダ・隣接)」する label 要素を対象に
     擬似要素を使って、赤い【必須】を付ける */
  :required ~ label::after {
    content: "【必須】";
    color: var(--kyohiiro);
  }

  /* ラベルの表示位置を上方に調整 */
  label {
    display: block;     /* ブロック要素として表示にする
                           幅と高さを持てるようになるので、上に移動可能となる */
    transform: translateY(-80px) scale(1); /* 位置を上にずらす */
    font-size: 14px;    /* 書体の大きさを指定 */
    padding: 7px;       /* 空白を設ける */
  }
  /* textarea 要素 に「~(チルダ・隣接)」する label 要素を対象に */
  textarea ~ label {
    transform: translateY(-164px) scale(1); /* さらに上方に移動 */
  }
}
//}

== Form の設定

WAVEをNetlifyにアップします。

「Log in」をクリックします
//image[form01][][width=80%]
---
「Log in with email」をクリックします。
//image[form02][][width=80%]

メールアドレス、パスワードを入力し、「Log in」ボタンを押します。
//image[form03][][width=80%]
---
Team overview 画面が表示されます。 Sites を押します。
//image[form04][][width=80%]

右画面下に、WAVEを作成したフォルダをドラッグ＆ドロップします。
//image[form05][][width=80%]
---
しばらくすると、Netlifyへのアップロードが完了します。 Get started ボタンを押します。
//image[form06][][width=80%]

Sitesをクリックします。
//image[form07][][width=80%]
---
cute-capybara-450f14 というサイト名で公開されたようです。cute-capybara-450f14 をクリックします。
//image[form08][][width=80%]

Formsをクリックします。
//image[form09][][width=80%]
---
Enable form detection （フォーム検出）をクリックします。
これにより、Netlify による投稿フォームの処理ができるようになります。
//image[form10][][width=80%]

しばらくすると、Form detection is enabled. と表示され、フォームの検出が有効化されました。
//image[form11][][width=80%]
---
フォーム検出が有効となったので、Deploys をクリックし、「もう一度デプロイ（公開・配備）」します。
//image[form12][][width=80%]

Deploys画面下部に、WAVEディレクトリをドラッグ＆ドロップします。
//image[form13][][width=80%]
---
しばらくすると、Netlifyへのアップロードが完了します。
//image[form14][][width=80%]

Forms をクリックします。画面右に Active forms として、「contact」が表示されています。contact は、@<code>{<form name="contact">} と命名したことによるものです。
//image[form15][][width=80%]
---
Site settings をクリックします。
//image[form16][][width=80%]

Form notifications(フォーム通知)をクリックします。Add notification(通知の追加)をクリックします。
//image[form17][][width=80%]
---
Email notification (電子メールによる通知)をクリックします。
//image[form18][][width=80%]

通知を受け取りたいメールアドレスを入力します。
//image[form19][][width=80%]
---
メールアドレスの入力を終えたら、Saveボタンを押します。
//image[form29][][width=80%]

画面右上に、通知先として登録したメールアドレスが表示されています。
//image[form21][][width=80%]
---
それでは、問い合わせがあった際に投稿されるか、確認してみましょう。Site overview をクリックします。https://cute-capybara-450f14.netlify.app をクリックします。
//image[form22][][width=80%]

WAVEが表示されますので、右上、問い合わせをクリックします。
//image[form23][][width=80%]
---
作成した問い合わせフォームが表示されています。必須項目や入力例、ロボット避けのキャプチャが表示されています。
//image[form24][][width=80%]
---
必須項目に入力せぬまま、送信ボタンを押すと、「このフィールドは入力必須です。」とメッセージが表示されます。
//image[form24a][][width=80%]
---
CSS で次のように設定しました。
//list[][][1]{
@import url('https://fonts.googleapis.com/css2?family=Hachi+Maru+Pop&display=swap');

font-family: 'Hachi Maru Pop'
//}

入力枠内の文字が 可愛い Hachi maru pop 体 になっています。 @<br>{}
入力枠に入力したら、チェックボックスをクリックします。
//image[form25][][width=80%]
---
横断歩道の画像を選択するよう、求められました。選び終わったら、確認ボタンを押します。
//image[form26][][width=80%]
---
緑色のチェックが入り、送信ボタンが押せるようになりますので、送信ボタンを押します。
//image[form27][][width=80%]
---
お問い合わせありがとうございました。表示されます。これは @<code>{<form action="/success">} と記述して @<file>{success.html} を表示するようにした効果です。
//image[form28][][width=80%]
---
再びNetlifyの画面に戻ります。Formsをクリック、contact をクリックします。
//image[form30][][width=80%]

「HTMLとCSSを習得しました」と、問い合わせ画面からのメッセージが届いています。
//image[form31][][width=80%]
---
「HTMLとCSSを習得しました」をクリックすると、その詳細を確認することができます。
//image[form32][][width=80%]

メールソフトを立ち上げ、メールも確認してみましょう。問い合わせ画面に入力した内容がそのまま届いています。
//image[form33][][width=50%]
