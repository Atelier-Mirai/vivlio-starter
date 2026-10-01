# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/yomi_inferrer'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class YomiInferrerTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @inferrer = YomiInferrer.new
        end

        # --- phase: 読みの個人辞書（overrides）の優先 ---

        # overrides に登録された読みは MeCab 有無に関わらず最優先で返る。
        def test_infer_prefers_yomi_overrides_over_mecab
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/index_yomi_overrides.yml',
                         { 'yomi' => { '重力' => 'じゅうりょく' } }.to_yaml)

              # 新しいインスタンス（override をロードさせる）で検証
              result = YomiInferrer.new.infer('重力')

              assert_equal 'じゅうりょく', result
            end
          end
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

        # 語だけを解析すると「章」が人名（アキラ）と読まれる。人名・動詞を含まない解析を選ぶ（改善案 #99）
        def test_infer_avoids_person_name_readings
          skip 'MeCab が利用できない環境ではスキップ' unless @inferrer.available?
          @inferrer.instance_variable_set(:@overrides, {})

          assert_equal 'ぜんしょう', @inferrer.infer('全章')
          assert_equal 'しょうばんごう', @inferrer.infer('章番号')
        end

        # 英字が残る読みでは語の空白を残す（「fancylist」にしない）。仮名どうしの間は詰める（改善案 #99）
        def test_infer_keeps_spaces_next_to_latin_readings
          skip 'MeCab が利用できない環境ではスキップ' unless @inferrer.available?
          @inferrer.instance_variable_set(:@overrides, {})

          assert_equal 'fancy list', @inferrer.infer('fancy list')
          assert_equal 'Re:VIEW Starter', @inferrer.infer('Re:VIEW Starter')
          assert_equal 'Markdown ふぁいる', @inferrer.infer('Markdown ファイル')
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
