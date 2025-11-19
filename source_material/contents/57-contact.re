= お問い合わせページの機能拡張

//abstract{
//noindent
Netlify 公開したウェブサイトのために、
    * スパム対策
    * 必須項目設定
    * 連絡先自動入力
    * iPhoneで自動拡大を防ぐ
    * 投稿成功時の表示処理
    * 記入例(プレースホルダ)の表示
などを行っていきます。
//}

== @<ruby>{Netlify,ネットリファイ}

Netlifyは無料でサイトを公開できるサービスです。
会員登録なしでも利用可能ですが、登録により次のような様々な機能が使えるようになります。

 * Git(ギット)と連携したデプロイ(配備)ができる。
 * サイトを永久的に公開できる。
 * サイト名を好きな名前に変更できる。
 * 問い合わせフォームの投稿を、メールで通知できる。

紙幅の都合により登録方法等の解説は省きますが、登録等は容易ですのでご利用下さい。

== お問い合わせフォームの機能拡張

@<href>{https://ics.media/entry/200413/, CSS疑似クラスを活用した、モダンでインタラクティブなフォームの作り方}や、@<href>{https://ics.media/entry/11221/, 今どきの入力フォームはこう書く！ HTMLコーダーがおさえるべきinputタグの書き方まとめ} にとても良い記事がございます。引用・抜粋しつつ作成いたしました。是非ご一読下さい。

//image[contact][お問い合わせフォームの作成例][width=70%]
//image[success][送信ボタン押下後の表示][width=70%]

=== HTML

//list[][contact.html][1]{
<!-- 問い合わせフォーム -->
<form action="./success.html" method="post" name="contact" netlify-honeypot="bot-field" data-netlify="true">
  <input type="hidden" name="form-name" value="contact">
  <label class="hidden" for="subject">件名</label>
  <input type="hidden" id="subject" name="subject" value="Webサイトから「お問い合わせ」がありました。">
  <label class="hidden" for="referrer_url">お問い合わせ前に見ていたURL</label>
  <input  type="hidden" id="referrer_url" name="referrer_url"value="">

  <p class="hidden">
    <label>Don’t fill this out if you're human:
      <input name="bot-field">
    </label>
  </p>

  <p>
    <textarea autocapitalize="none" autocorrect="off" id="message" name="message" placeholder="とっても為になりました。ありがとうございます。" required="required"></textarea>
    <label class="name" for="message">お問い合わせ内容</label>
    <span id="message_size"></span>
  </p>

  <p>
    <input type="text" autocomplete="name" class="input" id="name" name="name" placeholder="山田 太郎" required="required">
    <label class="name" for="name">お名前</label>
  </p>

  <p>
    <input type="email" autocomplete="email" class="input" id="email" name="email" placeholder="taro@example.com" required="required">
    <label class="name" for="email">メールアドレス</label>
    <span class="error message">taro@example.comの形式で入力してください。</span>
  </p>

  <p>
    <input type="tel" autocomplete="tel" class="input" id="tel" maxlength="11" minlength="7" name="tel" pattern="^(\d|-|\(|\))*$" placeholder="0523734649">
    <label class="name" for="tel">電話番号</label>
    <span class="success message">OKです！</span>
    <span class="error message">09012345678、052-373-4649、0120(000)999の形式で入力してください。</span>
  </p>

  <input type="submit" id="submit" name="" value="送信">
</form>

<!-- contact form  validate -->
<link rel="stylesheet" href="vendor/contact_form_validate.css">
<script src="vendor/contact_form_validate.js"></script>
//}

少し大きなHTMLになったので要点を解説します。

//list[][contact.html]{
<form action="./success.html" method="post" name="contact" netlify-honeypot="bot-field" data-netlify="true">
//}
@<code>{form}要素に様々な属性が追記されています。

@<code>{action="./success.html"} で、フォーム送信後、success.htmlが表示されるようになります。

@<code>{method="post"} は、フォーム送信時に、入力したデータが見えないように送る指定です。

@<code>{name="contact"} と書くことで、サーバ側でこのフォームのデータを @<code>{params[:contact]}のような形で取得することができるようになります。

@<code>{netlify-honeypot="bot-field"} は、スパム対策用の記述です。 @<code>{bot}と呼ばれる機械プログラムにより投稿フォームが送信されることがあります。その際、 @<code>{honeypot}(蜜壺)を仕掛けておくことで、機械によるフォームデータの入力と、人によるフォームデータの入力を区別できます。

@<code>{data-netlify="true"} と書くことで、通常サーバ側でフォームデータを取り出す処理を行って管理者へのメール通知などを行わなければならないところを、 GUI上で簡単な設定を行うだけで@<code>{Netlify}が通知してくれるようになります。

//list[][contact.html]{
<input type="hidden" name="form-name" value="contact">
<label class="hidden" for="subject">件名</label>
<input type="hidden" id="subject" name="subject" value="Webサイトから「お問い合わせ」がありました。">
<label class="hidden" for="referrer_url">お問い合わせ前に見ていたURL</label>
<input  type="hidden" id="referrer_url" name="referrer_url"value="">
<script>
  document.getElementById("referrer_url").value = document.referrer;
</script>
//}

@<code>{<input type="hidden">}は、人の目には隠されている(hidden)入力枠です。プログラムからデータを送信したい際に用います。
@<code>{label}と@<code>{input}は、組にして用います。
書き方は二種類あり、一つは、@<code>{label}タグの中に、@<code>{input}タグを書く方法です。
//list[][]{
<label>
  件名
  <input id="subject">
</label>
//}

もう一つの方法は、@<code>{input}タグに @<code>{id}属性を付け、それを @<code>{label}タグで参照する方法です。
//list[][]{
<label for="subject">件名</label>
<input id="subject">
//}
コーディングやデザイン上の要請から、こちらの方法を用いています。

//list[][]{
<input  type="hidden" id="referrer_url" name="referrer_url"value="">
<script>
  document.getElementById("referrer_url").value = document.referrer;
</script>
//}
は、お問い合わせ前に見ていたURLを得るためのコードです。 @<code>{input}タグの @<code>{value}属性は、 @<code>{""}と空になっていますが、@<code>{JavaScript}コードを書くことで、お問い合わせページの直前に見ていたURLを取得し、@<code>{input}タグの @<code>{value}属性を与えています。

//list[][]{
<p class="hidden">
  <label>Don’t fill this out if you're human:
    <input name="bot-field">
  </label>
</p>
//}
は、 @<code>{honey-pot}(蜜壺)です。

@<code>{class="hidden"}と、 @<code>{hidden}クラスを付与することにより、人の目には見えないようになっています。それにもかかわらず、 @<code>{<input name="bot-field">}に何か値がセットされていたならば、ボットと呼ばれる機械プログラムからのスパムであると判定できます。

//list[][]{
<textarea autocapitalize="none" autocorrect="off" id="message" name="message" placeholder="とっても為になりました。ありがとうございます。" required="required"></textarea>
<label class="name" for="message">お問い合わせ内容</label>
<span id="message_size"></span>
//}
@<code>{autocapitalize="none"}は、自動的に先頭の文字を大文字にすることを無効にするために書きます。英語圏では自動的に先頭の文字が大文字になるのは有用ですが、日本語圏においてはむしろ邪魔になりますので、無効化します。

@<code>{autocorrect="off"}は、自動的に英単語のつづりを修正する機能です。これも英語圏では有用ですが、日本語圏においてはむしろ邪魔になりますので、無効化します。

@<code>{name="message"}と名前付けを行い、サーバ側でこのフィールドのデータを、@<code>{params[:message]}などのように取り出すことができるようにします。

@<code>{placeholder="とっても為になりました"}は、入力枠に表示される記入例で、例があると、サイトの閲覧者にとって何を入力すべきか、分かりやすくなります。

@<code>{required="required"}は、必須項目を現す属性です。ブーリアン属性と呼ばれ、必須の有無を表します。@<code>{required} または @<code>{required=""} と書くこともできます。

@<code>{<span id="message_size"></span>}は、後ほど JavaScript で文字数を数え、表示するために用意している要素です。


//list[][]{
<input type="text" autocomplete="name" class="input" id="name" name="name" placeholder="山田 太郎" required="required">
<label class="name" for="name">お名前</label>
//}
@<code>{autocomplete="name"}と書くことで、iPhoneに登録されている連絡先が自動入力されるようになります。

//list[][]{
<input type="email" autocomplete="email" class="input" id="email" name="email" placeholder="taro@example.com" required="required">
<label class="name" for="email">メールアドレス</label>
<span class="error message">taro@example.comのような形式で入力してください。</span>
//}
@<code>{type="email"}と書くことで、iPhoneで入力する際、@マーク付きのキーボードが表示されるので楽になります。

また、メールアドレスの形式が異なる場合に、エラーメッセージを表示するようにしています。

//list[][]{
<input type="tel" autocomplete="tel" class="input" id="tel" maxlength="11" minlength="7" name="tel" pattern="^(\d|-|\(|\))*$" placeholder="0523734649">
<label class="name" for="tel">電話番号</label>
<span class="success message">OKです！</span>
<span class="error message">09012345678、052-373-4649、0120(000)999のような形式で入力してください。</span>
//}
@<code>{type="tel"}と書くことで、iPhoneで入力する際、電話番号のためのキーボードが表示されるので楽になります。
@<code>{maxlength="11" minlength="7"}と書くことで、電話番号の桁数を最大11桁、最小7桁に指定します。
@<code>{pattern="^(\d|-|\(|\))*$"}は、入力データを「正規表現」と呼ばれる記法で制約しています。 数字と@<code>{-}(ハイフン)、@<code>{()}(かっこ)のみを受け付けるように指定しています。

=== CSS
//list[][contact_form_validate.css]{
form .hidden {
  display: none;
}

form {
  max-width: 600px;
  margin: 0 auto;
  padding: 24px;
}

form p {
  display: flex;
  flex-direction: column;
  margin-bottom: 2rem;
  position: relative;
}

form p:focus-within label.name {
  transform: translateY(0) scale(0.8);
}

form label.name {
  display: block;
  order: 1;
  transition: transform 0.2s;
  transform: translateY(32px) scale(1);
  transform-origin: 0 100%;
  padding: 7px;
  font-size: 14px;
  line-height: 1;
}

@media (min-width: 768px) {
  form label.name {
    transform: translateY(34px) scale(1);
  }
}

form input, form textarea {
  order: 2;
  width: 100%;
  border: none;
  font-size: 16px;
  padding: 8px;
  border-bottom: 1px solid #333333;
  background: rgba(255, 255, 255, 0.5);
}

form .message.error { color: red; }
form .message.success { color: green; }

form input:invalid,
form textarea:invalid {
  box-shadow: none;
}

form input:invalid~.error.message,
form textarea:invalid~.error.message {
  display: block;
}

form input:invalid~.success.message,
form textarea:invalid~.success.message {
  display: none;
}

form input:valid~.error.message,
form textarea:valid~.error.message {
  display: none;
}

form input:valid~.success.message,
form textarea:valid~.success.message {
  display: block;
}

form input::placeholder,
form textarea::placeholder {
  color: transparent;
}

form input:placeholder-shown~.error.message,
form input:placeholder-shown~.success.message,
form textarea:placeholder-shown~.error.message,
form textarea:placeholder-shown~.success.message {
  display: none;
}

form input:not(:placeholder-shown)~label.name,
form textarea:not(:placeholder-shown)~label.name {
  transform: translateY(0) scale(0.8);
}

form textarea~label.name {
  padding-left: 7px;
}

form .message {
  padding: 0 8px 8px 8px;
  position: absolute;
  bottom: -36px;
  z-index: -1;
  font-size: 0.9rem;
}

form input[required]~label.name::after,
form textarea[required]~label.name::after {
  content: '(必須)';
  color: red;
  font-size: small;
  margin-left: 5px;
}

form p.required {
  display: block;
  text-align: right;
  margin-bottom: 0;
}

form #submit {
  width: 120px;
  height: 40px;
  border: none;
  background-color: green;
  font-weight: bold;
  font-size: 1rem;
  color: #fff;
  cursor: pointer;
  transition: opacity 0.2s;
}

