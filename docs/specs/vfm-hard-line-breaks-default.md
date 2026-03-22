# VFM ハード改行デフォルト有効化仕様書

## 概要

Vivlio Starter で VFM（Vivliostyle Flavored Markdown）のハード改行機能をデフォルトで有効化し、日本語文章の執筆体験を向上させる仕様。

## 背景

### 現状の問題点
- Vivlio Starter では `hardLineBreaks` がデフォルト無効
- 日本語の自然な改行が `<br>` タグの手動記述が必要
- エンターでの改行がスペースとして扱われ、直感的でない
- 詩や歌詞などの表現が不自然

### 改善の目的
- 日本語文章の直感的な執筆体験の提供
- エンターでの改行をそのまま反映
- 技術的な箇所だけ個別に無効化できる柔軟性の確保

## 仕様

### 1. デフォルト設定の変更

#### 1.1 既定値のハードコーディング
`common.rb` の `merge_hardcoded_defaults` にVFM既定値を追加：

```ruby
def merge_hardcoded_defaults(cfg)
  cfg.merge(
    # 既存の既定値...
    vfm: default_vfm.merge(cfg[:vfm] || {})
  )
end

def default_vfm = {
  hardLineBreaks: true
}
```

#### 1.2 book.yml での明示的設定（オプション）
```yaml
vfm:
  hardLineBreaks: true
```

#### 1.3 既存プロジェクトへの配慮
- 既存の book.yml は変更されない
- 個別設定で既存動作を維持可能

### 2. 個別無効化機能

#### 2.1 フロントマターでの上書き
```markdown
---
vfm:
  hardLineBreaks: false
---
```

#### 2.2 マージ処理の優先順位
1. 既存フロントマターの設定を最優先
2. book.yml の明示的設定を補完
3. Common::CONFIG のハードコード既定値をフォールバック

### 3. 重要な注意点

#### 3.1 コードブロックへの影響
**hardLineBreaks 設定はコードブロックに影響しません**：

- **フェンスコードブロック** (```): 独立した要素として処理
- **インデントコードブロック**: 同様に独立した要素
- **インラインコード**: 影響を受けない

VFM公式ドキュメントによると、hardLineBreaksは「通常のテキスト段落」にのみ適用されます。

#### 3.3 変更不要の既存機能
- `frontmatter_generator.rb` のマージ処理は既存のままで対応可能
- フロントマターの `vfm.hardLineBreaks` 設定は既にサポート済み

#### 3.2 必要な変更
1. **Common::CONFIG 既定値追加**: `default_vfm` メソッドを追加
2. **frontmatter_generator.rb 強化**: VFM設定のマージ処理を明確化
3. **ドキュメント更新**: 新しいデフォルト動作を説明

## 使用シナリオ

### 1. 日本語の一般的な文章（デフォルト有効）
```markdown
---
title: "日本語の文章"
---

はじめまして。
Vivliostyle Flavored Markdown の世界へようこそ。
VFM は出版物の執筆に適した Markdown 方言です。
```

**出力結果**:
```html
<p>
  はじめまして。<br>
  Vivliostyle Flavored Markdown の世界へようこそ。<br>
  VFM は出版物の執筆に適した Markdown 方言です。
</p>
```

### 2. 技術的な説明文（個別無効化）

その文書全体で改行文字(エンター)を改行`<br>`ではなく、スペースとして扱いたい場合には、フロントマターに `hardLineBreaks: false` と記述します。

```markdown
---
vfm:
  hardLineBreaks: false
---

### 技術的な説明

この関数は引数を受け取り、
処理を実行して、
結果を返します。

複数行にわたる説明ですが、
改行はスペースとして扱われ、
自然な段落として表示されます。
```

**出力結果**:
```html
<h3>技術的な説明</h3>
<p>この関数は引数を受け取り、 処理を実行して、 結果を返します。 複数行にわたる説明ですが、 改行はスペースとして扱われ、 自然な段落として表示されます。</p>
```

### 3. 詩や歌詞（デフォルト有効のメリット）
```markdown
---
title: "詩の表現"
---

春風や
菜の葉の上を
渡る鳥

（芭蕉の句）
```

**出力結果**:
```html
<p>
  春風や<br>
  菜の葉の上を<br>
  渡る鳥
</p>
<p>
  （芭蕉の句）
</p>
```

**注**: 空行は通常通り段落分けとして扱われます（hardLineBreaks の影響を受けません）

## 互換性

### 既存プロジェクトへの影響
- **影響なし**: 既存の book.yml は変更されない
- **移行オプション**: 個別に無効化設定で既存動作を維持可能
- **段階的導入**: 新規プロジェクトから適用開始

### 他の VFM 環境との互換性
- **Vivliostyle CLI**: 標準的な VFM 挙動と一致
- **他のツール**: フロントマター設定で明示的に制御可能

## 実装計画

### Phase 1: 既定値設定の実装
1. `common.rb` に `default_vfm` メソッドを追加
2. `merge_hardcoded_defaults` でVFM設定をマージ

### Phase 2: フロントマター処理の強化
1. `frontmatter_generator.rb` でVFM設定のマージを明確化
2. 既存のマージ処理を活用して優先順位を保証

### Phase 3: テスト追加
1. デフォルト値（hardLineBreaks: true）が適用されるテスト
2. 日本語文章の改行が<br>タグに変換されるテスト
3. フロントマターで false に設定すると上書きされるテスト
4. デフォルト値と個別設定の優先順位テスト
5. コードブロックがhardLineBreaks設定の影響を受けないテスト
6. 空行の段落分けが正常に動作するテスト

### Phase 4: ドキュメント更新
1. `book-vivlio-starter/12-markdown-tutorial.md` の修正
2. ハード改行セクションの書き直し
3. 使用例の更新

### Phase 5: リリース
1. CHANGELOG.md の更新

## 品質保証

### テストケース
1. **個別無効化**: フロントマターで `false` に設定で上書きされる
2. **マージ処理**: 複数の設定が正しくマージされる

### リスク評価
1. **低リスク**: 既存のマージ機能を利用するのみ
2. **既存互換**: Common::CONFIG の既定値追加のみで既存コードに影響なし
3. **ロールバック容易**: 設定変更のみで元に戻せる

## ユーザーへの影響

### 利点
1. **直感的操作**: エンターでの改行がそのまま反映
2. **日本語最適**: 日本語文章の自然な表現が可能
3. **柔軟性**: 技術的な箇所だけ無効化できる
4. **学習コスト低減**: `<br>` タグの手動記述が不要


## 関連ドキュメント

- [VFM公式ドキュメント](https://vivliostyle.github.io/vfm/)
- [FrontmatterGenerator実装](../../../lib/vivlio/starter/cli/pre_process/frontmatter_generator.rb)
- [Markdownチュートリアル](../../../book-vivlio-starter/12-markdown-tutorial.md)

## 変更履歴

- 2026-03-22: 仕様書作成（初版）
