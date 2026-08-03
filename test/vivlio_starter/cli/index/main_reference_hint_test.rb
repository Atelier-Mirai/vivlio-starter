# frozen_string_literal: true

# ================================================================
# Test: index/main_reference_hint_test.rb
# ================================================================
# テスト対象:
#   UnifiedIndexManager#warn_missing_main_references
#   （index-main-reference-spec.md R7）
#
# 検証内容:
#   - 広く散らばっているのに主要参照が未指定の語を、要約 1 行で促す
#   - 語ごとに 1 行ずつ出さない（実測 30〜38 語。ログが埋まるうえ直せない）
#   - IssueRegistry へ積むのは 1 件だけ
#   - 部分ビルド・薄い本では黙る（比率は全章走査でしか意味を持たない）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/index/unified_index_manager'

module VivlioStarter
  module CLI
    module IndexCommands
      class MainReferenceHintTest < Minitest::Test
        CHAPTERS = %w[10-a 20-b 30-c 40-d 50-e 60-f].freeze

        def setup
          PreProcessCommands::IssueRegistry.reset!
        end

        def teardown
          PreProcessCommands::IssueRegistry.reset!
          IndexCommands.flush_post_build_messages
        end

        # --- phase: 促す ---

        def test_warns_once_with_a_summary_line
          message = hint_for(main: nil)

          assert_match(/主要参照が未指定の索引語が 1 語あります/, message)
          assert_match(/vs index:auto/, message, '直しに行ける導線を添える')
        end

        # 語ごとの詳細はレビューファイルの仕事。ビルドログに 30 行並べても
        # そこから修正には進めない。
        def test_does_not_list_the_terms_one_by_one
          refute_includes hint_for(main: nil), 'ノンブル'
        end

        def test_records_a_single_issue_without_a_chapter
          hint_for(main: nil)

          assert_equal 1, PreProcessCommands::IssueRegistry.issues.size
          assert_pattern do
            PreProcessCommands::IssueRegistry.issues.first => { chapter: nil, severity: :warn, category: :index }
          end
        end

        # --- phase: 黙る ---

        def test_stays_silent_when_the_term_has_a_main_reference
          assert_empty hint_for(main: '30-c').strip
          assert_empty PreProcessCommands::IssueRegistry.issues
        end

        # 出現が狭い語は、索引のページ番号がそのまま案内として働く
        def test_stays_silent_for_narrowly_used_terms
          assert_empty hint_for(main: nil, appears_in: ['10-a']).strip
        end

        # 比率は全章を走査したときにしか意味を持たない。
        # 1 章だけを対象にすると、その章に出る語が全部「広い」判定になる。
        def test_stays_silent_on_a_partial_build
          assert_empty hint_for(main: nil, build: ['10-a']).strip
        end

        # 薄い本では判定しない（TermSpread の下限と共通）
        def test_stays_silent_for_a_thin_book
          assert_empty hint_for(main: nil, chapters: %w[10-a 20-b 30-c]).strip
        end

        # 比率は book.yml で調整できる。1.0 なら全章に出る語しか promote しない
        def test_ratio_is_configurable
          assert_empty hint_for(main: nil, ratio: 1.0).strip
        end

        private

        # 「ノンブル」が appears_in の章に出る最小プロジェクトを組んで R7 だけを呼ぶ
        def hint_for(main:, appears_in: %w[10-a 20-b 30-c], chapters: CHAPTERS, build: nil, ratio: nil)
          Dir.mktmpdir('vs-main-ref-hint-') do |dir|
            Dir.chdir(dir) do
              write_project(chapters, appears_in, main)
              manager = UnifiedIndexManager.new
              manager.instance_variable_get(:@config)[:main_reference_hint_ratio] = ratio if ratio

              out, err = capture_io do
                manager.warn_missing_main_references(build || chapters)
                IndexCommands.flush_post_build_messages
              end
              out + err
            end
          end
        end

        def write_project(chapters, appears_in, main)
          FileUtils.mkdir_p(['config', Common::CONTENTS_DIR])
          File.write('config/catalog.yml', "CHAPTERS:\n#{chapters.map { "  - #{it}\n" }.join}")
          chapters.each do |name|
            body = appears_in.include?(name) ? "# 章\n\nノンブルを振ります。\n" : "# 章\n\n本文です。\n"
            File.write(File.join(Common::CONTENTS_DIR, "#{name}.md"), body)
          end

          entry = { 'term' => 'ノンブル', 'yomi' => 'のんぶる', 'flags' => 'i' }
          entry['main'] = main if main
          File.write('config/index_glossary_terms.yml', { 'terms' => [entry] }.to_yaml)
        end
      end
    end
  end
end
