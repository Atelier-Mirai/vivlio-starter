1. apply_frontmatter! YAMLフロントマター（--- ブロック）を生成または更新する。章番号・ファイル種別などのメタデータを付与。

2. strip_html_comments! <!-- ... --> を削除。複数行コメントにも対応。

3. process_data_streams! = books | tags=ruby のような QueryStream 記法を検出し、QueryStream.render でデータ展開する。コードブロック内はスキップ（QueryStream.render 内で制御）。

4. normalize_image_paths! ![alt](path) の画像パスを images/<章ディレクトリ>/ 配下に正規化。存在しない画像はSVGプレースホルダーのdata URIに置換。コードブロック内はスキップ。

5. validate_links_and_images! リンクと画像の整合性チェック（壊れたリンク等の警告）。

6. process_code_includes! ```include:path/to/file.rb ``` のような記法でソースコードファイルを取り込む。

7. normalize_html_block_boundaries! </small> 等のHTML閉じタグ直後にMarkdown記法が続く場合、空行を挿入してVFM/CommonMarkが正しく解釈できるよう調整。コードブロック内はスキップ。

8. escape_inline_code_html! インラインコード（`<h1>`）内のHTML予約文字（<, >等）をエスケープ。コードブロック内はスキップ。

9. transform_text_right_inlines! 行末の {.right} / {.text-right} を VFM の :::{.text-right} コンテナ記法に変換。コードブロック内はスキップ。

10. transform_book_cards! book-card ブロックをHTMLに変換し、内部のMarkdownをHTMLへ変換。

11. transform_table_rotations! table-rotate ブロックをHTMLに変換。

12. transform_links! 外部リンクを脚注（[^1]）に変換。

13. expose_container_footnotes! VFMコンテナ（:::{.sideimage}等）内の脚注参照をコンテナ外に露出させ、VFMが脚注定義を認識できるよう補助。

14. write_output! 加工済みコンテンツをファイルに書き出す。