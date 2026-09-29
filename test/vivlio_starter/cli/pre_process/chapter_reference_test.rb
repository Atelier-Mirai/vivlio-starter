# frozen_string_literal: true

# ================================================================
# Test: chapter_reference_test.rb
# ================================================================
# 検証内容（chapter-reference-spec.md）:
#   - 暗黙の章ラベル `ch-<スラッグ>` の収集（§1.1・§2.4・§2.8）と章題のアンカー（§3.2）
#   - @ch- / @pageref:ch- / @chapref:ch- の表示（§1.2・§2.11）
#   - 同じ段落の二度目のページ番号を省く（§2.9）
#   - 書き誤りの知らせ（§1.3・§2.4・§2.5・§2.7）と「前の章」の検査（§2.10）
#   - vs rename の追随（§2.2）
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/loader'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    class ChapterReferenceLabelTest < Minitest::Test
      XR = PreProcessCommands::CrossReferenceProcessor

      def test_should_collect_implicit_chapter_label_from_file_slug
        content = "# ビルド\n\n## 節 @build-steps\n"

        labels = XR.collect_labels(content, '44-build.md', '7', chapter_number_text: '第7章')[:labels]
        label = labels.find { it.id == 'ch-build' }

        assert_equal :chap, label.type
        assert_equal 'ビルド', label.title
        assert_equal '第7章', label.number
        assert_equal 1, label.line
        assert(labels.any? { it.id == 'build-steps' }, '見出しラベルは従来どおり集まる')
      end

      # 番号でラベルを作ると改番のたびに参照が切れるので、スラッグのない章には付けない（§2.4）
      def test_should_not_label_chapter_without_slug
        labels = XR.collect_labels("# はじめの一歩\n", '11.md', '1')[:labels]

        assert_empty labels
      end

      # 章題の中のタグや記号は、表示文字列から除く（§2.8）
      def test_should_strip_tags_from_chapter_title
        labels = XR.collect_labels("# 挑戦することの<br>贈り物\n", '97-sample.md', '97')[:labels]

        assert_equal '挑戦することの贈り物', labels.first.title
      end

      # 章題は最初の第 1 レベルの見出しだけ。コードの中の `# ` はコメントなので見ない
      def test_should_use_first_h1_outside_code
        content = "```ruby\n# コメント\n```\n\n# 本当の章題\n\n# 二つめ\n"

        labels = XR.collect_labels(content, '44-build.md', '7')[:labels]

        assert_equal ['本当の章題'], labels.map(&:title)
      end

      # `ch-` は暗黙の章ラベルの予約。手で付けると 🔴（§2.5）
      def test_should_reject_hand_written_chapter_prefix
        result = nil
        out, = capture_io { result = XR.collect_labels("## 節 @ch-build\n", '31-lint.md', '3') }

        refute(result[:labels].any? { it.id == 'ch-build' })
        assert_match(/章のラベル用の予約/, out)
      end

      def test_should_inject_chapter_anchor_inside_h1
        labels_map = { 'ch-build' => chap_label('ch-build', 'ビルド', '44-build.md') }

        out = XR.transform_captioned_blocks("# ビルド\n\n本文。\n", '44-build.md', labels_map)

        assert_includes out, '# ビルド <span id="ch-build" class="vs-sec-anchor"></span>'
      end

      # catalog.yml に載っていない章（章ラベルを集めていない章）にはアンカーを置かない
      def test_should_not_inject_anchor_when_label_is_not_collected
        out = XR.transform_captioned_blocks("# 草稿\n", '15-draft.md', {})

        assert_equal "# 草稿\n", out
      end

      private

      def chap_label(id, title, file, number = nil)
        XR::Label.new(id, :chap, '1', number, title, file, 1, false)
      end
    end

    class ChapterReferenceReplaceTest < Minitest::Test
      XR = PreProcessCommands::CrossReferenceProcessor

      def labels_map
        {
          'ch-new' => XR::Label.new('ch-new', :chap, '2', '第2章', '新規プロジェクトの作成', '12-new.md', 1, false),
          'ch-build' => XR::Label.new('ch-build', :chap, '7', '第7章', 'ビルド', '44-build.md', 1, false),
          'ch-notation-cheatsheet' => XR::Label.new('ch-notation-cheatsheet', :chap, '90', '付録 A', '記法早見表',
                                                    '90-notation-cheatsheet.md', 1, false),
          'ch-preface' => XR::Label.new('ch-preface', :chap, '0', nil, 'はじめに', '00-preface.md', 1, false),
          'install' => XR::Label.new('install', :sec, '1', '1', 'インストール', '93-install.md', 3, false),
          'fig-flow' => XR::Label.new('fig-flow', :fig, '11', '11-2', '処理の流れ', '21-images.md', 40, false)
        }
      end

      def replace(text, filename = '31-lint.md', **) = XR.replace_references(text, labels_map, filename, **)

      # --- 表示（§1.2・§2.11） ---

      def test_should_render_chapter_label_as_title_link
        content = replace("@ch-build の章。\n")[:content]

        assert_includes content, '<a href="44-build.html#ch-build" class="cross-ref-link">「ビルド」</a>'
      end

      def test_should_render_pageref_to_chapter_with_page_number_class
        content = replace("@pageref:ch-build の章。\n")[:content]

        assert_includes content, 'class="cross-ref-link pageref">「ビルド」</a>'
      end

      def test_should_render_chapref_with_chapter_number
        content = replace("@chapref:ch-build を参照。\n")[:content]

        assert_includes content, '<a href="44-build.html#ch-build" class="cross-ref-link pageref">第7章「ビルド」</a>'
      end

      def test_should_render_chapref_to_appendix_and_preface
        content = replace("@chapref:ch-notation-cheatsheet と @chapref:ch-preface。\n")[:content]

        assert_includes content, '>付録 A「記法早見表」</a>'
        # 前付けはローマ数字のノンブルなので frontmatter を付ける（索引と同じ扱い）
        assert_includes content, 'class="cross-ref-link pageref frontmatter">「はじめに」</a>'
      end

      def test_should_report_chapref_to_non_chapter_label
        result = replace("@chapref:install を参照。\n")

        assert_includes result[:content], '@chapref:install'
        assert_match(/@chapref: には章のラベル.*@pageref: を使います/, result[:errors].first)
      end

      def test_should_report_bare_chapref_with_example
        result = replace("@chapref を参照。\n")

        assert_match(/@chapref:ch-build/, result[:errors].first)
      end

      # --- 前後の空白（§1.2） ---

      # 鉤括弧で出す参照は、和文と接する側の半角空白を紙面に残さない
      def test_should_drop_spaces_between_bracketed_reference_and_japanese
        content = replace("次の章 @ch-new では、@pageref:ch-build と @install を見る。\n")[:content]

        assert_includes content, '次の章<a href="12-new.html#ch-new" class="cross-ref-link">「新規プロジェクトの作成」</a>では'
        assert_includes content, '「ビルド」</a>と<a href="93-install.html#install"'
        assert_includes content, '「インストール」</a>を見る'
      end

      # 英数字と接する側と行頭の空白は残す（語の区切りとして要る）
      def test_should_keep_spaces_next_to_ascii
        content = replace("Ruby @ch-build の章\n")[:content]

        assert_includes content, 'Ruby <a href="44-build.html#ch-build"'
        assert_includes content, '</a>の章'
      end

      # 図表の参照（「図 11-2 を」）と、置き換えなかった参照は書いたとおりに残す
      def test_should_keep_spaces_for_figures_and_unresolved_references
        content = replace("これは @fig-flow を見る。未定義 @ch-zzz です。\n")[:content]

        assert_includes content, 'これは <a href="21-images.html#fig-flow" class="cross-ref-link">図 11-2</a> を見る'
        assert_includes content, '未定義 @ch-zzz です'
      end

      # --- 同じ段落の二度目（§2.9） ---

      def test_should_drop_page_number_on_second_reference_in_same_paragraph
        content = replace("@pageref:ch-build で説明し、@chapref:ch-build にもある。\n続けて @pageref:ch-build。\n")[:content]

        assert_equal 1, content.scan('cross-ref-link pageref').size
        assert_equal 3, content.scan('href="44-build.html#ch-build"').size
      end

      def test_should_restore_page_number_after_paragraph_break
        content = replace("@pageref:ch-build で説明した。\n\n@pageref:ch-build をもう一度。\n")[:content]

        assert_equal 2, content.scan('cross-ref-link pageref').size
      end

      def test_should_treat_each_list_item_and_table_row_as_its_own_paragraph
        content = replace("- @pageref:ch-build\n- @pageref:ch-build\n\n| @pageref:ch-build |\n| @pageref:ch-build |\n")[:content]

        assert_equal 4, content.scan('cross-ref-link pageref').size
      end

      # 二度目の省略は @pageref: の対象すべてに効く（見出し・図表のラベルも同じ）
      def test_should_drop_second_page_number_for_heading_labels_too
        content = replace("@pageref:install と @pageref:install。\n")[:content]

        assert_equal 1, content.scan('cross-ref-link pageref').size
      end

      # --- 書き誤り（§1.3・§2.4・§2.7） ---

      def test_should_suggest_nearest_label_for_misspelled_chapter
        result = replace("@pageref:ch-biuld を参照。\n")

        assert_includes result[:content], '@pageref:ch-biuld'
        assert_match(/未定義のラベルID: @pageref:ch-biuld（もしかして: @pageref:ch-build）/, result[:errors].first)
      end

      def test_should_suggest_nearest_label_for_figures_too
        result = replace("@fig-flwo を参照。\n")

        assert_match(/（もしかして: @fig-flow）/, result[:errors].first)
      end

      def test_should_explain_that_slugless_chapter_has_no_label
        result = replace("@ch-11 を参照。\n")

        assert_match(/スラッグのない章には章ラベルが付きません。vs rename 11 11-<スラッグ>/, result[:errors].first)
      end

      # --- 「前の章」「次の章」（§2.10） ---

      ORDER = %w[00-preface 11-workflow 12-new 44-build 90-notation-cheatsheet].freeze

      def test_should_accept_previous_chapter_that_is_adjacent
        result = replace("前の章 @ch-new では。\n", '44-build.md', chapter_order: ORDER)

        assert_empty result[:errors]
      end

      def test_should_warn_when_previous_chapter_is_not_adjacent
        result = replace("前の章 @ch-new では。\n", '90-notation-cheatsheet.md', chapter_order: ORDER)

        assert_equal 1, result[:errors].size
        assert_match(/「前の章」の参照先 @ch-new（「新規プロジェクトの作成」）は、この章の前の章ではありません/,
                     result[:errors].first)
        assert_match(/前の章は 44-build。→ @ch-build/, result[:errors].first)
      end

      def test_should_check_next_chapter_with_pageref_and_chapref
        errors = replace("次章 @chapref:ch-build と次の章 @pageref:ch-new。\n", '12-new.md', chapter_order: ORDER)[:errors]

        assert_equal 1, errors.size
        assert_match(/「次の章」の参照先 @ch-new/, errors.first)
      end

      # 並びを渡さない呼び出し（組版用の置換・孤立ラベルの集計）では検査しない
      def test_should_skip_adjacency_check_without_chapter_order
        assert_empty replace("前の章 @ch-new では。\n", '90-notation-cheatsheet.md')[:errors]
      end
    end

    # 章番号の文字は章扉と同じ形で、catalog.yml の全体から数える（§2.11）
    class ChapterNumberTextTest < Minitest::Test
      XR = PreProcessCommands::CrossReferenceProcessor

      def test_should_number_chapters_by_catalog_order_not_file_number
        with_project do
          assert_equal '第1章', XR.chapter_number_text_for('11-install.md')
          assert_equal '第2章', XR.chapter_number_text_for('44-build.md')
          assert_equal '付録 A', XR.chapter_number_text_for('92-latex.md')
          assert_nil XR.chapter_number_text_for('00-preface.md')
        end
      end

      # 単章ビルドの絞り込みがあっても、参照先の番号は全体から数える
      def test_should_ignore_single_chapter_override
        with_project do
          hp = PostProcessCommands::HeadingProcessor
          previous = hp.chapter_tokens_override
          hp.chapter_tokens_override = ['44-build']
          assert_equal '第2章', XR.chapter_number_text_for('44-build.md')
        ensure
          hp.chapter_tokens_override = previous
        end
      end

      private

      def with_project
        Dir.mktmpdir('vs-chapter-number') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p(%w[config contents])
            File.write('config/catalog.yml',
                       "PREFACE:\n  - 00-preface\nCHAPTERS:\n  - 11-install\n  - 44-build\n" \
                       "APPENDICES:\n  - 92-latex\nPOSTFACE:\n")
            %w[00-preface 11-install 44-build 92-latex].each { File.write("contents/#{it}.md", "# #{it}\n") }
            yield
          end
        end
      end
    end

    # vs rename でスラッグを変えると本文の章参照が追随する（§2.2）
    class ChapterReferenceRenameTest < Minitest::Test
      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('chapter_reference_rename')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p(%w[contents config images])
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      def test_should_rewrite_references_outside_code
        File.write('contents/31-lint.md', <<~MD)
          詳しくは @chapref:ch-intro、@pageref:ch-intro、@ch-intro を参照。
          @ch-intro-extra と `@ch-intro` はそのまま。

          ```markdown
          @pageref:ch-intro
          ```
        MD

        out, = capture_io { ChapterRename.follow_chapter_references('11-intro', '11-introduction') }
        text = File.read('contents/31-lint.md')

        assert_includes text, '@chapref:ch-introduction、@pageref:ch-introduction、@ch-introduction を参照'
        assert_includes text, '@ch-intro-extra と `@ch-intro` はそのまま'
        assert_includes text, "```markdown\n@pageref:ch-intro\n```"
        assert_match(/3 箇所/, out)
      end

      # 改番だけならスラッグは変わらず、章ラベルも変わらない
      def test_should_leave_references_when_only_number_changes
        File.write('contents/31-lint.md', "@ch-intro を参照。\n")

        ChapterRename.follow_chapter_references('11-intro', '12-intro')

        assert_equal "@ch-intro を参照。\n", File.read('contents/31-lint.md')
      end

      def test_should_count_without_writing_for_confirmation
        File.write('contents/31-lint.md', "@ch-intro と @pageref:ch-intro。\n")

        assert_equal 2, ChapterRename.rewrite_chapter_references('ch-intro', 'ch-x', write: false)
        assert_equal "@ch-intro と @pageref:ch-intro。\n", File.read('contents/31-lint.md')
      end
    end
  end
end