form #submit:disabled {
  background-color: #999;
  color: #ddd;
  cursor: not-allowed;
}

form #submit:not(:disabled):hover {
  opacity: 0.8;
}

form #message_size {
  font-size: 12px;
  transform: translateY(140px)
}
//}

要点を解説していきます。

#@# //list[][]{
#@#   input,
#@#   textarea {
#@#     /* iOS では 16px 未満だと自動拡大されるので */
#@#     font-size: 16px;
#@#   }
#@# //}
#@# iPhoneでは、入力枠のフォントが16px未満だと画面が自動拡大されます。予めフォントサイズを16pxにしておくことにより、自動拡大されることを防ぎます。

#@# //list[][contact.css]{
#@# form input::placeholder,
#@# form textarea::placeholder {
#@#   font-family: 'Hachi Maru Pop', cursive;
#@# }
#@# //}
#@# @<code>{input::placeholder}セレクタで、プレースホルダーの書体を設定します。
#@#
//list[][]{
form input[required]~label.name::after,
form textarea[required]~label.name::after {
  content: '(必須)';
  color: red;
  font-size: small;
  margin-left: 5px;
}
//}
@<code>{input[required]}は、属性セレクタです。 @<code>{required}属性が設定されている要素を選択します。
@<code>{~}は、間接セレクタです。 @<code>{required}属性が設定されている要素の後に続く @<code>{label.name} に対して疑似要素@<code>{::after}を指定、赤色で(必須)を挿入しています。
これをやりたいために、 @<code>{<input>}タグの「後」に @<code>{<label>}タグを書いていることにも着目してください。

