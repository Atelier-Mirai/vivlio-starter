# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    # 廃止した設定キーの検出（Common::RETIRED_CONFIG_KEYS）
    #
    # キーを廃止するたびに各コマンドが book.yml を読みに行くのでは、CONFIG へ
    # 集約した意味が薄れる。検出と案内は登録簿 1 つに集約し、全コマンド共通の
    # 関門（ensure_configured!）で 1 度だけ発火させる、という設計を固定する。
    class RetiredConfigKeysTest < Minitest::Test
      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('retired_keys_test')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
        Common.instance_variable_set(:@authored_keys, nil)
        Common.instance_variable_set(:@retired_keys_reported, nil)
      end

      def authored(hash)
        Common.instance_variable_set(:@retired_keys_reported, nil)
        Common.instance_variable_set(:@authored_keys, Common.collect_key_paths(hash))
      end

      # --- phase: 著者が何を書いたか（CONFIG では答えられない問い） ---

      def test_collect_key_paths_records_nested_paths
        paths = Common.collect_key_paths({ index: { target_terms: 'standard' } })

        assert_includes paths, %i[index]
        assert_includes paths, %i[index target_terms]
      end

      # 廃止キー検出の内部実装なので send で呼ぶ。公開 API から外してあること自体が
      # 仕様である——現役キーに使うと常に真になり、意図の代理に使えない
      # （config-retirement-guidelines.md §3）。
      def test_authored_key_answers_what_the_author_wrote
        authored({ index: { target_terms: 260 } })

        assert Common.send(:authored_key?, :index, :target_terms)
        refute Common.send(:authored_key?, :index, :candidate_pool),
               '書いていないキーは false（既定値が効くこととは別の問い）'
      end

      # 外から呼べないこと自体を固定する（呼べると誤用が再発する）
      def test_authored_key_is_not_public
        assert_raises(NoMethodError) { Common.authored_key?(:index, :target_terms) }
      end

      # --- phase: 廃止キーの案内 ---

      def test_warns_for_each_retired_key_with_guidance
        authored({ index: { auto_approve_threshold: 300, high_candidates_ratio: 0.25 } })

        out, err = capture_io { Common.warn_retired_config_keys }
        combined = out + err

        assert_match(/index\.auto_approve_threshold.*廃止/, combined)
        assert_match(/index\.high_candidates_ratio.*廃止/, combined)
        assert_match(/target_terms/, combined, '代わりに何をするかまで示す')
        assert_match(/読み込まれません/, combined, '値が無視されることを明言する')
      end

      def test_stays_silent_when_no_retired_key_is_written
        authored({ index: { target_terms: 'standard', candidate_pool: 3.0 } })

        out, err = capture_io { Common.warn_retired_config_keys }

        assert_empty (out + err).strip
      end

      # 同じ実行で何度呼ばれても案内は 1 度だけ。コマンドが内部で複数回
      # 設定に触れても、著者には同じ警告が繰り返し見えないようにする。
      def test_reports_only_once_per_run
        authored({ index: { review_threshold: 150 } })

        first, = capture_io { Common.warn_retired_config_keys }
        second, = capture_io { Common.warn_retired_config_keys }

        refute_empty first.strip
        assert_empty second.strip
      end

      # --- phase: 登録簿の健全性 ---

      # 廃止キーがスキーマに残っていると CONFIG に載ってしまい、
      # 「廃止したのに読める」という中途半端な状態になる。
      def test_retired_keys_are_absent_from_the_default_schema
        schema = Common.default_config_schema

        Common::RETIRED_CONFIG_KEYS.each_key do |path|
          section = schema[path.first]
          next unless section.is_a?(Hash)

          refute_includes section.keys, path.last,
                          "#{path.join('.')} は廃止キーなので既定値スキーマに残さない"
        end
      end

      def test_every_retired_key_carries_actionable_guidance
        Common::RETIRED_CONFIG_KEYS.each do |path, guidance|
          refute_empty guidance.to_s.strip, "#{path.join('.')} に案内文がない"
        end
      end
    end
  end
end
