# コードのリファクタリング超ダイジェスト

:::{.chapter-lead}
この付録では、「リファクタリング」と呼ばれるコードの整理術について、ほんの触りだけご紹介いたします。

リファクタリングとは、「動くコードのまま、読んだり直したりしやすい形に整え直すこと」です。
新しい機能を足したり、バグを直したりする前に、まずはコードの見通しをよくするためのお掃除、と考えていただくとイメージしやすくなります。
:::

## リファクタリングとは何ですか

ソフトウェア開発の世界では、次のような作業をまとめて「リファクタリング」と呼びます。

- 動いてはいるが読みにくいコードを、意味の分かる変数名・関数名に直す
- 同じような処理が何度も出てくるところを、ひとつの関数にまとめる
- 長くて追いにくい関数を、役割ごとに分割する

ここで大事なのは、**外から見た「振る舞い」は変えない** という約束です。

- ✅ 振る舞いを変えずに、内部の書き方だけを整える → リファクタリング
- ✅ バグを直す前に、原因を探しやすい形にコードを整理する → リファクタリングの一種
- ❌ 新しい機能を追加する → それ自体はリファクタリングではない（機能追加）

リファクタリングは、ある程度コードを書き進めて「ちょっと読みにくくなってきたな」と感じたときに、
こまめに挟んでいくのが理想です。一気に大工事をするというより、「早め早めの掃除」として付き合うと気が楽になります。

## 小さな JavaScript での例

ここでは、JavaScript のごく小さな例を使って、リファクタリングの流れを眺めてみましょう。

### リファクタリング前のコード

次のように、利用者一覧を表示する関数が 2 つあるとします。

```js
function printUserSummary(users) {
  for (const user of users) {
    console.log(user.name + " (" + user.age + "歳)");
  }
}

function sendBirthdayMail(users) {
  for (const user of users) {
    if (!user.hasBirthdayToday) continue;

    const title = "お誕生日おめでとうございます";
    const body =
      user.name + " (" + user.age + "歳) さん、いつもありがとうございます。";

    console.log("送信:", title, body);
  }
}
```

動作としては問題ありませんが、`user.name + " (" + user.age + "歳)"` という書き方が、
2 つの関数で重複しています。表示形式を少し変えたくなったとき、両方を直し忘れるとバグの元になりそうです。

### ステップ 1: 共通処理を関数に切り出す

まずは、「利用者を表示するときのラベル」を作る処理だけを、別の関数に切り出してみます。

```js
function formatUserLabel(user) {
  return user.name + " (" + user.age + "歳)";
}

function printUserSummary(users) {
  for (const user of users) {
    console.log(formatUserLabel(user));
  }
}

function sendBirthdayMail(users) {
  for (const user of users) {
    if (!user.hasBirthdayToday) continue;

    const title = "お誕生日おめでとうございます";
    const body = formatUserLabel(user) + " さん、いつもありがとうございます。";

    console.log("送信:", title, body);
  }
}
```

やっていることはまったく同じですが、

- 「名前と年齢をラベルにする処理」は `formatUserLabel` に 1 箇所だけ
- それを使う側 (`printUserSummary` / `sendBirthdayMail`) は、
  「ラベルをどう使うか」だけに集中できる

という構造になりました。

このように、**意味のあるまとまりごとに名前を付けてあげる** のは、リファクタリングの代表的な一手です。

### ステップ 2: テンプレートリテラルで読みやすくする

さらに、文字列のつなぎ方をテンプレートリテラルに変えると、
文章としての見通しもよくなります。

```js
function formatUserLabel(user) {
  return `${user.name} (${user.age}歳)`;
}

function printUserSummary(users) {
  for (const user of users) {
    console.log(formatUserLabel(user));
  }
}

function sendBirthdayMail(users) {
  for (const user of users) {
    if (!user.hasBirthdayToday) continue;

    const title = "お誕生日おめでとうございます";
    const body = `${formatUserLabel(user)} さん、いつもありがとうございます。`;

    console.log("送信:", title, body);
  }
}
```

動作は最初のコードと変わりませんが、

- 「どの部分が名前で、どの部分が年齢か」がひと目で分かる
- ラベルの形式を変えたいとき、`formatUserLabel` だけを見ればよい

という状態になりました。

これも立派なリファクタリングです。

## リファクタリングをするときの心がけ

少しだけ大きなコードを書くようになってきたら、次のような点を意識すると安全に進めやすくなります。

- **小さなステップで進める**  
  まずは関数 1 つだけ名前を変える、1 箇所だけ共通化する、など、
  「前後のコードを見比べやすい粒度」で手を動かします。

- **動作が変わっていないか、こまめに確認する**  
  ブラウザをリロードしたり、簡単なテストコードを書いたりして、
  リファクタリングの前後で結果が同じかどうかをチェックします。

- **「読み手の自分」にやさしくするつもりで書く**  
  変数名や関数名に迷ったときは、
  「一週間後の自分が読んだらどう感じるか？」を想像してみると、
  自然とよい名前が浮かびやすくなります。

この付録の内容は、最初にすべて覚える必要はありません。
いったん「リファクタリングという考え方がある」と知っておいて、
コードが少し長くなってきたタイミングで、また読み返していただければうれしいです。