#@# //list[][]{
#@# <input type="text" id="name" required="required">
#@# <label class="name" for="name">お名前</label>
#@# //}
#@#
#@# //list[][]{
#@# form .hidden {
#@#   display: none;
#@# }
#@# //}
#@# @<code>{display: none;} で、非表示にします。

//list[][]{
form label.name {
  display: block;
  order: 1;
  transition: transform 0.2s;
  transform: translateY(32px) scale(1);
  transform-origin: 0 100%;
  padding: 7px;
  font-size: 14px;
  line-height: 1;
}
//}
少し長いCSSルールですが、 ポイントとなるのは、@<code>{transform: translateY(-72px) scale(1);} です。

//list[][]{
  <input type="text" id="name" required="required">
  <label class="name" for="name">お名前</label>
//}
と書いたことで、入力枠の「後」に、見出しがきます。
この見出しを72px上にずらすことで、入力枠の「前」に、見出しがくるようにしています。

//list[][]{
form .message.error { color: red; }
form .message.success { color: green; }

form input:invalid~.error.message,
form textarea:invalid~.error.message {
  display: block;
}

form input:invalid~.success.message,
form textarea:invalid~.success.message {
  display: none;
}
//}
入力に誤りがあった場合、エラーメッセージを赤で、正常であった場合、緑で表示します。
着目して欲しいのは @<code>{:invalid}擬似クラス です。
フォームの検証（バリデーション）をブラウザが行った際、妥当でない入力の場合には、@<code>{:invalid} となりますので、CSS により、赤くエラーメッセージを表示させることができます。

