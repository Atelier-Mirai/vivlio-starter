# frozen_string_literal: true

# =============================================================================
# Test: fuzz/token_resolver_fuzz_test.rb
# =============================================================================
# テスト対象:
#   TokenResolver::Resolver
#
# 検証する性質（docs/specs/test-suite-expansion-spec.md §7.2）:
#   FZ-03: resolve(任意トークン列) は例外を出さず、常に Entry の配列を返す
#          （不正トークンは invalid Entry / 空配列として扱われ、クラッシュしない）
#
# CLI の章指定（vs build 11 12-15 intro 等）は利用者の自由入力がそのまま
# 渡るため、どんな文字列でも落ちないことを保証する。
# =============================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require_relative '../support/fuzz_generator'

module VivlioStarter
  module CLI
    class TokenResolverFuzzTest < Minitest::Test
      # 変異元: 実際に使われる妥当なトークン表記
      VALID_TOKENS = %w[11 11-intro 11-15 00 99 90 intro 11,12 11- -15 11-intro.md contents/11-intro.md].freeze

      # FZ-03: catalog のあるプロジェクトで任意トークン列を解決しても例外を出さない
      def test_should_resolve_any_token_sequence_without_raising
        with_temp_project do
          fuzz_tokens(seed: 20_260_615).each do |tokens|
            entries = TokenResolver::Resolver.new.resolve(tokens)

            assert_kind_of Array, entries, failure_for(tokens, '戻り値が配列でない')
            entries.each { assert_kind_of TokenResolver::Entry, it, failure_for(tokens, 'Entry 以外が混入') }
          rescue StandardError => e
            flunk failure_for(tokens, "例外が送出された: #{e.class}: #{e.message}")
          end
        end
      end

      # catalog.yml が無い（プロジェクト未設定の）状態でも同じ性質が成り立つ
      def test_should_resolve_any_token_sequence_without_catalog
        Dir.mktmpdir('vs-fuzz-resolver') do |dir|
          Dir.chdir(dir) do
            fuzz_tokens(seed: 20_260_616).each do |tokens|
              entries = TokenResolver::Resolver.new.resolve(tokens)

              assert_kind_of Array, entries, failure_for(tokens, '戻り値が配列でない')
            rescue StandardError => e
              flunk failure_for(tokens, "例外が送出された: #{e.class}: #{e.message}")
            end
          end
        end
      end

      private

      # 単一トークンの変異と複数トークン列の両方を生成する
      def fuzz_tokens(seed:)
        rng = Random.new(seed)
        singles = VsTestSupport::FuzzGenerator.corpus(seed: seed, count: 120, base_samples: VALID_TOKENS)
        multis = Array.new(40) do
          Array.new(rng.rand(1..4)) { singles[rng.rand(singles.size)] }
        end
        singles.map { [it] } + multis + [[]]
      end

      def failure_for(tokens, reason)
        "#{reason}\n  トークン列: #{tokens.inspect[0, 300]}"
      end

      def with_temp_project(&)
        Dir.mktmpdir('vs-fuzz-resolver') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            File.write('config/catalog.yml', "PREFACE:\n  - 00-preface\nCHAPTERS:\n  - 11-intro\nAPPENDICES:\nPOSTFACE:\n")
            File.write('contents/00-preface.md', "# preface\n")
            File.write('contents/11-intro.md', "# intro\n")
            yield
          end
        end
      end
    end
  end
end
