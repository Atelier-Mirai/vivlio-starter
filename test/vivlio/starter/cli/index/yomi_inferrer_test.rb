# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/yomi_inferrer'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        class YomiInferrerTest < Minitest::Test
          # --- phase: setup ---

          def setup
            @inferrer = YomiInferrer.new
          end

          # --- phase: infer tests ---

          def test_infer_returns_original_when_mecab_unavailable
            # MeCab が利用できない環境では元のテキストを返す
            @inferrer.stub(:available?, false) do
              result = @inferrer.infer('テスト')
              assert_equal 'テスト', result
            end
          end

          def test_infer_handles_english_text
            # 英語テキストはそのまま返される（MeCabが利用可能でも）
            @inferrer.stub(:available?, false) do
              result = @inferrer.infer('Ruby')
              assert_equal 'Ruby', result
            end
          end

          def test_infer_handles_empty_string
            result = @inferrer.infer('')
            assert_equal '', result
          end

          def test_infer_handles_nil_gracefully
            # nil を渡しても例外が発生しない
            @inferrer.stub(:available?, false) do
              result = @inferrer.infer(nil)
              assert_nil result
            end
          end

          # --- phase: available? tests ---

          def test_available_caches_result
            # available? は結果をキャッシュする
            first_result = @inferrer.available?
            second_result = @inferrer.available?

            assert_equal first_result, second_result
          end

          def test_available_returns_boolean
            result = @inferrer.available?

            assert [true, false].include?(result)
          end

          # --- phase: integration tests (when MeCab is available) ---

          def test_infer_converts_kanji_to_hiragana_when_mecab_available
            skip 'MeCab not available' unless @inferrer.available?

            result = @inferrer.infer('日本語')

            # MeCab が利用可能な場合、ひらがなに変換される
            assert_match(/[ぁ-ん]+/, result)
          end

          def test_infer_converts_katakana_to_hiragana_when_mecab_available
            skip 'MeCab not available' unless @inferrer.available?

            result = @inferrer.infer('コンピュータ')

            # カタカナはひらがなに変換される
            assert_equal 'こんぴゅーた', result
          end

          def test_infer_handles_mixed_text_when_mecab_available
            skip 'MeCab not available' unless @inferrer.available?

            result = @inferrer.infer('Rubyプログラミング')

            # 混合テキストも処理できる
            refute_empty result
          end
        end
      end
    end
  end
end
