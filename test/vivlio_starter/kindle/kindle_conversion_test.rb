# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/kindle/kindle_conversion_test.rb
#
# Kindle 変換検証テスト（opt-in・Mac/Win ローカル専用）
#
# 【背景】
#   vs build が生成する EPUB を Kindle Previewer で変換すると、画像が WebP の
#   ままだと Kindle が非対応で「無効な画像」（W14015/W14012）になり変換不能だった
#   （docs/specs/epub-kindle-webp-incompatibility-report.md）。WebP→JPEG/PNG
#   トランスコード（epub-kindle-webp-transcode-spec.md §5-1）後、Kindle Previewer 3
#   の CLI で実変換し、画像系警告がゼロであることを実機検証する。
#
# 【検証内容】
#   - epub をビルド → kindlepreviewer -convert で実変換
#   - conversionLog CSV に画像系コード W14015 / W14012 / W14010 が 1 件も無い
#
# 【実行方法】
#   rake test:kindle    （要 Kindle Previewer 3 = kindlepreviewer / ImageMagick。
#                          実ビルド＋実変換を伴うため遅い。通常 test からは除外）
#   ※ リポジトリルートで実行すること。Linux CI や CLI 未導入環境では skip する。
# =============================================================================

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../support/build_helper"

class KindleConversionTest < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle qpdf gs unzip magick kindlepreviewer].freeze
  # Kindle が「画像が無効/見つからない/非対応フォーマット」として出す警告コード
  IMAGE_WARNING_CODES = %w[W14015 W14012 W14010].freeze

  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")

    missing = REQUIRED_TOOLS.reject { system("which #{it} >/dev/null 2>&1") }
    skip "Kindle 検証に必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?
  end

  # epub を実変換し、画像系警告（W14015/W14012/W14010）が 1 件も出ないことを確認する
  def test_should_convert_epub_without_image_warnings
    epub = build_epub!
    refute_nil epub, "epub 成果物が生成されませんでした"

    Dir.mktmpdir("vs-kindle-out") do |outdir|
      run_kindle_previewer!(epub, outdir)

      # Kindle Previewer 3 は Summary_Log.csv と Logs/<book>_log.csv を出力する。
      # 版差でファイル名が変わっても拾えるよう、出力配下の全 CSV を走査対象にする。
      csvs = Dir.glob(File.join(outdir, "**", "*.csv"))
      refute_empty csvs, "Kindle Previewer のログ CSV が見つかりません（変換が失敗した可能性）"

      offending = csvs.flat_map do |csv|
        File.readlines(csv, encoding: "UTF-8").select do |line|
          IMAGE_WARNING_CODES.any? { |code| line.include?(code) }
        end
      end

      assert_empty offending,
                   "Kindle 変換で画像系警告が残っています（#{offending.size} 件）:\n#{offending.first(10).join}"
    end
  ensure
    cleanup_artifacts!
  end

  private

  # targets: epub に切り替えてビルドし、生成された epub の絶対パスを返す
  def build_epub!
    cleanup_artifacts!
    VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s*)targets:\s*[^\n]*$/, "\\1targets: epub") do
      ok, output = VsTestSupport::VsBuilder.build!(vs_command: VsTestSupport::VsBuilder.repo_vs_command)
      raise "vs build（targets: epub）が失敗しました:\n#{output.lines.last(20).join}" unless ok
    end
    latest = Dir.glob("*.epub").max_by { File.mtime(it) }
    latest && File.expand_path(latest)
  end

  # Kindle Previewer 3 CLI で EPUB を変換する（KPF/Mobi を outdir に生成し、ログを出す）
  def run_kindle_previewer!(epub, outdir)
    system("kindlepreviewer", epub, "-convert", "-output", outdir, "-locale", "en",
           out: File::NULL, err: File::NULL)
  end

  def cleanup_artifacts!
    Dir.glob("*.epub").each { FileUtils.rm_f(it) }
  end
end
