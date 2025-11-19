= 連想配列

//abstract{
配列と並ぶ重要な**データ構造**に、 **連想配列** (ハッシュや辞書とも呼ばれます)があります。 @<fn>{hash}

//footnote[hash][JavaScriptでは連想配列(ハッシュ・辞書)と呼ばれる特別な種類があるのではなく、後ほど紹介する「オブジェクト」として扱われています。]

この章では、連想配列の基本的な使い方を学習します。
//}

== 連想配列

=== 連想配列の基礎

//list[][配列][1]{
// 配列の宣言と初期値設定
let scores = [85, 95, 85, 75]
//}

先に紹介した配列では、@<code>{0, 1, 2, 3} と言う添字で要素を指定する必要がありました。そのため、0番目の要素が国語であり、1番目の要素が算数であり、2番目の要素が理科であり、3番目の要素が社会であると言うことを把握しておく必要がありました。

把握しておくのも大変ですし、また、指定する添字を誤ってしまうと、当然違う科目の点数を得ることとなります。

「連想配列」では、@<code>{0, 1, 2, 3} と言う添字に代えて、@<code>{kokugo, sansuu, rika, shakai} という科目名で指定できるようになります。

//list[][連想配列][1]{
// 連想配列の宣言と初期値設定
let hash_scores = { kokugo: 85, sansuu: 95, rika: 85, shakai: 75 }
//}

== 連想配列要素の 取得・更新・追加・削除

=== 要素の取得

配列では、各要素の値(バリュー)を取得する為に添字を用いましたが、連想配列では、「キー(鍵)」を用いて、各要素の値（バリュー）を取得します。

国語の点数を取得する為には、キー @<code>{kokugo} を用いて、次のように書きます（@<code>{[]ブラケット}を使うので、ブラケット記法と呼ばれます）。

//list[][][1]{
// 要素の取得
hash_scores["kokugo"]
//}

連想配列の各要素にアクセスしやすいよう、@<code>{.} を用いるドット記法も用意されています。
//list[][][1]{
// 要素の取得
hash_scores.kokugo
//}

=== 要素の更新

要素の更新や追加は配列と同様に行えます。

国語の点数を95点に更新する例です。ブラケット記法、ドット記法、それぞれの例を示します。
//list[][][1]{
// 要素の更新
hash_scores["kokugo"] = 95
hash_scores.kokugo = 95
//}

=== 要素の追加

新しい要素を追加することも出来ます。
//list[][][1]{
// 要素の追加
hash_scores["programming"] = 100
hash_scores.programming = 100
//}

=== 要素の削除

連想配列の要素を削除するためには、@<code>{delete} 演算子を用います。

//list[][][1]{
// 要素の削除
delete hash_scores["shakai"]
delete hash_scores.shakai
//}

コンソール画面での実行例です。ぜひご自身で入力して確かめてください。
//image[hash][][width=80%]

== 連想配列と反復処理

=== @<code>{for...in文}で 合計点と平均点を求める

合計点と平均点を求めて見ましょう。

@<href>{https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Statements/for...in,for...in} 文は、配列の際の @<code>{for...of} 文 と同様、「連想配列の全ての要素」を処理する際に便利な繰り返しの為の構文です。

//list[][][1]{
// 連想配列を宣言 ＆ 初期データを投入
let hash_scores = { kokugo: 85, sansuu: 95, rika: 85, shakai: 75 }

// 合計点を、@<code>{for...in} 文を使って求める
let total = 0
for (let key in hash_scores) {
  let value = hash_scores[key]
  total += value
}

// 平均点を求める
let count = Object.keys(hash_scores).length
let average = total / count

// 結果を表示する
console.log(total)
console.log(average)
//}


配列の場合とほぼ同様のコードとなっておりますが、変更点をご案内します。

一般に 連想配列は、@<code>{hash = { key1: value1, key2: value2, key3: value3 ... \}} と、 @<code>{key} と @<code>{value} の組み合わせになっています。

6行目の @<code>{for (let key in hash_scores) {} では、連想配列の @<code>{key} が入ります。つまり、繰り返しの都度、@<code>{key} には @<code>{kokugo, sansuu, ... } など科目名が入ります。

ここで得られたキーを用いて、各科目の点数を取得しているのが、7行目のコード @<code>{let value = hash_scores[key]}です。

これで @<code>{value} には、各科目の点数が入りましたので、 @<code>{total} に足し込んで、合計点を求めることが出来ます。

//blankline

以上で合計点を求めることができましたが、平均点を求めるための処理である12, 13行目も解説します。

平均点を求める為には、合計点数を科目数で割る必要があります。4科目あるので4で割れば良いのです。配列の場合は要素数を @<code>{lenght} メソッドで取得することができましたが、連想配列の場合には、要素数を求めるメソッドは用意されていないため、少し手間をかける必要があります。

まず、 @<code>{Object.keys}メソッドにより 連想配列からキーのみを取り出した配列を作ります(@<code>{["kokugo", "sansuu", "rika", "shakai"]}という新しい配列が得られます)。
@<small>{(それが @<code>{Object.keys(hash_scores)} と書かれている部分です)}

次に、この取得したキー配列の要素数を求める為に、@<code>{lenght} メソッド を使います。
@<small>{(それが @<code>{Object.keys(hash_scores).length} と書かれている部分です)}

この二段構えで、連想配列の要素数（＝科目数）を取得することができたので、 @<code>{count} という変数に代入しています。

最後に 13 行目で、合計点を科目数で割って、平均点を求めることが出来ました。

//blankline
少し手間暇かかりますが、連想配列も、配列と並んでよく使われます。少しずつ習得なさってください。
