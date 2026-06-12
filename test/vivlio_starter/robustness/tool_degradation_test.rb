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
require 'tmpdir'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/metrics/analyzer'
require 'vivlio_starter/cli/build/backlink_dedup_orchestrator'
require 'vivlio_starter/cli/pdf'

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

      # DG-03a: パイプライン（Step 12）経由では gs 不在でも exit せず、
      # 🟡 でスキップを案内して続行する（PDF 生成後にビルドを落とさない）
      def test_should_skip_compression_and_continue_in_pipeline_without_ghostscript
        in_project_with_pdf do
          warns = []
          compressor = PdfCommands::PdfCompressor.new({ pipeline: true }, 'output.pdf', nil)

          Common.stub :log_warn, ->(msg, **) { warns << msg } do
            compressor.stub :ghostscript_available?, false do
              capture_io { compressor.call }
            end
          end

          assert warns.any? { it.include?('スキップ') }, '🟡 で圧縮スキップを案内するべき'
          refute_path_exists 'output_compressed.pdf', '圧縮ファイルは生成されない'
        end
      end

      # DG-03b: 単体コマンド（vs pdf:compress）では利用者の明示要求のため
      # 🔴 + doctor 案内 + exit 1 で報告する
      def test_should_exit_with_error_for_standalone_compress_without_ghostscript
        in_project_with_pdf do
          errors = []
          compressor = PdfCommands::PdfCompressor.new({}, 'output.pdf', nil)

          Common.stub :log_error, ->(msg, **) { errors << msg } do
            compressor.stub :ghostscript_available?, false do
              e = assert_raises(SystemExit) { capture_io { compressor.call } }
              assert_equal 1, e.status
            end
          end

          assert errors.any? { it.include?('Ghostscript') }, '🔴 で gs 不在を報告するべき'
        end
      end

      # DG-04: waifu2x 不在でも 🟡 案内の上 ImageMagick のみで
      # frontispiece / ornament 生成が完走する
      # （waifu2x の不在は存在しないパスを渡して再現。画像は magick で生成した
      # 小さな実画像を使い、AI 拡大なしの実処理パスを通す）
      def test_should_fall_back_to_imagemagick_without_waifu2x
        skip 'ImageMagick (magick) が見つかりません' unless system('which magick >/dev/null 2>&1')

        Dir.mktmpdir('vs-degradation') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('stylesheets/images')
            created = system('magick -size 200x150 gradient:navy-pink stylesheets/images/dg04.png',
                             out: File::NULL, err: File::NULL)
            skip 'テスト画像の生成に失敗しました' unless created

            warns = []
            result = nil
            Common.stub :log_warn, ->(msg, **) { warns << msg } do
              capture_io do
                result = PreProcessCommands::ImageGenerator.generate_frontispiece_and_ornament_from(
                  'dg04.png', waifu2x: '/nonexistent/waifu2x-ncnn-vulkan'
                )
              end
            end

            assert result, 'waifu2x 不在でも生成は成功（true）するべき'
            assert warns.any? { it.include?('waifu2x') && it.include?('ImageMagick のみで生成します') },
                   '🟡 で ImageMagick フォールバックを案内するべき'
            assert_path_exists 'stylesheets/images/dg04_portrait.webp'
            assert_path_exists 'stylesheets/images/dg04_landscape.webp'
          end
        end
      end

      private

      # ダミーの output.pdf を持つ一時プロジェクトへ chdir する（DG-03 用）
      def in_project_with_pdf(&)
        Dir.mktmpdir('vs-degradation') do |dir|
          Dir.chdir(dir) do
            File.write('output.pdf', '%PDF-1.4')
            yield
          end
        end
      end
    end
  end
end
