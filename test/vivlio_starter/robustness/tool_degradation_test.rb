# frozen_string_literal: true

# ================================================================
# robustness: 外部ツール欠落時のグレースフルデグラデーション（DG）
# ================================================================
# docs/specs/test-suite-expansion-spec.md §8
#
# 検証内容:
#   DG-01: mecab 不在 → metrics の解析が簡易トークナイザへ縮退して完走する
#   DG-02: playwright/chromium 不在 → バックリンク重複排除がスキップされ
#          ビルド処理が例外なく続行する
#   DG-03: gs 不在 → 圧縮スキップ（現状は exit(1) するため skip / 課題切り出し）
#   DG-04: waifu2x 不在 → ImageMagick のみへフォールバック（画像実処理と
#          不可分なため本階層では対象外。skip に理由を記載）
#
# 既存の robustness/missing_external_command_test.rb は「エラーメッセージの
# 品質」を対象としており、本テストは「縮退して完走するか」を対象とする
# （spec §1.1 の分担）。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/metrics/analyzer'
require 'vivlio_starter/cli/build/backlink_dedup_orchestrator'

module VivlioStarter
  module CLI
    class ToolDegradationTest < Minitest::Test
      SAMPLE_TEXT = <<~MD
        # 見出し

        日本語の文章を解析する。MeCab が無い環境でも、簡易トークナイザで
        文字数や文の長さなどの基本統計は算出できることを確認する。
      MD

      # DG-01: MeCab 不在でも Analyzer は簡易トークナイザで全統計を完走する
      def test_should_complete_metrics_analysis_without_mecab
        # @mecab_available は initialize 内で判定されるため、判定メソッドを
        # オーバーライドした匿名サブクラスで「不在」を注入する（グローバル汚染なし）
        degraded_analyzer = Class.new(Metrics::Analyzer) do
          private def check_mecab_available = false
        end.new(SAMPLE_TEXT)

        basic = degraded_analyzer.basic_stats
        vocabulary = degraded_analyzer.vocabulary_stats

        assert_operator basic.chars, :>, 0
        assert_operator basic.sentences, :>, 0
        assert_operator vocabulary.kanji_ratio, :>, 0, '簡易トークナイザでも漢字比率は算出されるべき'
        assert_operator vocabulary.ttr, :>, 0, '簡易トークナイザでも TTR は算出されるべき'
      end

      # DG-02a: ページマッピングが取得できない（playwright 不在相当）場合、
      # 重複排除はスキップされ、例外なく false を返してビルドが続行できる
      def test_should_skip_backlink_dedup_when_page_mapping_unavailable
        orchestrator = Build::BacklinkDedupOrchestrator

        result = nil
        orchestrator.stub :dedup_enabled?, true do
          orchestrator.stub :dedup_target_exists?, true do
            orchestrator.stub :extract_page_mapping, nil do
              capture_io { result = orchestrator.run! }
            end
          end
        end

        assert_equal false, result, '重複排除はスキップ（false）でビルド続行するべき'
      end

      # DG-02b: 重複排除の途中で想定外例外が起きても 🟡 警告 + false で続行する
      def test_should_warn_and_continue_when_dedup_raises
        orchestrator = Build::BacklinkDedupOrchestrator
        warns = []

        result = nil
        Common.stub :log_warn, ->(msg, **) { warns << msg } do
          orchestrator.stub :dedup_enabled?, true do
            orchestrator.stub :dedup_target_exists?, true do
              orchestrator.stub :extract_page_mapping, ->(*) { raise 'playwright crashed' } do
                capture_io { result = orchestrator.run! }
              end
            end
          end
        end

        assert_equal false, result
        assert warns.any? { it.include?('重複排除') }, '🟡 で重複排除のスキップを案内するべき'
      end

      # DG-03: gs 不在時の圧縮スキップ
      def test_should_skip_compression_without_ghostscript
        skip <<~REASON
          【課題切り出し済み・spec §8.3】現状の PdfCompressor#compress_pdf は gs 不在時に
          「圧縮をスキップします」と警告しつつ exit(1) で停止する（pdf.rb:374-376）。
          ビルド Step 12 経由では PDF 生成後にビルド全体が落ちるため、
          「単体コマンドは exit 1 / パイプライン内はスキップ続行」の文脈分離を
          別タスクで設計・修正した後に本テストを有効化する。
        REASON
      end

      # DG-04: waifu2x 不在時の ImageMagick フォールバック
      def test_should_fall_back_to_imagemagick_without_waifu2x
        skip <<~REASON
          【対象外の理由・spec §8.3】ImageGenerator の waifu2x フォールバック判定は
          実画像の生成処理（ImageMagick 実行）と不可分なため、スタブのみでは
          「完走」を検証できない。実画像を伴う検証は rake test:manual 階層の
          ビルド（waifu2x 有無の差は 🟡 案内のみ）で間接的にカバーされる。
        REASON
      end
    end
  end
end
