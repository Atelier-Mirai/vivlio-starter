# frozen_string_literal: true

# ================================================================
# Test: build_token_expansion_test.rb
# ================================================================
# テスト対象:
#   TokenExpander（lib/vivlio_starter/cli/build/token_expander.rb）
#
# 検証内容:
#   - 単一章番号 "45" → ["45-first-html.md"] への展開
#   - 範囲 "45-47" → 複数ファイルへの展開
#   - カンマ区切り "45,47" の解析
#   - ベース名からファイル解決
#
# テスト手法:
#   - mock_files でファイル一覧をスタブ化
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/convert'
require 'vivlio_starter/cli/post_process'
require 'vivlio_starter/cli/entries'
require 'vivlio_starter/cli/pdf'
require 'vivlio_starter/cli'

module VivlioStarter
  module CLI
    # TokenExpander のユニットテスト
    class TokenExpansionTest < Minitest::Test
      def setup
        @expander = TokenExpander.new
      end

      # 単一の章番号からベース名への展開
      def test_expand_single_number_token
        @expander.mock_files = ['45-first-html.md', '46-first-css.md', '47-wave-studio-css.md']
        result = @expander.expand_token_to_basenames('45')
        assert_equal ['45-first-html.md'], result
      end

      # 範囲指定からベース名への展開
      def test_expand_range_token
        @expander.mock_files = ['45-first-html.md', '46-first-css.md', '47-wave-studio-css.md', '48-legacy-work.md']
        result = @expander.expand_token_to_basenames('45-47')
        expected = ['45-first-html.md', '46-first-css.md', '47-wave-studio-css.md']
        assert_equal expected.sort, result.sort
      end

      # 明示的なベース名での展開
      def test_expand_explicit_basename
        @expander.mock_files = ['45-first-html.md', '46-first-css.md']
        result = @expander.expand_token_to_basenames('45-first-html')
        assert_equal ['45-first-html.md'], result
      end

      # .md 拡張子付きでの展開
      def test_expand_with_md_extension
        @expander.mock_files = ['45-first-html.md', '46-first-css.md']
        result = @expander.expand_token_to_basenames('45-first-html.md')
        assert_equal ['45-first-html.md'], result
      end

      # 存在しない番号は空配列を返す
      def test_expand_nonexistent_number
        @expander.mock_files = ['45-first-html.md', '46-first-css.md']
        result = @expander.expand_token_to_basenames('99')
        assert_equal [], result
      end

      # 複数トークンの展開
      def test_expand_multiple_tokens
        @expander.mock_files = ['45-first-html.md', '46-first-css.md', '54-operator.md', '55-condition.md']
        result = @expander.expand_tokens_to_targets(['45', '54-55'])
        expected = ['45-first-html.md', '54-operator.md', '55-condition.md']
        assert_equal expected.sort, result.sort
      end

      # 重複は除去される
      def test_expand_removes_duplicates
        @expander.mock_files = ['45-first-html.md', '46-first-css.md']
        result = @expander.expand_tokens_to_targets(['45', '45-first-html', '45-46'])
        expected = ['45-first-html.md', '46-first-css.md']
        assert_equal expected.sort, result.sort
      end

      # 空のトークンは無視される
      def test_expand_ignores_empty_tokens
        @expander.mock_files = ['45-first-html.md']
        result = @expander.expand_tokens_to_targets(['', nil, '45'])
        assert_equal ['45-first-html.md'], result
      end
    end

    # BuildCommands のトークン展開ロジックを再実装したテスト用ヘルパー
    class TokenExpander
      attr_accessor :mock_files

      def initialize
        @mock_files = []
      end

      def list_contents_basenames
        @mock_files
      end

      def chapter_number_from_basename(basename)
        (basename[/^(\d+)-/, 1] || nil)&.to_i
      end

      def find_basenames_in_range(from_num, to_num)
        a, b = [from_num.to_i, to_num.to_i].minmax
        list_contents_basenames.select do |bn|
          n = chapter_number_from_basename(bn)
          n && n >= a && n <= b
        end
      end

      def expand_token_to_basenames(token)
        t = token.to_s.strip
        return [] if t.empty?
        return find_basenames_in_range(::Regexp.last_match(1), ::Regexp.last_match(2)) if t =~ /(\A\d+)-(\d+\z)/
        return list_contents_basenames.select { |bn| bn.start_with?("#{t}-") } if t =~ /\A\d+\z/

        # 明示的なベース名
        name = t.sub(%r{\Acontents/}, '')
        name = "#{name}.md" unless name.end_with?('.md')
        list_contents_basenames.include?(name) ? [name] : []
      end

      def expand_tokens_to_targets(tokens)
        Array(tokens).compact.flat_map { |tok| expand_token_to_basenames(tok) }.uniq
      end
    end

    # ================================================================
    # Single Mode Integration Test
    # ================================================================
    # 単章ビルドのワークフロー全体をテスト
    class SingleModeIntegrationTest < Minitest::Test
      def test_single_mode_invokes_correct_commands
        within_temp_dir do
          pipeline = build_pipeline(['11-sample'])
          pre_calls = []
          conv_calls = []
          post_calls = []

          # 直接メソッド呼び出しをスタブして記録
          PreProcessCommands.stub :execute_pre_process, ->(opts, tokens) { pre_calls << tokens } do
            ConvertCommands.stub :execute_convert, ->(opts, tokens) { conv_calls << tokens } do
              PostProcessCommands.stub :execute_post_process, ->(opts, tokens) { post_calls << tokens } do
                pipeline.send(:build_target_sections_html)
              end
            end
          end

          # Entry オブジェクトが渡されるので、basename を比較
          assert_equal [['11-sample']], pre_calls.map { |c| c.map(&:basename) }
          assert_equal [['11-sample']], conv_calls.map { |c| c.map(&:basename) }
          assert_equal [['11-sample']], post_calls.map { |c| c.map(&:basename) }
        end
      end

      # single mode も full と同じ「html/ → pdf/ コピー＋用途別 entries/config」経路（P4・E5）
      def test_single_mode_generates_entries_and_pdf
        within_temp_dir do
          # ワークスペース html/ に対象章の中間 HTML を用意する
          FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
          File.write(File.join(Common::BUILD_HTML_DIR, '11-sample.html'), '<html><title>11</title></html>')
          File.write(File.join(Common::BUILD_HTML_DIR, '12-tutorial.html'), '<html><title>12</title></html>')

          pipeline = build_pipeline(['11-sample', '12-tutorial'])
          writer_calls = []
          pdf_calls = []

          writer_stub = lambda { |name:, entry_htmls:, output:|
            writer_calls << { name:, entry_htmls:, output: }
            File.join(Common::BUILD_PDF_DIR, "vivliostyle.config.#{name}.js")
          }
          Build::VivliostyleConfigWriter.stub :write!, writer_stub do
            PdfCommands.stub :execute_pdf, ->(opts, *args, **kwargs) { pdf_calls << kwargs } do
              pipeline.send(:generate_entries_and_pdf)
            end
          end

          # 用途別 config（single）が pdf/ へステージ済みの章 HTML で生成される
          assert_equal 1, writer_calls.size
          assert_equal 'single', writer_calls.first[:name]
          expected_htmls = ['11-sample', '12-tutorial'].map { File.join(Common::BUILD_PDF_DIR, "#{it}.html") }
          assert_equal expected_htmls, writer_calls.first[:entry_htmls]
          # pdf コマンドが生成 config で呼ばれる
          assert_equal 1, pdf_calls.size
          assert_equal File.join(Common::BUILD_PDF_DIR, 'output.pdf'), pdf_calls.first[:output_path]
        end
      end

      def test_rename_single_mode_pdf_single_chapter
        within_temp_dir do
          # ワークスペース pdf/ に output.pdf を作成
          FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
          FileUtils.touch(File.join(Common::BUILD_PDF_DIR, 'output.pdf'))

          pipeline = build_pipeline(['54-operator'])

          # CONFIG をモック
          with_mock_config({ 'pdf' => { 'output_file' => 'output.pdf' } }) do
            pipeline.send(:rename_single_mode_pdf)
          end

          assert File.exist?('54-operator.pdf'), '単章PDFにリネームされるべき'
          refute File.exist?(File.join(Common::BUILD_PDF_DIR, 'output.pdf')), 'ワークスペースの output.pdf は移動されるべき'
          assert_equal '54-operator.pdf', pipeline.generated_pdf_name
        end
      end

      def test_rename_single_mode_pdf_multiple_chapters
        within_temp_dir do
          FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
          FileUtils.touch(File.join(Common::BUILD_PDF_DIR, 'output.pdf'))

          pipeline = build_pipeline(['54-operator', '55-condition', '56-loop'])

          with_mock_config({ 'pdf' => { 'output_file' => 'output.pdf' } }) do
            pipeline.send(:rename_single_mode_pdf)
          end

          assert File.exist?('54-56.pdf'), '範囲名のPDFにリネームされるべき'
          assert_equal '54-56.pdf', pipeline.generated_pdf_name
        end
      end

      private

      def build_pipeline(targets)
        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        # targets を Entry オブジェクトに変換
        entries = targets.map { |bn| make_entry(bn) }
        BuildCommands::UnifiedBuildPipeline.new(command, entries: entries, mode: :single)
      end

      def make_entry(basename)
        name = basename.sub(/\.md\z/, '')
        num = name[/\A(\d+)-/, 1]&.to_i
        slug = name.sub(/\A\d+-/, '')
        TokenResolver::Entry.new(
          number: num,
          slug: slug,
          kind: :chapter,
          label: name,
          path: "contents/#{name}.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
      end

      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { yield dir }
        end
      end

      def with_mock_config(config_hash)
        original_config = Common.const_get(:CONFIG).dup rescue {}
        Common.send(:remove_const, :CONFIG) if Common.const_defined?(:CONFIG)
        Common.const_set(:CONFIG, config_hash)
        yield
      ensure
        Common.send(:remove_const, :CONFIG) if Common.const_defined?(:CONFIG)
        Common.const_set(:CONFIG, original_config)
      end
    end
  end
end
