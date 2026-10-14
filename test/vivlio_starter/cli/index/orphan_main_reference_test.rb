# frozen_string_literal: true

# ================================================================
# Test: index/orphan_main_reference_test.rb
# ================================================================
# テスト対象:
#   UnifiedIndexManager#warn_orphan_main_references（改善案.md #108 の B）
#
# 検証内容:
#   - 辞書の main: が、原稿の無い章を指していたら 🟡 で知らせる
#     （直し方と、その語が出てくる章を添える）
#   - catalog から外しただけの章（原稿はある）は今までどおり黙る
#     （外して戻す使い方のため。index-main-reference-spec.md）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/index/unified_index_manager'

module VivlioStarter
  module CLI
    module IndexCommands
      class OrphanMainReferenceTest < Minitest::Test
        def setup
          PreProcessCommands::IssueRegistry.reset!
        end

        def teardown
          PreProcessCommands::IssueRegistry.reset!
          IndexCommands.flush_post_build_messages
        end

        # --- phase: 知らせる ---

        def test_warns_when_main_points_to_a_chapter_without_manuscript
          message = warning_for(main: ['61-developer'])

          assert_match(/「テスト」の主要参照 61-developer の原稿がありません/, message)
          assert_match(%r{config/index_glossary_terms\.yml}, message, '直す場所を示す')
          assert_match(/vs index:auto/, message, '外した後の導線を示す')
          assert_match(/10-a・20-b/, message, '主要参照の候補になる章を添える')
        end

        def test_warns_for_a_section_reference_too
          assert_match(/61-developer の原稿がありません/, warning_for(main: ['61-developer#テストの書き方']))
        end

        def test_records_one_issue_per_term
          warning_for(main: ['61-developer'])

          assert_equal 1, PreProcessCommands::IssueRegistry.issues.size
          assert_pattern do
            PreProcessCommands::IssueRegistry.issues.first => { severity: :warn, category: :index }
          end
        end

        # --- phase: 黙る ---

        def test_stays_silent_when_the_chapter_exists
          assert_empty warning_for(main: ['20-b']).strip
          assert_empty PreProcessCommands::IssueRegistry.issues
        end

        # 原稿はあるが catalog から外した章は、外して戻す使い方なので黙る
        def test_stays_silent_when_the_chapter_is_only_out_of_the_catalog
          assert_empty warning_for(main: ['90-extra'], extra_manuscripts: ['90-extra']).strip
        end

        private

        # 「テスト」が 10-a・20-b に出る最小プロジェクトを組んで B だけを呼ぶ
        def warning_for(main:, extra_manuscripts: [])
          chapters = %w[10-a 20-b 30-c]
          Dir.mktmpdir('vs-orphan-main-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(['config', Common::CONTENTS_DIR])
              File.write('config/catalog.yml', "CHAPTERS:\n#{chapters.map { "  - #{it}\n" }.join}")
              chapters.each do |name|
                body = %w[10-a 20-b].include?(name) ? "# 章\n\nテストを書きます。\n" : "# 章\n\n本文です。\n"
                File.write(File.join(Common::CONTENTS_DIR, "#{name}.md"), body)
              end
              extra_manuscripts.each { File.write(File.join(Common::CONTENTS_DIR, "#{it}.md"), "# 外した章\n") }
              entry = { 'term' => 'テスト', 'yomi' => 'てすと', 'flags' => 'i', 'main' => main }
              File.write('config/index_glossary_terms.yml', { 'terms' => [entry] }.to_yaml)

              out, err = capture_io do
                UnifiedIndexManager.new.warn_orphan_main_references(chapters)
                IndexCommands.flush_post_build_messages
              end
              out + err
            end
          end
        end
      end
    end
  end
end
