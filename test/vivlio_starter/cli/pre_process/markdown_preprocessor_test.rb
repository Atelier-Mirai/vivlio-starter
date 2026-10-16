# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/pre_process/markdown_preprocessor'
require 'vivlio_starter/cli/token_resolver'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 索引記法の展開（strip_index_markup!）のテスト。
      # inline-footnote-index-collision-spec.md §3.1 / §5 に対応する。
      class MarkdownPreprocessorTest < Minitest::Test
        def setup
          @temp_dir = Dir.mktmpdir('markdown_preprocessor_test')
          @md_path = File.join(@temp_dir, '50-sample.md')
          File.write(@md_path, "# 見出し\n")
          @entry = CLI::TokenResolver::Entry.new(
            number: '50', slug: 'sample', kind: :chapter, label: 'サンプル',
            path: @md_path, exists: true, in_catalog: true, valid: true
          )
        end

        def teardown = FileUtils.rm_rf(@temp_dir)

        # 索引記法の展開だけを通した結果を返す。
        # 索引・用語集が**無効**なときの経路（＝素のテキストへ落とす代替）を見る。
        # 有効なときは索引スキャナがタグを付けるので、ここは何もしない（下の
        # test_should_keep_index_markup_when_index_enabled が担当）。
        def strip(markdown, index_enabled: false)
          Common.stub(:index_enabled?, index_enabled) do
            pre = MarkdownPreprocessor.new(@md_path, @entry)
            pre.context.content = markdown
            pre.send(:strip_index_markup!)
            pre.context.content
          end
        end

        # --- phase: 索引が有効なら記法を温存する（スキャナがタグを付ける） ---

        # 前処理（Step 3）は索引スキャン（Step 4）より先に走る。ここで括弧を外すと
        # スキャナが記法を見る前に消えてしまい、**著者が明示した索引語が 1 つも
        # 登録されない**（index-markup-plain-fallback-spec.md §2.1）。
        def test_should_keep_index_markup_when_index_enabled
          source = '[Ruby]は言語です。[標準入出力|ひょうじゅん]もあります。'

          assert_equal source, strip(source, index_enabled: true)
        end

        # --- phase: 索引が無効ならプレーンテキストへ展開する ---

        def test_should_expand_index_markup_to_plain_text
          assert_equal 'Rubyは言語です。', strip('[Ruby]は言語です。')
          assert_equal '標準入出力について。', strip('[標準入出力|ひょうじゅん]について。')
        end

        # タグの形をした語を素通しすると生 HTML として VFM に渡り、本物の見出しになる
        def test_should_escape_tag_shaped_term_when_expanding
          assert_equal '&lt;h1&gt;は、見出しタグです。', strip('[<h1>]は、見出しタグです。')
        end

        # --- phase: 他の記法のブラケットには触らない ---

        # 表の見出しの「幅 [mm]」は単位の表記。索引を切っていても角かっこごと残す（改善案 #99）
        def test_should_keep_short_alphanumeric_brackets_intact
          assert_equal '幅 [mm] と解像度 [px]。', strip('幅 [mm] と解像度 [px]。')
          assert_equal 'OS の話。', strip('[OS|OS] の話。')
        end

        def test_should_keep_inline_footnote_intact
          # ブラケットだけ剥がすと脚注本体が本文へ流れ込み、脚注末尾の「。」と
          # 本文の「。」が重なる（`安全です。。`）のが元の症状（spec §1）
          source = '…356 枚目にあたります^[この 49 ページというずれです。]。'

          assert_equal source, strip(source)
        end

        def test_should_keep_consecutive_inline_footnotes_intact
          source = 'A^[補足1]とB^[補足2]。'

          assert_equal source, strip(source)
        end

        def test_should_keep_footnote_reference_and_definition_intact
          assert_equal '本文です[^ref1]。', strip('本文です[^ref1]。')
          assert_equal '[^ref1]: 参照の定義', strip('[^ref1]: 参照の定義')
        end

        def test_should_keep_links_and_images_intact
          source = '[公式](https://example.com)と ![図](img.png)'

          assert_equal source, strip(source)
        end

        # --- phase: コード内の記法解説は壊さない ---

        def test_should_not_expand_index_markup_inside_code
          source = "`[Ruby]` と書きます。\n\n```markdown\n[Ruby]は言語です。\n```\n"

          assert_equal source, strip(source)
        end

        # --- phase: 脚注本体の中の索引記法は従来どおり展開する ---

        def test_should_expand_index_markup_nested_in_footnote_body
          assert_equal '本文^[これはRubyの話]。', strip('本文^[これは[Ruby]の話]。')
        end

        # --- phase: 数式の中のブラケットは印ではない（改善案 #115） ---

        # 数式の SVG 化が使えない環境では数式が素のまま残る。単位の [\Omega] を剥がすと式が変わる
        def test_should_keep_brackets_inside_math_when_expanding
          source = "$$R = 5\\,[\\Omega]$$ と $[\\text{W}]$ と [電力]。\n"

          assert_equal "$$R = 5\\,[\\Omega]$$ と $[\\text{W}]$ と 電力。\n", strip(source)
        end

        # --- phase: 数式の SVG 化を飛ばす警告（mathjax-full が見つからないとき） ---

        # 数式のある章に当たったとき 1 度だけ、入れるべきものと入れ方を添えて知らせる。
        # 数式の無い章では出さない（以前は全章で「mathematical gem が無い」と並んでいた）
        def test_should_warn_once_about_missing_mathjax_only_for_chapters_with_math
          MarkdownPreprocessor.math_renderer_warned = nil
          out, = capture_io do
            MathTransformer.stub(:available?, false) do
              ["数式の無い章です。\n", "式 $a^2$ があります。\n", "式 $$b$$ もあります。\n"].each do |markdown|
                pre = MarkdownPreprocessor.new(@md_path, @entry)
                pre.context.content = markdown
                pre.send(:transform_math!)
              end
            end
          end

          assert_equal 1, out.scan('mathjax-full が見つからないため').size
          assert_includes out, 'vs doctor --fix で入れられます'
          refute_includes out, 'mathematical gem'
        ensure
          MarkdownPreprocessor.math_renderer_warned = nil
        end
      end
    end
  end
end