//list[][]{
form #submit {
  background-color: green;
}

form #submit:disabled {
  background-color: #999;
  cursor: not-allowed;
}
//}

同様に「送信ボタン」も、全入力欄が妥当な場合には緑色、そうでない場合には灰色となり送信ボタンを押せないようにしています。

=== JavaScript

//list[][contact_form_validate.js]{
/*-----------------------------------------------------------------------------
  ユーザーが何かを入力するたびに、文字数を表示する。
-----------------------------------------------------------------------------*/
// 文字数を返す関数
let getCharacterLength = (str) => {
  return [...str].length;
}

// 文字数の表示
const message      = document.getElementById('message');
const message_size = document.getElementById('message_size');
message.addEventListener("input", (event) => {
  let size = getCharacterLength(message.value);
  message_size.innerText = `${ size } 文字入力しました。`;
});

/*-----------------------------------------------------------------------------
  フォーム全体の妥当性を判定する
-----------------------------------------------------------------------------*/
let validate = () => {
  let validForm         = document.querySelector("form:valid");
  let submitButton      = document.getElementById("submit");
  submitButton.disabled = (validForm === null);
};

// (送信ボタンが押せないよう) 初回読み込み時に、validate関数を実行。
validate();

// フォームに入力されたら、validate関数を実行
document.querySelectorAll("input, textarea").forEach((input) => {
  input.addEventListener("input", validate);
});

