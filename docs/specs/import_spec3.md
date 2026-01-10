# import_spec.md, import_spec2.md への補足

## markdownコードブロックへ言語指定を追加する

```
p {
  color: var(--sakurairo);
}
```

=>

```css
p {
  color: var(--sakurairo);
}
```

のように、もし言語指定がないコードブロックがあれば、
中のコードを参照し、適切な言語を付与する。

サンプルコードは次の通り。

```ruby
require 'rouge'

def detect_markdown_lang(code)
  lexer = Rouge::Lexer.guess(source: code)
  tag = lexer.tag

  # Markdownで一般的に使われる短いタグ名に変換するマッピング表
  mapping = {
    'javascript' => 'js',
    'typescript' => 'ts',
    'markdown'   => 'md',
    'plaintext'  => 'text', # 明示的にtextと出す
    'bash'       => 'zsh',  # シェルスクリプトはzshに寄せる
    'shell'      => 'zsh'
  }

  mapping.fetch(tag, tag)
end
```

rougeを導入するに当たり、`vs doctor -fix` の自動インストール機能にも、`rouge` を含めること。

- 既に言語指定があるコードブロックはそのまま維持で良い。

- Rouge が Lexer.guess できなかった場合（例外や nil）、text をデフォルトにする。

- コードブロック内に複数言語が混在するケース（例: shell + sample 出力）
    ```ruby
    # 1. 行頭に $ や % があれば、混在していても shell 扱いにする
    return 'zsh' if code.match?(/^[ \t]*[\$%][ \t]+/)

    # 2. それ以外は Rouge に任せる
    lexer = Rouge::Lexer.guess(source: code)
    ```

## 表紙画像の取得

```yml:config_starter.yml
starter: 
  frontcover_pdffile: hyoshi.pdf   # 表表紙（電子用のみ、印刷用にはつかない）
```

のように、frontcover_pdffileの記載があった場合には、

starter側の `/images/hyoshi.pdf`を、
vivlio-starter側の `covers/hyoshi.pdf` にコピーする。
（もし同名ファイルがあれば上書きして良い）

※ PDF 以外（PNG 等）が指定されていた場合は未対応（スキップ）で良い。

また、
```yml:config/book.yml
output:
  cover:
    front: hyoshi.pdf
```
のように、output.cover.frontを更新する。


## テストコードの実装

/Users/mirai/.claude/skills/ruby-refactoring/SKILL.md
に従い、importに関するコードをリファクタリングするとともに、minitestによる必要なテストスイーツを実装する。

- 既存 import コードのどの範囲までテスト対象は、post_process_markdown! 周辺を丁寧に、他はざっくりテストすれば良い。
- Minitest のテストランナーは既存 test/ ディレクトリに統合で良い。
- ruby-refactoring スキル指示に従う際、特に優先度の高いリファクタリング対象はない（というより、実質import.rbのみのリファクタリングである）。現状でも良いコードだが、６００行ほどあるので、責務の分離の観点から Markdown変換、画像処理、YAML操作に分けるようにすると見通しがよくなると思われる。またコメントを適切に付けることで、保守性を高めるようにせよ。
