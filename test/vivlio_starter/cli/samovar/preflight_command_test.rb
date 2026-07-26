# frozen_string_literal: true

# ================================================================
# Test: preflight_command_test.rb
# ================================================================
# テスト対象:
#   PreflightCommand — vs preflight コマンドの Samovar 実装
#
# 検証内容:
#   - 引数なしで全章が対象になること
#   - 章番号トークンが正しく解決されること
#   - 範囲トークンが正しく解決されること
#   - --no-resize で Step 1 がスキップされること
#   - preflight 実行後に HTML/PDF が生成されないこと
#   - RootCommand.public_commands に登録されていること
#   - vs --help に preflight が表示されること
#   - --help / -h でヘルプが表示されること
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/samovar'
require 'vivlio_starter/cli/samovar/preflight_command'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter'
require 'vivlio_starter/cli'

module VivlioStarter
  module CLI
    module SamovarCommands
      # ----------------------------------------------------------------
      # オプション解析テスト
      # ----------------------------------------------------------------
      class PreflightCommandOptionTest < Minitest::Test
        # --no-resize で options[:resize] が false になる
        def test_should_disable_resize_when_no_resize_is_passed
          command = PreflightCommand.new(['--no-resize'])
          assert_equal false, command.options[:resize]
        end

        # デフォルトで resize が有効
        def test_should_keep_resize_enabled_by_default
          command = PreflightCommand.new([])
          assert_equal true, command.options[:resize]
        end

        # --help で options[:help] が true になる
        def test_should_set_help_option_when_help_is_passed
          command = PreflightCommand.new(['--help'])
          assert_equal true, command.options[:help]
        end

        # -h でも options[:help] が true になる
        def test_should_set_help_option_when_h_is_passed
          command = PreflightCommand.new(['-h'])
          assert_equal true, command.options[:help]
        end
      end

      # ----------------------------------------------------------------
      # 実行テスト
      # ----------------------------------------------------------------
      class PreflightCommandExecutionTest < Minitest::Test
        # 引数なしで全章が対象になり、mode: :preflight で pipeline が呼ばれる
        def test_should_run_all_chapters_when_no_targets_given
          entries = sample_entries('11-sample', '12-tutorial')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new([])
              suppress_outputs(command) { command.call }
            end

            pipeline = pipelines.last
            assert pipeline.run_called, 'pipeline#run が呼ばれるべきです'
            assert_equal :preflight, pipeline.mode
            assert_equal entries, pipeline.entries_param
          end
        end

        # 章番号トークン "0" が 00-preface に解決される
        def test_should_resolve_chapter_number_token
          entries = sample_entries('00-preface')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new(['0'])
              suppress_outputs(command) { command.call }
            end

            assert_equal entries, pipelines.last.entries_param
          end
        end

        # 範囲トークン "1-10" が複数章に解決される
        def test_should_resolve_range_token
          entries = sample_entries('01-intro', '05-advanced', '10-summary')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new(['1-10'])
              suppress_outputs(command) { command.call }
            end

            assert_equal entries, pipelines.last.entries_param
          end
        end

        # --no-resize で pipeline の run_step1 がスキップされる（options[:resize] = false）
        def test_should_skip_step1_when_no_resize
          entries = sample_entries('11-sample')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new(['--no-resize'])
              suppress_outputs(command) { command.call }
            end

            assert_equal false, pipelines.last.command_options[:resize]
          end
        end

        # preflight 実行後に HTML/PDF ファイルが生成されない
        def test_should_not_generate_html_or_pdf
          entries = sample_entries('11-sample')
          with_resolver_stub(entries) do
            with_pipeline_stub([]) do
              command = PreflightCommand.new([])
              Dir.mktmpdir do |dir|
                Dir.chdir(dir) do
                  suppress_outputs(command) { command.call }
                  html_files = Dir.glob('*.html')
                  pdf_files  = Dir.glob('*.pdf')
                  assert_empty html_files, 'preflight 後に HTML が生成されるべきではありません'
                  assert_empty pdf_files,  'preflight 後に PDF が生成されるべきではありません'
                end
              end
            end
          end
        end

        # --help でヘルプが表示されて終了コード 0 が返る
        def test_should_print_help_with_help_option
          output, = capture_io do
            command = PreflightCommand.new(['--help'])
            result = command.call
            assert_equal 0, result
          end
          assert_includes output, 'preflight'
        end

        private

        def sample_entries(*basenames)
          basenames.map do |bn|
            number = bn[/^\d+/, 0].to_i
            slug = bn.sub(/^\d+-/, '')
            TokenResolver::Entry.new(
              number: number,
              slug: slug,
              kind: :chapter,
              label: bn,
              path: "contents/#{bn}.md",
              exists: true,
              in_catalog: true,
              valid: true
            )
          end
        end

        def suppress_outputs(command)
          PreProcessCommands::LinkImageValidator.stub :reset!, nil do
            PreProcessCommands::LinkImageValidator.stub :print_summary, nil do
              PreProcessCommands::LinkImageValidator.stub :any_issues?, false do
                Common.stub :log_always, nil do
                  yield
                end
              end
            end
          end
        end

        def with_resolver_stub(entries)
          TokenResolver::Resolver.stub :new, -> { ResolverStub.new(entries) } do
            yield
          end
        end

        def with_pipeline_stub(registry)
          BuildCommands::UnifiedBuildPipeline.stub :new, ->(_cmd, entries:, mode:) {
            fake = PipelineStub.new(_cmd, entries, mode)
            registry << fake
            fake
          } do
            yield
          end
        end

        class ResolverStub
          def initialize(return_value)
            @return_value = return_value
          end

          def resolve(*_tokens)
            @return_value
          end
        end

        class PipelineStub
          attr_reader :entries_param, :mode, :run_called, :command_options

          def initialize(command, entries, mode)
            @command_options = command.options
            @entries_param = entries
            @mode = mode
            @run_called = false
          end

          def run
            @run_called = true
            []
          end
        end
      end

      # ----------------------------------------------------------------
      # 章別サマリー・3 段階の最終行
      # （docs/specs/preflight-chapter-summary-spec.md §1・§3-2・§3-4）
      # ----------------------------------------------------------------
      class PreflightCommandSummaryTest < Minitest::Test
        def teardown
          PreProcessCommands::IssueRegistry.reset!
        end

        # エラーがあると章別表に内訳が出て、最終行は ❌・終了コード 1
        def test_should_report_errors_with_chapter_breakdown_and_exit_1
          output, status = run_preflight(entries: fixture_entries('10-alpha', '21-beta')) do
            PreProcessCommands::IssueRegistry.record(
              chapter: '21-beta.md', severity: :error, category: :image, message: '存在しない画像: a.webp'
            )
            PreProcessCommands::IssueRegistry.record(
              chapter: '21-beta.md', severity: :warn, category: :link, message: '裸 URL'
            )
          end

          assert_equal 1, status
          assert_includes output, '📋 章別サマリー'
          assert_includes output, '🔴 エラー 1 件・🟡 警告 1 件'
          assert_includes output, '❌ Preflight 完了: エラー 1 件・警告 1 件'
          # 指摘ゼロの章も「検査した」証明として載る
          assert_match(/10 alpha\s+✅/, output)
        end

        # 警告のみなら最終行は ⚠️（ビルドは可能）で終了コード 0
        # Guard 警告（章に紐付かない）も最終判定に反映される（§0-2 の非対称の解消）
        def test_should_report_warning_only_and_exit_0
          output, status = run_preflight(entries: fixture_entries('10-alpha')) do
            PreProcessCommands::IssueRegistry.record(
              severity: :warn, category: :guard, message: '未知のコンテナクラス .foo'
            )
          end

          assert_equal 0, status
          assert_includes output, '章に紐付かない指摘'
          assert_includes output, '🟡 警告 1 件'
          assert_includes output, '⚠️ Preflight 完了: 警告 1 件（ビルドは可能です）'
        end

        # 全章 ✅ なら表は 1 行へ短縮され、最終行は ✅・終了コード 0
        def test_should_shorten_table_when_all_chapters_are_clean
          output, status = run_preflight(entries: fixture_entries('10-alpha', '21-beta'))

          assert_equal 0, status
          assert_includes output, '✅ 全 2 章: 問題なし'
          refute_includes output, '📋 章別サマリー'
          assert_includes output, '✅ Preflight 完了: 良好な状態です'
        end

        # 裸 URL の警告だけなら終了コード 0（🟡 しか出ていないのに CI が落ちる食い違いの解消）。
        # 従来は LinkImageValidator.any_issues? が severity を見ず 1 を返していた。
        def test_should_exit_0_when_only_bare_url_warnings_exist
          output, status = run_preflight(entries: fixture_entries('10-alpha')) do
            PreProcessCommands::IssueRegistry.record(
              chapter: '10-alpha.md', line: 12, severity: :warn,
              category: :link, message: '裸 URL: https://example.com'
            )
          end

          assert_equal 0, status, '警告のみなら終了コードは 0'
          assert_includes output, '⚠️ Preflight 完了: 警告 1 件（ビルドは可能です）'
        end

        # 危険スキームは 🔴 なので終了コード 1（セキュリティ検出を CI で止める）
        def test_should_exit_1_when_dangerous_scheme_detected
          _, status = run_preflight(entries: fixture_entries('10-alpha')) do
            PreProcessCommands::IssueRegistry.record(
              chapter: '10-alpha.md', line: 3, severity: :error,
              category: :link, message: '危険なスキーム: file:///etc/passwd'
            )
          end

          assert_equal 1, status, '危険スキームは終了コード 1'
        end

        # 章単位実行（vs preflight 21）でも対象章のみの同形式になる
        def test_should_limit_table_to_targeted_chapter
          output, = run_preflight(entries: fixture_entries('21-beta'), targets: ['21']) do
            PreProcessCommands::IssueRegistry.record(
              chapter: '21-beta.md', severity: :error, category: :image, message: '存在しない画像: a.webp'
            )
          end

          assert_includes output, '21 beta'
          refute_includes output, '10 alpha'
        end

        private

        # contents/ に実在しない basename を使い、章タイトルがスラッグへ縮退する形で固定する
        def fixture_entries(*basenames)
          basenames.map do |bn|
            TokenResolver::Entry.new(
              number: bn[/^\d+/, 0], slug: bn.sub(/^\d+-/, ''), kind: :chapter, label: 'CHAPTERS',
              path: "contents/#{bn}.md", exists: false, in_catalog: true, valid: true
            )
          end
        end

        # pipeline.run のタイミングで recorder を呼び、各発生源が指摘を積んだ状態を作る。
        # 終了コードは IssueRegistry の severity だけで決まるため、
        # LinkImageValidator.any_issues? はスタブしない（呼ばれない）。
        def run_preflight(entries:, targets: [], &recorder)
          status = nil
          output, = capture_io do
            with_stubs(entries, recorder) do
              status = PreflightCommand.new(targets).call
            end
          end
          [output, status]
        end

        def with_stubs(entries, recorder, &block)
          validator = PreProcessCommands::LinkImageValidator
          Guards::Guard.stub(:run!, nil) do
            CleanCommands.stub(:execute_clean, nil) do
              TokenResolver::Resolver.stub(:new, -> { ResolverStub.new(entries) }) do
                BuildCommands::UnifiedBuildPipeline.stub(:new, ->(*, **) { RecordingPipelineStub.new(recorder) }) do
                  validator.stub(:reset!, nil) do
                    validator.stub(:check_external_urls!, nil) do
                      validator.stub(:print_summary, nil, &block)
                    end
                  end
                end
              end
            end
          end
        end

        class ResolverStub
          def initialize(entries)
            @entries = entries
          end

          def resolve(*_tokens) = @entries
        end

        # run の中で指摘を積む pipeline スタブ（実際の前処理は走らせない）
        class RecordingPipelineStub
          def initialize(recorder)
            @recorder = recorder
          end

          def run
            @recorder&.call
            []
          end
        end
      end

      # ----------------------------------------------------------------
      # CLI 統合テスト
      # ----------------------------------------------------------------
      class PreflightCommandRegistrationTest < Minitest::Test
        # RootCommand.public_commands に 'preflight' が登録されている
        def test_should_register_in_public_commands
          assert_includes RootCommand.public_commands.keys, 'preflight'
          assert_equal PreflightCommand, RootCommand.public_commands['preflight']
        end

        # vs --help に preflight が表示される
        def test_should_appear_in_help_output
          output, = capture_io do
            ::VivlioStarter::CLI.start(['--help'])
          end
          assert_includes output, 'preflight'
        end

        # vs preflight --help でヘルプが表示される
        def test_should_print_help_with_help_option_via_cli
          output, = capture_io do
            status = ::VivlioStarter::CLI.start(['preflight', '--help'])
            assert_equal 0, status
          end
          assert_includes output, 'preflight'
          assert_includes output, 'targets'
          assert_includes output, 'resize'
        end
      end
    end
  end
end
