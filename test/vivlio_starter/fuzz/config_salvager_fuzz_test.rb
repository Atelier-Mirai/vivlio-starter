# frozen_string_literal: true

# =============================================================================
# Test: fuzz/config_salvager_fuzz_test.rb
# =============================================================================
# テスト対象:
#   DoctorCommands::ConfigSalvager / Guards::ConfigValidityCheck
#
# 検証する性質（docs/specs/test-suite-expansion-spec.md §7.2）:
#   FZ-01: salvage(book.yml, 任意文字列) は例外を出さない。
#          戻り値は nil または「妥当な YAML Hash になる content」を持つ Result
#   FZ-02: salvage(catalog.yml, 任意文字列) + ランダムな contents/ 構成 で同上
#   FZ-04: ConfigValidityCheck.diagnose(任意内容のファイル) は例外を出さず
#          :ok / :missing / :corrupt のいずれかを返す
#
# シードは固定（決定的）。失敗時は再現入力を inspect でメッセージに含める。
# =============================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'
require 'vivlio_starter/cli/guards'
require_relative '../support/fuzz_generator'

module VivlioStarter
  module CLI
    class ConfigSalvagerFuzzTest < Minitest::Test
      SCAFFOLD_BOOK_YML = File.join(DoctorCommands::SCAFFOLD_CONFIG_DIR, 'book.yml')

      # 変異元: 実際の book.yml に近い妥当入力
      VALID_BOOK_SAMPLE = <<~YAML
        book:
          main_title: "わたしの技術書"
          subtitle: "副題テスト"
          author: "アトリヱ未來"
          series: "「技術書典20 新刊」"
        project:
          name: "mybook"
      YAML

      # FZ-01: 任意入力で salvage(book.yml) が例外を出さず、救出結果は常に妥当な YAML
      def test_should_never_raise_and_always_yield_valid_yaml_for_book_salvage
        in_tmpdir do
          each_fuzz_input(seed: 20_260_612, base: VALID_BOOK_SAMPLE) do |input|
            result = DoctorCommands::ConfigSalvager.salvage('config/book.yml', input, SCAFFOLD_BOOK_YML)
            next if result.nil?

            parsed = YAML.safe_load(result.content, aliases: true)
            assert_kind_of Hash, parsed, failure_for(input, '救出結果が妥当な YAML Hash でない')
          rescue StandardError => e
            flunk failure_for(input, "例外が送出された: #{e.class}: #{e.message}")
          end
        end
      end

      # FZ-02: ランダムな contents/ 構成で salvage(catalog.yml) が例外を出さない
      def test_should_never_raise_for_catalog_salvage_with_odd_contents
        odd_basenames = [
          '00-preface', '11-normal', '99', '100-over', '999999-huge', '0011-zero-pad',
          '12-日本語スラッグ', '13-with space', '14-quote"name', '_titlepage', '_legal',
          'noprefix', '15_underscore', '16-', '-17'
        ]

        in_tmpdir do
          FileUtils.mkdir_p('contents')
          odd_basenames.each { File.write("contents/#{it}.md", "# x\n") }

          each_fuzz_input(seed: 20_260_613, base: "PREFACE:\nCHAPTERS:\n  - 11-normal\n") do |input|
            result = DoctorCommands::ConfigSalvager.salvage('config/catalog.yml', input, SCAFFOLD_BOOK_YML)
            next if result.nil?

            parsed = YAML.safe_load(result.content)
            assert_kind_of Hash, parsed, failure_for(input, '再構築結果が妥当な YAML Hash でない')
          rescue StandardError => e
            flunk failure_for(input, "例外が送出された: #{e.class}: #{e.message}")
          end
        end
      end

      # FZ-04: 任意内容のファイルに対して diagnose が例外を出さず 3 状態のいずれかを返す
      def test_should_diagnose_any_file_content_without_raising
        in_tmpdir do
          FileUtils.mkdir_p('config')

          each_fuzz_input(seed: 20_260_614, base: VALID_BOOK_SAMPLE) do |input|
            File.binwrite('config/fuzz.yml', input)
            status, = Guards::ConfigValidityCheck.diagnose('config/fuzz.yml')

            assert_includes %i[ok missing corrupt], status, failure_for(input, "未知の状態: #{status.inspect}")
          rescue StandardError => e
            flunk failure_for(input, "例外が送出された: #{e.class}: #{e.message}")
          end
        end
      end

      private

      def each_fuzz_input(seed:, base:, &)
        VsTestSupport::FuzzGenerator.corpus(seed:, count: 150, base_samples: [base]).each(&)
      end

      # 失敗時に再現可能なよう入力そのものを報告する
      def failure_for(input, reason)
        "#{reason}\n  入力(#{input.bytesize} bytes): #{input.inspect[0, 300]}"
      end

      def in_tmpdir(&)
        Dir.mktmpdir('vs-fuzz') { |dir| Dir.chdir(dir, &) }
      end
    end
  end
end
