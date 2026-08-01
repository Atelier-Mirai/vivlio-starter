# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/index_match_scanner'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexMatchScannerTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('match_scanner_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('contents')
          FileUtils.mkdir_p('config')
          @scanner = IndexMatchScanner.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: scan_and_tag_file! tests ---

        def test_scan_detects_term_with_yomi
          File.write('01-test.md', <<~MD)
            # Test

            [Ruby|るびー]は素晴らしい言語です。
          MD

          @scanner.scan_and_tag_file!('01-test.md')

          assert_equal 1, @scanner.matches.size
          assert_equal 'Ruby', @scanner.matches[0]['term']
          assert_equal 'るびー', @scanner.matches[0]['yomi']
        end

        def test_scan_detects_term_without_yomi
          File.write('02-test.md', <<~MD)
            # Test

            [JavaScript]を学びましょう。
          MD

          @scanner.scan_and_tag_file!('02-test.md')

          assert_equal 1, @scanner.matches.size
          assert_equal 'JavaScript', @scanner.matches[0]['term']
        end

        def test_scan_excludes_markdown_links
          File.write('03-test.md', <<~MD)
            # Test

            [リンクテキスト](https://example.com)はスキップされる。
            [索引語]は検出される。
          MD

          @scanner.scan_and_tag_file!('03-test.md')

          assert_equal 1, @scanner.matches.size
          assert_equal '索引語', @scanner.matches[0]['term']
        end

        def test_scan_excludes_footnote_references
          File.write('04-test.md', <<~MD)
            # Test

            脚注参照[^1]はスキップされる。
            [有効な用語]は検出される。

            [^1]: 脚注の内容
          MD

          @scanner.scan_and_tag_file!('04-test.md')

          term_names = @scanner.matches.map { it['term'] }
          refute_includes term_names, '^1'
          assert_includes term_names, '有効な用語'
        end

        def test_scan_excludes_inline_footnote_bodies
          # `^` はブラケットの外側にあるため、参照脚注 [^1] を落とす条件では
          # 除外できない。脚注本文が索引語として登録されるのを防ぐ
          # （inline-footnote-index-collision-spec.md §3.2）
          File.write('06-test.md', <<~MD)
            # Test

            本文です^[この 49 ページというずれです]。
            [有効な用語]は検出される。
          MD

          @scanner.scan_and_tag_file!('06-test.md')

          term_names = @scanner.matches.map { it['term'] }
          refute_includes term_names, 'この 49 ページというずれです'
          assert_includes term_names, '有効な用語'
        end

        def test_scan_leaves_inline_footnote_markup_untouched
          File.write('07-test.md', "# Test\n\n本文です^[短い補足]。\n")

          @scanner.scan_and_tag_file!('07-test.md')

          assert_includes File.read('07-test.md'), '^[短い補足]',
                          'インライン脚注の記法がタグ付けで壊されてはならない'
        end

        def test_scan_tags_first_occurrence_with_dfn
          File.write('05-test.md', <<~MD)
            # Test

            [Ruby]は初出です。
            [Ruby]は2回目です。
          MD

          @scanner.scan_and_tag_file!('05-test.md')

          assert_equal 2, @scanner.matches.size
          assert_equal 'dfn', @scanner.matches[0]['tag_type']
          assert_equal 'span', @scanner.matches[1]['tag_type']
        end

        def test_scan_excludes_code_blocks
          File.write('06-test.md', <<~MD)
            # Test

            ```ruby
            [コードブロック内]は除外される
            ```

            [本文の用語]は検出される。
          MD

          @scanner.scan_and_tag_file!('06-test.md')

          term_names = @scanner.matches.map { it['term'] }
          refute_includes term_names, 'コードブロック内'
          assert_includes term_names, '本文の用語'
        end

        # インラインコード `[!]` 内の [...] は明示マーカー [用語] と誤認せずリテラル表示する。
        # コメント強調マーカー [!] を説明する地の文（`[!]` マーカー…）が索引語化される回帰を防ぐ。
        def test_scan_skips_index_marker_inside_inline_code
          File.write('14-inline.md', <<~MD)
            # Test

            コメントに `[!]` マーカーを書くと強調されます。
            バックティックの外の [本文用語] は検出される。
          MD

          @scanner.scan_and_tag_file!('14-inline.md')

          term_names = @scanner.matches.map { it['term'] }
          refute_includes term_names, '!', 'インラインコード内の [!] は索引語化しない'
          assert_includes term_names, '本文用語'

          tagged = File.read('14-inline.md')
          assert_includes tagged, '`[!]`', 'インラインコードの内容は保持される'
        end

        # ````（4連）で ``` を入れ子にしたコード例の中の [!] は索引語化しない。
        # フェンス長を見ないと内側 ``` で閉じたと誤判定し、コード本文を地の文として
        # 索引スキャンしてしまう（コメント強調 [!] が誤索引化される）回帰を防ぐ。
        def test_scan_excludes_nested_quadruple_backtick_fence
          File.write('15-fence.md', <<~MD)
            # Test

            ````markdown
            ```ruby
            puts "x"   # [!] この行が強調される
            ```
            ````

            フェンスの外の [本文用語] は検出される。
          MD

          @scanner.scan_and_tag_file!('15-fence.md')

          term_names = @scanner.matches.map { it['term'] }
          refute_includes term_names, '!', '4連フェンス内の [!] は索引語化しない'
          assert_includes term_names, '本文用語'

          tagged = File.read('15-fence.md')
          assert_includes tagged, '# [!] この行が強調される', 'コード例の内容は保持される'
        end

        def test_scan_handles_special_characters
          File.write('07-test.md', <<~MD)
            # Test

            [!]は否定演算子です。
            [&&]は論理積演算子です。
            [||]は論理和演算子です。
            [404]はエラーコードです。
          MD

          @scanner.scan_and_tag_file!('07-test.md')

          term_names = @scanner.matches.map { it['term'] }
          assert_includes term_names, '!'
          assert_includes term_names, '&&'
          assert_includes term_names, '||'
          assert_includes term_names, '404'
        end

        def test_scan_handles_html_like_terms
          File.write('08-test.md', <<~MD)
            # Test

            [<h1>]は見出しタグです。
            [</h1>]は閉じタグです。
            [!DOCTYPE]はHTML宣言です。
          MD

          @scanner.scan_and_tag_file!('08-test.md')

          term_names = @scanner.matches.map { it['term'] }
          assert_includes term_names, '<h1>'
          assert_includes term_names, '</h1>'
          assert_includes term_names, '!DOCTYPE'
        end

        # --- phase: read_only mode tests ---

        def test_scan_read_only_does_not_modify_file
          original_content = "[Ruby]は素晴らしい。\n"
          File.write('contents/09-test.md', original_content)

          @scanner.scan_and_tag_file!('contents/09-test.md', read_only: true)

          assert_equal original_content, File.read('contents/09-test.md')
          assert_equal 1, @scanner.matches.size
        end

        def test_scan_non_read_only_modifies_file
          File.write('10-test.md', "[Ruby]は素晴らしい。\n")

          @scanner.scan_and_tag_file!('10-test.md', read_only: false)

          content = File.read('10-test.md')
          assert_includes content, '<dfn'
          assert_includes content, 'class="index-term"'
        end

        # --- phase: scan_all_chapters! tests ---

        def test_scan_all_chapters_saves_matches
          # 前処理済み中間 .md はワークスペースの html/ に置かれる（P4 §3.4-1）
          FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
          File.write(File.join(Common::BUILD_HTML_DIR, '11-a.md'), "[用語A]を説明。\n")
          File.write(File.join(Common::BUILD_HTML_DIR, '12-b.md'), "[用語B]を説明。\n")

          @scanner.scan_all_chapters!(%w[11-a 12-b])

          assert File.exist?(Common::INDEX_MATCHES_FILE)
          data = YAML.load_file(Common::INDEX_MATCHES_FILE)
          assert_equal 2, data['total_matches']
        end

        # --- phase: auto indexing with config tests ---

        def test_scan_applies_config_terms
          config_content = <<~YAML
            terms:
              - term: Ruby
                yomi: るびー
                pattern: "/Ruby/"
                flags: i
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          # 新しいスキャナを作成（configを読み込むため）
          scanner = IndexMatchScanner.new
          File.write('13-test.md', "Rubyは素晴らしい言語です。\n")

          scanner.scan_and_tag_file!('13-test.md')

          assert scanner.matches.any? { it['term'] == 'Ruby' }
        end

        # --- phase: manual markup + ig flags (no double tagging) ---

        def test_manual_markup_with_ig_flag_no_double_tagging
          # 天衣無縫 が flags: ig で登録されている場合
          config_content = <<~YAML
            terms:
              - term: 天衣無縫
                yomi: てんいむほう
                flags: ig
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          File.write('01-life.md', "「[天衣無縫]」は素晴らしい。\n")

          scanner.scan_and_tag_file!('01-life.md')

          tagged = File.read('01-life.md')
          # HTML タグが属性内で二重展開されていないこと
          refute_match(/class="index-term".*class="index-term"/, tagged)
          # glossary-link のhref属性内にindex-termタグが混入していないこと
          refute_match(/href="[^"]*class="index-term"/, tagged)
          # 天衣無縫 の索引タグが1回だけ存在すること
          assert_equal 1, tagged.scan(/class="index-term"/).size
        end

        # --- phase: 保護トークンの入れ子復元（html_token 露出回帰） ---

        # 退避トークンが最終出力に残っていないことを検査する。
        # 旧実装の `[[HTML_TOKEN_n]]` 形式と現行の NUL 区切り形式の両方を見る
        # （形式が変わってもこの回帰検査が空振りしないように）。
        def refute_leftover_token(text, message)
          refute_match(/\[\[(?:HTML|IDX|RUBY|CODE|GLS_HTML|GLS_RUBY|GLS_CODE)_\d+\]\]/, text, message)
          refute_includes text, IndexMatchScanner::LineMask::SENTINEL, message
        end

        # インラインコード内に HTML タグ様の文字列（例: `vs build <章名>`）があると、
        # 保護トークンが入れ子（CODE が HTML を内包）になる。復元を挿入順（FIFO）で行うと
        # `[[HTML_TOKEN_n]]` が最終出力へ残留する（KNOWN_ISSUES の html_token 問題）。
        # 逆順（LIFO）復元で残留しないこと・コード内容が保持されることを検証する。
        def test_inline_code_with_html_like_tag_leaves_no_token
          config_content = <<~YAML
            terms:
              - term: ビルド
                yomi: びるど
                flags: i
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          File.write('11-workflow.md', "| | `vs build <章名>` | 章単位で素早く確認 |\n")

          scanner.scan_and_tag_file!('11-workflow.md')

          tagged = File.read('11-workflow.md')
          refute_leftover_token(tagged, '保護トークンが最終出力に残留してはならない')
          assert_includes tagged, '`vs build <章名>`', 'インラインコードの内容が保持されること'
        end

        # 用語集のみ（flags: g）の経路も同じ入れ子復元バグを持つため回帰検証する。
        def test_glossary_only_inline_code_with_html_like_tag_leaves_no_token
          config_content = <<~YAML
            terms:
              - term: WWW
                yomi: WWW
                flags: g
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          File.write('08-web.md', "WWW の例は `<a href=\"x\">` のように書く。\n")

          scanner.scan_and_tag_file!('08-web.md')

          tagged = File.read('08-web.md')
          refute_leftover_token(tagged, '用語集のみ経路でも保護トークンが残留してはならない')
          assert_includes tagged, '`<a href="x">`', 'インラインコードの内容が保持されること'
        end

        # --- phase: 退避内容の逐語復元（バックスラッシュ破損回帰） ---

        # 退避した内容を `gsub!(token, original)` で戻すと、置換文字列中の `\`` が
        # 「マッチ前の文字列」参照として解釈され、行頭が重複して混入する（実害あり・
        # 2026-07-26 に原稿 3 章で発生していた）。`\` を含むインラインコードでも
        # 原文が逐語で戻ることを検証する。
        def test_inline_code_containing_backslash_is_restored_verbatim
          config_content = <<~YAML
            terms:
              - term: エスケープ
                yomi: えすけーぷ
                flags: i
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          line = "記号は `\\*` のように `\\` を前置してエスケープします。\n"
          File.write('21-markdown.md', line)

          scanner.scan_and_tag_file!('21-markdown.md')

          tagged = File.read('21-markdown.md')
          assert_includes tagged, '`\\*`', 'バックスラッシュを含むインラインコードが保持されること'
          assert_includes tagged, '`\\`', '単独のバックスラッシュのインラインコードが保持されること'
          assert_equal 1, tagged.scan('記号は').size, '行頭が重複して混入してはならない'
          assert_includes tagged, 'class="index-term"', '用語のタグ付け自体は行われること'
        end

        # --- phase: 生成タグの遮蔽（保護を 1 回化しても等価であること） ---

        # 生成した索引タグには class="index-term" のような英字が含まれるため、
        # 後続の用語（例: index）がタグの属性内へ食い込みうる。退避を用語ごとに
        # やり直す旧方式と、生成タグを即退避する現行方式は、この遮蔽において等価。
        def test_generated_tag_is_not_matched_by_later_terms
          config_content = <<~YAML
            terms:
              - term: Ruby
                yomi: るびー
                flags: i
              - term: index
                yomi: いんでっくす
                flags: i
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          File.write('31-terms.md', "Ruby の index を作ります。\n")

          scanner.scan_and_tag_file!('31-terms.md')

          tagged = File.read('31-terms.md')
          # Ruby と index の 2 語ぶんだけタグが付く（生成タグの属性内に増殖しない）
          assert_equal 2, tagged.scan(/class="index-term"/).size
          refute_match(/class="<(?:span|dfn)/, tagged, '属性内にタグが入り込んではならない')
          refute_match(/data-yomi="[^"]*<(?:span|dfn)/, tagged, '属性内にタグが入り込んではならない')
        end

        # --- phase: contents/ protection ---

        def test_contents_files_are_never_written_to
          File.write('contents/01-test.md', "[Ruby]は素晴らしい。\n")
          original = File.read('contents/01-test.md')

          @scanner.scan_and_tag_file!('contents/01-test.md', read_only: false)

          # read_only: false でも contents/ 内のファイルは書き換えられない
          assert_equal original, File.read('contents/01-test.md')
        end

        # --- phase: glossary-only backlink ---

        def test_glossary_only_term_gets_backlink
          config_content = <<~YAML
            terms:
              - term: WWW
                yomi: WWW
                flags: g
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          File.write('08-web.md', "WWWは世界中に広がっている。\n")

          scanner.scan_and_tag_file!('08-web.md')

          tagged = File.read('08-web.md')
          # 用語集リンク（†）が追加されていること
          assert_match(/glossary-link/, tagged)
          # 索引タグは追加されないこと（flags: g のみ）
          refute_match(/class="index-term"/, tagged)
        end

        # --- phase: 辞書は読み取り専用（R1）・バックリンクは中間 YAML へ（R2） ---

        # R1: スキャンは config/index_glossary_terms.yml を一切書き換えない
        def test_scan_all_chapters_does_not_modify_dictionary
          config_content = <<~YAML
            terms:
              - term: WWW
                yomi: WWW
                flags: g
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
          File.write(File.join(Common::BUILD_HTML_DIR, '08-web.md'), "WWWは世界中に広がっている。\n")

          scanner.scan_all_chapters!(['08-web'])

          assert_equal config_content, File.read('config/index_glossary_terms.yml'),
                       'ビルドスキャンで辞書が汚れてはならない（git クリーン保証）'
        end

        # R2: 用語集バックリンクは辞書ではなく中間 YAML（_index_matches.yml）へ書かれる
        def test_scan_all_chapters_saves_glossary_backlinks_to_matches_file
          config_content = <<~YAML
            terms:
              - term: WWW
                yomi: WWW
                flags: g
          YAML
          File.write('config/index_glossary_terms.yml', config_content)

          scanner = IndexMatchScanner.new
          FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
          File.write(File.join(Common::BUILD_HTML_DIR, '08-web.md'), "WWWは世界中に広がっている。\n")

          scanner.scan_all_chapters!(['08-web'])

          data = YAML.load_file(Common::INDEX_MATCHES_FILE)
          backlinks = data['glossary_backlinks']
          assert backlinks.key?('WWW'), 'バックリンクが中間 YAML に保存されること'
          assert_equal '08-web', backlinks['WWW'].first['chapter']
          assert backlinks['WWW'].first['anchor_id'].start_with?('gls-src-08-web-')
        end

        # --- phase: find_chapter_file tests ---

        def test_find_chapter_file_prefers_workspace_by_default
          # 前処理済み（ワークスペース html/）を優先する（P4 §3.4-1）
          workspace_md = File.join(Common::BUILD_HTML_DIR, 'chapter.md')
          FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
          File.write(workspace_md, 'workspace content')
          File.write('contents/chapter.md', 'contents content')

          result = @scanner.find_chapter_file('chapter', prefer_contents: false)

          assert_equal workspace_md, result
        end

        def test_find_chapter_file_prefers_contents_when_specified
          FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
          File.write(File.join(Common::BUILD_HTML_DIR, 'chapter.md'), 'workspace content')
          File.write('contents/chapter.md', 'contents content')

          result = @scanner.find_chapter_file('chapter', prefer_contents: true)

          assert_equal 'contents/chapter.md', result
        end

        def test_find_chapter_file_returns_nil_when_missing
          result = @scanner.find_chapter_file('nonexistent')

          assert_nil result
        end
      end
    end
  end
end
