# frozen_string_literal: true

# ================================================================
# Test: index/glossary_warning_scope_test.rb
# ================================================================
# テスト対象:
#   UnifiedIndexManager#warn_unmatched_glossary_terms（R4）のスコープ判定
#   （docs/specs/preflight-glossary-warning-scope-report.md 案 A・案 C）
#
# 検証内容:
#   - 章を絞った走査では警告を出さない（用語集の照合は書籍全体が単位のため）
#   - catalog 全章を走査したときは従来どおり警告する
#   - 出現先が catalog 未登録の原稿なら、その章名を「catalog 未登録の …」と伝える
#   - どこにも出現しない語は「原稿のどこにも出現しません」と伝える
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/index/unified_index_manager'

module VivlioStarter
  module CLI
    module IndexCommands
      class GlossaryWarningScopeTest < Minitest::Test
        # 章を絞った走査では黙る（1 章だけを対象にすると用語集語がほぼ全滅して誤検知になる）
        def test_should_stay_silent_when_scanning_a_subset_of_catalog
          in_project do
            out = warn_for(chapters: ['21-images'])

            assert_empty out, '部分実行では R4 警告を出すべきではありません'
          end
        end

        # catalog 全章を走査したときは警告する（本来の役割＝辞書に残った死語の検出）
        def test_should_warn_when_scanning_all_catalog_chapters
          in_project do
            out = warn_for(chapters: %w[21-images 22-tables])

            assert_includes out, '用語集語がビルド対象章に出現しません: トンボ'
          end
        end

        # catalog 未登録の原稿に出現する語は、その章名を添えて知らせる
        def test_should_name_the_uncatalogued_chapter_where_the_term_appears
          in_project do
            File.write(File.join(Common::CONTENTS_DIR, '97-draft.md'), "# 下書き\n\nトンボは印刷の目印です。\n")

            out = warn_for(chapters: %w[21-images 22-tables])

            assert_includes out, 'catalog 未登録の 97-draft に出現'
            refute_includes out, 'catalog 外の', '「catalog 外」という曖昧な表記は使わない'
          end
        end

        # 原稿のどこにも出現しない語は、語の変更・削除を疑うよう伝える
        def test_should_report_terms_absent_from_every_manuscript
          in_project do
            out = warn_for(chapters: %w[21-images 22-tables])

            assert_includes out, '原稿のどこにも出現しません'
          end
        end

        # 全章走査で出た死語は章別サマリーへ積まれる（:index・章に紐付かない指摘）
        def test_should_record_dead_term_into_issue_registry
          in_project do
            PreProcessCommands::IssueRegistry.reset!
            warn_for(chapters: %w[21-images 22-tables])

            issue = PreProcessCommands::IssueRegistry.issues.first
            assert_pattern do
              issue => { chapter: nil, severity: :warn, category: :index }
            end
            assert_includes issue.message, 'トンボ'
          ensure
            PreProcessCommands::IssueRegistry.reset!
          end
        end

        # 部分走査では警告も集計も行わない（誤検知を集計へ昇格させない）
        def test_should_not_record_when_scanning_a_subset
          in_project do
            PreProcessCommands::IssueRegistry.reset!
            warn_for(chapters: ['21-images'])

            assert_empty PreProcessCommands::IssueRegistry.issues
          ensure
            PreProcessCommands::IssueRegistry.reset!
          end
        end

        private

        # catalog に 2 章を持つ最小プロジェクトを組む。
        # 用語集語「トンボ」はどの章にも出現しないため、全章走査なら R4 の対象になる。
        def in_project
          Dir.mktmpdir('vs-glossary-scope-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', "CHAPTERS:\n  - 21-images\n  - 22-tables\n")
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              File.write(File.join(Common::CONTENTS_DIR, '21-images.md'), "# 画像\n\n本文です。\n")
              File.write(File.join(Common::CONTENTS_DIR, '22-tables.md'), "# 表\n\n本文です。\n")
              yield
            end
          end
        end

        # R4 だけを直接呼ぶ（スキャン全体は走らせない）。
        # glossary_backlinks を空にすることで「1 度も出現しなかった」状態を作る。
        def warn_for(chapters:)
          manager = UnifiedIndexManager.new
          terms = [{ 'term' => 'トンボ', 'flags' => 'g' }]

          out, = capture_io do
            manager.send(:warn_unmatched_glossary_terms, terms, {}, chapters)
          end
          out
        end
      end
    end
  end
end
