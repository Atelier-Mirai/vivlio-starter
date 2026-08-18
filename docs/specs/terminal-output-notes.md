# ターミナル出力の知見メモ

> 対象: `vs` が端末へ出す文字列（絵文字・桁揃え・進行表示）
> 位置づけ: 実測で確定した事実を残す恒久メモ。仕様書ではないので archives へは移さない

## 1. 絵文字は「異体字セレクタなし・EAW=W」のものだけを使う

### 症状

`⚠️` だけが端末で**半角幅で描かれ**、行頭の桁が揃わない。表や箇条書きの縦位置が崩れる。

### 原因

`⚠️` は 1 文字ではなく **2 コードポイント**である。

| 表示 | 符号位置 | East Asian Width | 幅 |
|---|---|---|---|
| ✅ | U+2705 | **W** | 全角固定 |
| ❌ | U+274C | **W** | 全角固定 |
| 📚 | U+1F4DA | **W** | 全角固定 |
| 🔴 🟡 | U+1F534 / U+1F7E1 | **W** | 全角固定 |
| ❗ | U+2757 | **W** | 全角固定 |
| **⚠️** | U+26A0 **＋ U+FE0F** | **N** | **端末依存** |
| **ℹ️** | U+2139 **＋ U+FE0F** | **N** | **端末依存** |

`⚠` `ℹ` はもともと**文字記号**（EAW=N）で、後ろの異体字セレクタ VS16（U+FE0F）が
「絵文字として描け」と指示しているだけである。**幅をどう数えるかは規定されておらず端末実装に委ねられる**
ため、絵文字の見た目で描きながら幅は 1 と数える端末がある。

### 規則

**CLI 出力に使う絵文字は、単一コードポイントで `East Asian Width = W` のものに限る。**
新しいアイコンを足すときは必ず確認する。

```bash
python3 -c "import unicodedata as u; s='❗'; print(len(s), [hex(ord(c)) for c in s], u.east_asian_width(s[0]))"
# → 1 ['0x2757'] W   … 1 文字・W なら安全
```

コードベース全体を洗うには:

```bash
python3 - <<'PY'
import re, unicodedata as ud, pathlib, collections
pat = re.compile('[℀-➿⬀-⯿\U0001F000-\U0001FAFF]️?')
bad = collections.Counter()
for p in pathlib.Path('lib/vivlio_starter').rglob('*.rb'):
    for m in pat.finditer(p.read_text(encoding='utf-8')):
        if ud.east_asian_width(m.group()[0]) != 'W':
            bad[m.group()] += 1
for s, n in bad.most_common():
    print(s, ' '.join(f"U+{ord(c):04X}" for c in s), n)
PY
```

矢印（`→` U+2192）などの EAW=A は対象外。あれは絵文字ではなく記号で、端末で 1 幅が期待値。

### 現在の語彙（`Common#log_result` ほか）

| 用途 | 絵文字 | 意味 |
|---|---|---|
| 成功 | ✅ | 結末・問題なし |
| 警告 | ❗ | 結末・要対応だが処理は成立 |
| 失敗 | ❌ | 結末・エラーあり |
| 成果物 | 📚 | 生成したファイルの一覧 |
| エラー行 | 🔴 | 逐次ログ・章別サマリー |
| 警告行 | 🟡 | 逐次ログ・章別サマリー |
| 情報 | 💡 | 知っておくと役立つ補足 |
| 集計 | 🔍 | 検証結果のサマリー |
| 確認 | ❓ | 取り返しのつかない操作の前 |

`⚠️` は 2026-08-03 に `❗` へ、`ℹ️` は `💡` へ置き換えた。**どちらも復活させない。**

## 2. 進行表示は「何をしているか」を名乗る

`vs preflight` のスピナーが「ビルド中: …」と出していた（`UnifiedBuildPipeline` 共通の
文言だったため）。preflight は原稿を検査するだけで何も組まないので、**出力物ができると
誤解させ、実行を止める判断を誤らせる**。

`pipeline.rb` の `PROGRESS_VERB` でモード別に切り替える（`:preflight` → 「点検中」）。
新しいモードを足すときはここも見る。

## 3. `lib/` で `Kernel#warn` を呼んではならない

`bin/vs` は起動時に `RUBYOPT=-W0` を付けて自身を再実行しており、**`-W0` は処理系の
警告だけでなく `Kernel#warn` の出力も丸ごと捨てる**（`ruby -W0 -e 'warn "x"'` は無出力）。
`warn` で書いたメッセージは `vs` 経由で 1 行も表示されない。

| 文脈 | 使うもの |
| :--- | :--- |
| 例外・シグナルのハンドラ（`startup.rb`） | `$stderr.puts`（**最後の砦**。`Common` が壊れていても動き、ログレベルにも左右されない） |
| 通常の警告 | `Common.log_warn`（🟡 の体裁とログレベル制御が揃う。出力先は **stdout**） |

`contract/warning_delivery_test.rb` の WD-05 が `lib/` を grep して固定している。
**`VS_DEBUG=1` を付けると再実行がスキップされて警告が復活する**ので、手動確認は
素の `vs` で行う。詳細は `cli-warning-delivery-spec.md`（archives）。
