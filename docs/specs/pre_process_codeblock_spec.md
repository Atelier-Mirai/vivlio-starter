# pre_process メソッド群における、コード、ブロック除外処理の改善について

## 処理の概要
pre_process メソッド群においては、次のような処理を行っている。個別の処理がそれぞれコードブロックの除外処理を行っているので、リファクタリングを行い、より良い構造への改善を目指すとともに、不具合の解消を目指すものである。

1. apply_frontmatter! YAMLフロントマター（--- ブロック）を生成または更新する。章番号・ファイル種別などのメタデータを付与。

2. strip_html_comments! <!-- ... --> を削除。複数行コメントにも対応。

3. process_data_streams! = books | tags=ruby のような QueryStream 記法を検出し、QueryStream.render でデータ展開する。コードブロック内はスキップ（QueryStream.render 内で制御）。

- [x] 4. normalize_image_paths! ![alt](path) の画像パスを images/<章ディレクトリ>/ 配下に正規化。存在しない画像はSVGプレースホルダーのdata URIに置換。コードブロック内はスキップ。

5. validate_links_and_images! リンクと画像の整合性チェック（壊れたリンク等の警告）。

6. process_code_includes! ```include:path/to/file.rb ``` のような記法でソースコードファイルを取り込む。

- [x] 7. normalize_html_block_boundaries! </small> 等のHTML閉じタグ直後にMarkdown記法が続く場合、空行を挿入してVFM/CommonMarkが正しく解釈できるよう調整。コードブロック内はスキップ。

- [x] 8. escape_inline_code_html! インラインコード（`<h1>`）内のHTML予約文字（<, >等）をエスケープ。コードブロック内はスキップ。

- [x] 9. transform_text_right_inlines! 行末の {.right} / {.text-right} を VFM の :::{.text-right} コンテナ記法に変換。コードブロック内はスキップ。

10. transform_book_cards! book-card ブロックをHTMLに変換し、内部のMarkdownをHTMLへ変換。

11. transform_table_rotations! table-rotate ブロックをHTMLに変換。

12. transform_links! 外部リンクを脚注（[^1]）に変換。

13. expose_container_footnotes! VFMコンテナ（:::{.sideimage}等）内の脚注参照をコンテナ外に露出させ、VFMが脚注定義を認識できるよう補助。

14. write_output! 加工済みコンテンツをファイルに書き出す。


## 改善方針

`MarkdownUtils`に於て、既に、コードブロックの除外処理を実装していることから、これを各メソッドで共通して使うことにする。

使用方法は次の通りである。

```ruby
text, spans = MarkdownUtils.extract_code_spans(content)
# text に対して変換処理を行う（コードブロック内は触れない）
result = some_transform(text)
# 最後に元のコードブロックを復元
final = MarkdownUtils.restore_code_spans(result, spans)
```

## Ruby4.0標準開発スキル

開発にあたっては、以下の標準開発スキルに従うとする
[Ruby4.0標準開発スキル](ruby-development-standard.md)