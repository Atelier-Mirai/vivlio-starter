## 執筆方針
各 work ディレクトリの役割

## work/
いまやったとおり、「骨組み＋グリッドで段取りをつける」章。
HTML の構造と CSS Grid の基礎に集中。

## work2/
見た目をぐっと誌面に近づけるステップとして扱うのがよさそうです。
おもなテーマ:
header / nav / hero / #recent / footer の「見栄え」と余白
フォント（本文・見出し）、色（和色のカスタムプロパティ）、背景グラデーション
カードの角丸・影・ホバー時のわずかな変化 など
ここまでは 1 枚の 
style.css
 のまま にしておくと、読者の負担が少ないです。
google fonts の導入 font-family: "Yuji Boku", serif;
.catch_phrase, .sub_title, circle.svg が前に来るように、.hero img に z-index: -1で背面にする

### media query
work2 では：
本格的な media query はまだ入れず、
「モバイルを基準に整えておき、デスクトップ向けの調整は次のステップで」という予告＋考え方にとどめる。
もし入れるとしても、1 つだけごく簡単な例（@media (min-width: 768px) で #recent を 3 列にするとか）に絞る。（media query は range query で実装する）

work3 で：
iPhone 向けの layout を起点に、
@media (width >= 768px)で
ヘッダーのレイアウト切り替え
hero の横並び・余白
#recent の列数変更
といった「きちんとしたレスポンシブ対応」をまとめて扱う。


### work2 での nested CSS の扱い方
位置づけ
「本編」はフラットな CSS だけで完結。
章末に「発展：nested CSS で同じコードを書くと？」という小見出しを用意し、work3 への橋渡しにする。
題材にするコードの候補
work2/style.css のうち、階層関係が分かりやすいものを 1〜2 個だけ：
例1: .sub_title a:hover まわり
例2: section#recent article:not(.link.disable) img:hover まわり
まずフラット版を再掲し、その直後に「nested 版」を並べて示す構成にすると違いが一目で分かります。
説明の軸
「書き方は変わるが、ブラウザでの見た目・働きは同じ」ことを強調。
& の意味だけを最小限に説明：
&:hover は「親セレクタの :hover」
&::before は「親セレクタの ::before」
「work3 では、この書き方を全面的に使ってコードを整理していきます」と一言入れて、次の章にバトンを渡す。


## work3/
設計とモダン化に踏み込む仕上げステップとして:
CSS の分割（master.css ＋ _colors.css, _layout.css, _hero.css, _recent.css, _footer.css など）
design_tokens の説明

モバイルファーストの media query でデスクトップ版まで整える
追加の効果（トランジション、ボタンのホバー、微妙なシャドウ、clamp() など）
「プロジェクトとして育てていくときの書き方」の見本、という位置づけにできます。_
link.disable が付いている article はホバー効果を付けない (index.html側にクラス付与)
topへ戻るボタンに、金色のボタンになるようにcss追加, js追加
.catch_phraseがキラキラするように、css追加,js追加
@acab/reset.css導入
fontawesome導入

## まとめ
work：レイアウトの発想転換（グリッド）
work2：ビジュアルを整える楽しさ
work3：設計とレスポンシブという「一段上の世界」
という三段階がきれいに分かれます。