/*-----------------------------------------------------------------------------
  どの記事を見てからの問い合わせか分かるよう、参照元URLを取得する
-----------------------------------------------------------------------------*/
document.getElementById("referrer_url").value = document.referrer;

/*-----------------------------------------------------------------------------
  フォーム送信前にタブを閉じる際に、確認アラートを表示する。
-----------------------------------------------------------------------------*/
let confirmationAlert = (event) => {
  // Cancel the event as stated by the standard.
  event.preventDefault();
  // Chrome requires returnValue to be set.
  event.returnValue = '';
};

// ページ離脱しようとした際に、アラートを表示する。
window.addEventListener('beforeunload', confirmationAlert, false);

// 但し、#submit が押された際には、アラートを表示させない。
document.getElementById('submit').addEventListener('click', () => {
  window.removeEventListener('beforeunload', confirmationAlert, false);
});
//}

JavaScript の解説を行っていきます。

//blankline
==== 文字数を数える
//sideimage[mojisuu][45mm][sep=5mm,side=R]{
「ユーザーが何かを入力するたびに、文字数を表示する。」機能を設けてあります。

@<code>{str.length} では、一部の絵文字等で正しく取得できない場合があるため、
JavaScriptで正確に文字数を数えるためには、次のような関数により実現します。
//}

//list[][]{
let getCharacterLength = (str) => {
  return [...str].length;
}
//}

詳細は @<href>{https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Global_Objects/String/length, String length} をご覧ください。

文字数が数えられるようになりましたので、イベントリスナを準備し、表示させています。

//blankline

==== フォームの妥当性
//sideimage[soushin_off][30mm][sep=5mm,side=R]{
「フォーム全体の妥当性を判定する」機能の説明です。
フォームの必須項目が入力されていないか、形式が誤っている場合には送信ボタンを押せないようにします。
//}

//sideimage[soushin_on][30mm][sep=5mm,side=R]{
妥当なデータが入力されているなら、送信ボタンを押せるようにします。
サイトの利用者にも分かりやすくなっています。
//}

フォームの妥当性は@<code>{document.querySelector("form:valid");}で取得できます。これにより送信ボタンの有効・無効を切り替えて実現しています。

@<href>{https://ics.media/entry/200413/, CSS疑似クラスを活用した、モダンでインタラクティブなフォームの作り方} や、@<href>{https://developer.mozilla.org/ja/docs/Learn/Forms/Form_validation,クライアント側のフォーム検証}に詳細が記されておりますので、ご参考になるかと思います。

==== 参照元URL の取得
@<code>{document.referrer}でURLが取得できるので、 お問い合わせ前に見ていたURLを@<code>{<input type="hidden" id="referrer_url" name="referrer_url" value="">} に渡しています。

==== 確認アラートの表示
//sideimage[alert][60mm][sep=5mm,side=R]{
フォーム送信前に他のページへ行くと入力中のデータは失われてしまいます。そうならないよう確認アラートを表示しましょう。
//}
@<href>{https://developer.mozilla.org/ja/docs/Web/API/Window/beforeunload_event,Window: beforeunload イベント}を使います。

//quote{
  beforeunload イベントは、ウィンドウ、文書、およびそのリソースがアンロードされる直前に発生します。文書はまだ表示されており、この時点ではイベントはキャンセル可能です。
  このイベントによって、ウェブページがダイアログボックスを表示し、ユーザーにページを終了するかどうかの確認が求めることができます。ユーザーが確認すれば、ブラウザーは新しいページへ遷移し、そうでなければ遷移をキャンセルします。
//}

@<href>{https://qiita.com/naoki_koreeda/items/bf0f512dbd91b450c671,ページ離脱時にアラート表示}も参考になります。
