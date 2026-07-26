# frozen_string_literal: true

# ================================================================
# Test: build/index_step_scope_test.rb
# ================================================================
# テスト対象:
#   UnifiedBuildPipeline#run_step4_index_processing のスコープ判定
#   （docs/specs/preflight-glossary-warning-scope-report.md）
#
# 検証内容:
#   - 章を絞った実行では索引処理を行わない（vs build <章> と挙動を揃える）
#   - catalog 全章が対象なら従来どおり索引処理を実行する
#   - 引数なし（entries 空）のフォールバックも全章とみなす
#
# preflight は「vs build が報告することを先に見る」機能なので、
# build が言わないことを言ってはならない——という契約をここで固定する。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/build/pipeline'
require 'vivlio_starter/cli/build/targets'
require 'vivlio_starter/cli/index'
require 'vivlio_starter/cli/token_resolver'

module VivlioStarter
  module CLI
    module BuildCommands
      class IndexStepScopeTest < Minitest::Test
        # 章を絞った実行では索引処理そのものを行わない
        def test_should_skip_index_processing_for_a_subset_of_catalog
          in_project do
            out = run_step4(entries: entries_for('21-images'))

            assert_includes out, '章を絞った実行のためスキップします'
            refute processed?, '部分実行で索引処理を呼んではいけません'
          end
        end

        # catalog 全章が対象なら索引処理を実行する
        def test_should_run_index_processing_when_all_catalog_chapters_are_targeted
          in_project do
            out = run_step4(entries: entries_for('21-images', '22-tables'))

            assert_includes out, '索引語のスキャンと索引ページ生成を実行します'
            assert_equal %w[21-images 22-tables], processed_chapters
          end
        end

        # 引数なし（entries 空）のフォールバックは全章扱い
        def test_should_treat_empty_entries_as_full_scope
          in_project do
            run_step4(entries: [])

            assert processed?, 'entries が空のときは contents/ 全体を対象に実行するべきです'
          end
        end

        private

        def in_project
          Dir.mktmpdir('vs-index-scope-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', "CHAPTERS:\n  - 21-images\n  - 22-tables\n")
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              File.write(File.join(Common::CONTENTS_DIR, '21-images.md'), "# 画像\n")
              File.write(File.join(Common::CONTENTS_DIR, '22-tables.md'), "# 表\n")
              @processed_chapters = nil
              yield
            end
          end
        end

        def entries_for(*basenames)
          basenames.map do |bn|
            TokenResolver::Entry.new(
              number: bn[/\A\d+/], slug: bn.sub(/\A\d+-/, ''), kind: :chapter, label: 'CHAPTERS',
              path: File.join(Common::CONTENTS_DIR, "#{bn}.md"), exists: true, in_catalog: true, valid: true
            )
          end
        end

        # 索引処理の実行有無だけを見たいので、実処理は差し替える。
        # 判断理由（log_action）は info 以上でしか出ないため、ログレベルを上げて拾う
        def run_step4(entries:)
          pipeline = UnifiedBuildPipeline.new(CommandStub.new, entries: entries, mode: :preflight)

          with_info_log do
            out, = capture_io do
              IndexCommands.stub(:index_enabled?, true) do
                IndexCommands.stub(:process_index_for_build!, ->(chapters) { @processed_chapters = chapters }) do
                  pipeline.send(:run_step4_index_processing)
                end
              end
            end
            out
          end
        end

        # ログレベルは Common が保持する状態なので、ARGV を汚さずに切り替えられる
        def with_info_log
          original = Common.log_level
          Common.log_level = Common::LEVELS['info']
          yield
        ensure
          Common.log_level = original
        end

        def processed? = !@processed_chapters.nil?
        def processed_chapters = @processed_chapters

        class CommandStub
          def options = { resize: false }
        end
      end
    end
  end
end
