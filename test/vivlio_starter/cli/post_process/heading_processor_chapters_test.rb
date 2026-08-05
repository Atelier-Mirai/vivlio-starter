# frozen_string_literal: true

# ================================================================
# Test: heading_processor_chapters_test.rb
# ================================================================
# テスト対象:
#   HeadingProcessor.configured_main_chapter_tokens
#   （lib/vivlio_starter/cli/post_process/heading_processor.rb）
#
# 検証内容:
#   book.yml の chapters に書ける 6 形式（nil / all / 番号・範囲 / 番号配列 /
#   ファイルベース名の行並び / ファイルベース名配列）が、それぞれ意図どおり
#   章トークンへ落ちること。番号の綴りの解釈は Build::ChapterConfig に寄せたので、
#   その委譲が形式の判別を壊していないことを含めて固定する。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      class HeadingProcessorChaptersTest < Minitest::Test
        PREFACE = '00-preface'
        CHAPTERS = %w[11-install 12-tutorial 13-advanced 21-images].freeze
        APPENDIX = '91-appendix'

        def setup
          @saved_config = Common::CONFIG
          reset_warning_guard!
        end

        def teardown
          Common.install_configuration!(@saved_config)
          reset_warning_guard!
        end

        # nil / 'all' はフルビルド（絞り込みなし）
        def test_should_return_nil_for_full_build
          in_project do
            assert_nil tokens_for(nil)
            assert_nil tokens_for('all')
            assert_nil tokens_for('ALL')
          end
        end

        # 番号・範囲・カンマ区切りは番号指定として解釈される
        def test_should_resolve_number_and_range_strings
          in_project do
            assert_equal ['11-install'], tokens_for('11')
            assert_equal %w[11-install 12-tutorial 13-advanced], tokens_for('11-13')
            assert_equal %w[11-install 13-advanced 21-images], tokens_for('11, 13, 21')
            assert_equal %w[11-install 12-tutorial 21-images], tokens_for('11-12, 21')
          end
        end

        # 全要素が整数の配列も番号指定
        def test_should_resolve_integer_arrays
          in_project do
            assert_equal %w[11-install 13-advanced], tokens_for([11, 13])
            assert_equal %w[11-install 13-advanced], tokens_for(%w[11 13])
          end
        end

        # ファイルベース名は番号指定ではないので、そのままトークンとして扱う
        def test_should_treat_basenames_as_tokens
          in_project do
            assert_equal %w[11-install 12-tutorial], tokens_for("11-install\n12-tutorial")
            assert_equal %w[11-install 21-images], tokens_for(%w[11-install 21-images])
          end
        end

        # 番号とファイルベース名の混在（"11-12, 21-images"）は「番号指定ではない」側へ落ち、
        # 1 行なので行トークンとして丸ごと 1 つのトークンになる。どの章にも当たらないので
        # 警告で知らせる（トークンの中身自体は従来どおり）。
        def test_should_not_read_mixed_spec_as_numbers
          in_project do
            out, tokens = capture_tokens('11-12, 21-images')

            refute_includes tokens, '11-install', '番号として展開してはならない'
            assert_equal ['11-12, 21-images'], tokens
            assert_includes out, 'カンマ区切りが使えるのは番号指定のときだけ'
            assert_includes out, '- 11-install', '直し方（YAML 配列）を示すこと'
          end
        end

        # 該当する章が 1 つも無ければ nil（フルビルドへ戻す）
        def test_should_return_nil_when_nothing_selected
          in_project do
            assert_nil tokens_for('')
            assert_nil tokens_for([])
          end
        end

        # ------------------------------------------------------------
        # 書き間違いの案内
        # ------------------------------------------------------------

        # 実在しない章名は、どこを直すかまで示す
        def test_should_warn_on_unknown_chapter_name
          in_project do
            out, = capture_tokens('11-nonexistent')

            assert_includes out, "'11-nonexistent' に当たる章がありません"
            assert_includes out, 'contents/11-nonexistent.md がありません'
            assert_includes out, 'config/catalog.yml'
          end
        end

        # chapters が絞るのは本文章だけ。付録を書いても効かないので、その旨を伝える
        def test_should_warn_when_entry_is_not_a_main_chapter
          in_project do
            out, tokens = capture_tokens('91-appendix')

            assert_empty tokens
            assert_includes out, '本文章（1〜89）ではないので効きません'
            assert_includes out, 'appendix'
          end
        end

        # 番号指定がどの章にも当たらないと絞り込みが丸ごと消え、全章が組まれてしまう
        def test_should_warn_when_number_spec_matches_nothing
          in_project do
            out, tokens = capture_tokens('77')

            assert_empty tokens
            assert_includes out, "'77' に当たる章が 1 つもありません"
            assert_includes out, '全章が組まれます'
          end
        end

        # "11-89"（本文章を全部、の慣用的な書き方）で実在しない番号を数え上げない。
        # 絞り込みは効いているので、端の書きすぎは黙って落とす
        def test_should_stay_silent_when_range_overshoots_but_still_selects
          in_project do
            out, tokens = capture_tokens('11-89')

            assert_equal %w[11-install 12-tutorial 13-advanced 21-images], tokens
            assert_empty out
          end
        end

        # 正しい指定では何も言わない
        def test_should_stay_silent_on_valid_specs
          in_project do
            assert_empty capture_tokens('11-13').first
            assert_empty capture_tokens(%w[11-install 21-images]).first
            assert_empty capture_tokens("11-install\n12-tutorial").first
          end
        end

        # 同じ設定について 1 回だけ。章ごとに呼ばれるので素通しにすると章数ぶん並ぶ
        def test_should_warn_only_once_per_configuration
          in_project do
            first, = capture_tokens('11-nonexistent')
            second, = capture_io { HeadingProcessor.configured_main_chapter_tokens }

            assert_includes first, '11-nonexistent'
            assert_empty second
          end
        end

        private

        def tokens_for(chapters)
          capture_tokens(chapters).last
        end

        # 案内は 🟡（log_warn）で出るので stdout ごと受け取る
        def capture_tokens(chapters)
          Common.install_configuration!(Common.build_direct_configuration(chapters:))
          reset_warning_guard!
          tokens = nil
          out, = capture_io { tokens = HeadingProcessor.configured_main_chapter_tokens }
          [out, tokens]
        end

        def reset_warning_guard!
          HeadingProcessor.instance_variable_set(:@warned_chapters_config, nil)
        end

        def in_project
          Dir.mktmpdir('vs-heading-chapters-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', <<~YAML)
                PREFACE:
                  - #{PREFACE}
                CHAPTERS:
                #{CHAPTERS.map { "  - #{it}\n" }.join}
                APPENDICES:
                  - #{APPENDIX}
              YAML
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              [PREFACE, *CHAPTERS, APPENDIX].each do |basename|
                File.write(File.join(Common::CONTENTS_DIR, "#{basename}.md"), "# #{basename}\n")
              end
              yield
            end
          end
        end
      end
    end
  end
end
