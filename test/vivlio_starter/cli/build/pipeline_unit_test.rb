# frozen_string_literal: true

# ================================================================
# Test: pipeline_unit_test.rb
# ================================================================
# テスト対象:
#   UnifiedBuildPipeline の「単位（unit）」軸（build-mode-parity-spec.md §2）
#
# なぜ必要か:
#   単章モードのステップ表は、以前はモードごとに手で維持されていた。片方への
#   追加がもう片方へ届かないため、「単章では ○○ だったが全章では ×× だった」が
#   繰り返し起きていた（実測: 補償コード 5 箇所・3 ファイル）。
#
#   いまは単章モードを `unit: :chapter` からの導出に置き換えてある。この導出が
#   壊れると差分がまた手作業に戻るので、構造そのものを固定する。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module BuildCommands
      class PipelineUnitTest < Minitest::Test
        Pipeline = UnifiedBuildPipeline

        # 単位の値は 2 つだけ。増やすなら仕様書（§2.1）から見直す
        VALID_UNITS = %i[chapter whole_book].freeze

        # 単章固有の出力ステップ。章単位の導出とは別に足すもので、
        # 閲覧用 PDF のみ・ファイル名も違う（章名.pdf）ため全章の結合とは別物。
        # `final clean` は全章表にも同名の行があるが、あちらは :join 相で
        # 他ターゲットの完了を待つためのもの。単章は待つ相手がいないので自前で持つ。
        SINGLE_ONLY = ['entries.js + pdf', 'rename output pdfs', 'final clean'].freeze

        def setup
          skip 'config/book.yml が見つかりません（リポジトリルートで実行してください）' unless File.exist?('config/book.yml')
        end

        # ステップ表の各行から [ラベル, 単位] を取り出す。
        # ハンドラは呼ばないので、実ビルドは起きない。
        def step_table
          pipeline = Pipeline.allocate
          pipeline.instance_variable_set(:@targets, Build::Targets.resolve)
          pipeline.instance_variable_set(:@entries, [])
          pipeline.send(:full_mode_step_table)
        end

        # --- 宣言漏れの検出 -------------------------------------------------

        # 単位を書き忘れた行は既定（:whole_book）に落ちるため、**単章から静かに消える**。
        # 消えたこと自体は気づきにくいので、宣言を必須にして書き忘れを落とす。
        def test_every_step_declares_a_unit
          missing = step_table.reject { |row| row[4] }.map(&:first)

          assert_empty missing, "単位（第 5 要素）の宣言が無いステップ: #{missing.join(', ')}"
        end

        def test_units_are_within_the_known_set
          unknown = step_table.filter_map { |row| row[4] unless VALID_UNITS.include?(row[4]) }.uniq

          assert_empty unknown, "未知の単位: #{unknown.join(', ')}（有効値: #{VALID_UNITS.join(' / ')}）"
        end

        # --- 逸脱の宣言制 ---------------------------------------------------

        # 章単位でありながら単章で走らせないものは SINGLE_MODE_SKIP に**理由つきで**書く。
        # 表に無い逸脱は認めない（§3.1）
        def test_single_mode_skip_entries_are_chapter_scoped_and_reasoned
          chapter_labels = step_table.select { |row| row[4] == :chapter }.map(&:first)

          Pipeline::SINGLE_MODE_SKIP.each do |label, reason|
            assert_includes chapter_labels, label,
                            "#{label} は章単位ではないので SINGLE_MODE_SKIP に書く必要がない"
            refute_empty reason.to_s, "#{label} の逸脱に理由が書かれていない"
          end
        end

        # --- 導出 -----------------------------------------------------------

        # 単章モードのステップ集合＝「:chapter かつ SINGLE_MODE_SKIP でない」＋単章固有の出力。
        # ここが崩れると、モードごとに表を手で持っていた時代へ戻る
        def test_single_mode_runs_every_chapter_scoped_step
          expected = step_table
                     .select { |row| row[2] && row[4] == :chapter }
                     .map(&:first)
                     .reject { |label| Pipeline::SINGLE_MODE_SKIP.key?(label) }

          refute_empty expected, '章単位のステップが 1 つも無い（表の宣言が壊れている）'

          assert_equal (expected + SINGLE_ONLY), single_mode_step_labels
        end

        # techbook は章単位だが単章では走らせない（Type 3 対策は入稿用の関心事）
        def test_single_mode_excludes_declared_skips
          refute_includes single_mode_step_labels, 'techbook post-process'
        end

        # 全書籍を単位とするものは単章に現れない
        def test_single_mode_excludes_whole_book_steps
          whole_book = step_table.select { |row| row[4] == :whole_book }.map(&:first)
          derived = single_mode_step_labels - SINGLE_ONLY

          (whole_book & derived).tap do |leaked|
            assert_empty leaked, "全書籍単位のステップが単章へ漏れている: #{leaked.join(', ')}"
          end
        end

        private

        # 単章モードで登録されるステップのラベル列（ハンドラは呼ばない）
        def single_mode_step_labels
          @single_mode_step_labels ||= begin
            pipeline = Pipeline.allocate
            pipeline.instance_variable_set(:@targets, Build::Targets.resolve)
            pipeline.instance_variable_set(:@entries, [])
            pipeline.instance_variable_set(:@steps, [])
            pipeline.send(:register_single_mode_steps)
            pipeline.instance_variable_get(:@steps).map(&:label)
          end
        end
      end
    end
  end
end
