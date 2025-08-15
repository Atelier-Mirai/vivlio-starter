# Appendix-E コマンド／操作チートシート

:::{.chapter-lead}
頻出のコマンドと操作を最小限の説明でまとめました。安全に試せる順で並べ、破壊的操作には注意喚起を付けています。
:::

## よく使う Rake タスク（プロジェクト内）

| コマンド | 用途 | 補足 |
|---|---|---|
| `rake` | デフォルトの一括ビルド（`build` 実行） | 失敗時は下の個別手順で切り分け |
| `rake help` | 利用可能なタスクの一覧と説明 | `rake -T` 相当を置換 |
| `rake preprocess` | 前処理（画像パス付与・FM生成・コード取り込み） | ログで差分を確認 |
| `rake convert` | VFM→HTML 変換と post-replace | 正規表現置換が走る点に注意 |
| `rake toc` | 目次 `toc.html` 生成 | ブラウザ確認推奨 |
| `rake entries` | 章立て `entries.js` 生成 | 章追加後に実行 |
| `rake pdf` | PDF 生成 | 失敗時は画像/テンプレの項を参照 |
| `rake open` | 生成した PDF を開く | `pdf` のエイリアス |
| `rake clean` | 生成物のクリーンアップ | ビルド不整合時の切り札 |
| `rake build` | preprocess→convert→toc→entries→pdf→clean→open | 時間計測に便利 |
| `rake vivliostyle:generate_config` | `vivliostyle.config.js` 再生成 | 設定更新時 |
| `rake create[番号-スラッグ]` | 新規章の作成 | 例: `rake create[21-sample]` |
| `rake delete[番号]` | 章の削除 | 例: `rake delete[21]`（破壊的） |
| `rake renumber[旧,新]` | 章番号の変更/整列 | 例: `rake renumber[21,22]` |

Tips
- まず `rake clean && rake` で不整合を解消してから個別切り分け
- ログが抑制されている場合は verbose モードで再実行（必要なら）

## 作業フロー別ミニレシピ

### 新しい章を追加してビルド
1. `rake create[95-appendix-e]`
2. 原稿を書く（`contents/` 配下）
3. `rake` で一括ビルド → `rake open`

### ビルドが不安定/変更が反映されない
1. `rake clean`
2. 画像パス/存在を確認（特に PNG/JPG の拡張子）
3. `rake preprocess convert pdf`

### PDF 生成が落ちる
- 大きすぎる画像を圧縮/変換
- テンプレ/フロントマターの構文を確認

## よく使うコマンド断片（汎用）

| スニペット | 用途 |
|---|---|
| ``which <cmd>`` | 実体パスの確認 |
| ``echo $PATH`` | PATH の並び確認 |
| ``ls -l <file>`` | 権限/所有者 |
| ``curl -I <url>`` | ネットワーク到達性/ヘッダ |
| ``file <path>`` | 画像/文書の実拡張・エンコーディング確認 |

注意
- `delete` や `renumber` は破壊的になり得ます。実行前に Git 管理と差分確認を。

---
末尾メモ: 表のカラム幅は CSS（`stylesheets/appendix-e.css`）で調整できます。
