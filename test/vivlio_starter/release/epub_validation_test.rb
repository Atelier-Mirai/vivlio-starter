# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/epub_validation_test.rb
#
# EPUB 構造検証（EP）— docs/specs/test-suite-expansion-spec.md §13
#
# 【検証内容】
#   EP-01: output.targets を epub に切り替えてビルド → exit 0・.epub 生成
#   EP-02: 生成 .epub に epubcheck → FATAL / ERROR が 0 件
#
# 【実行方法】
#   rake test:manual   （リポジトリルートで実行。実ビルドを伴う）
#
# 【注意】
#   - book.yml の書き換えは BookYmlPatcher.rewrite_line で行い、必ず復元する
#   - epubcheck（Java 依存・brew install epubcheck）が無い環境では EP-02 を skip
# =============================================================================

require "minitest/autorun"
require_relative "../support/build_helper"

class EpubValidationTest < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle].freeze

  class << self
    # EPUB ビルドは高コストのため 1 回だけ実行し、結果を EP-01 / EP-02 で共有する
    def epub_result
      @epub_result ||= build_epub_once
    end

    private

    def build_epub_once
      success = nil
      output = nil
      epub = nil

      VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s+)targets:\s*pdf\b.*$/, '\1targets: epub') do
        success, output = VsTestSupport::VsBuilder.build!(
          vs_command: VsTestSupport::VsBuilder.repo_vs_command
        )
        epub = Dir.glob("*.epub").max_by { File.mtime(it) }
      end

      { success: success, output: output, epub: epub }
    end
  end

  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")

    missing = REQUIRED_TOOLS.reject { system("which #{it} >/dev/null 2>&1") }
    skip "ビルドに必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?
  end

  # EP-01: epub ターゲットでのビルドが成功し、.epub が生成される
  def test_should_build_epub_successfully
    result = self.class.epub_result

    assert result[:success],
           "epub ターゲットのビルドが失敗しました\n#{result[:output].lines.last(20).join}"
    refute_nil result[:epub], ".epub が生成されませんでした"
    assert File.size(result[:epub]).positive?
  end

  # EP-02: epubcheck による構造検証（FATAL / ERROR ゼロ）
  def test_should_pass_epubcheck_validation
    skip "epubcheck が見つかりません（brew install epubcheck で導入できます）" \
      unless system("which epubcheck >/dev/null 2>&1")

    result = self.class.epub_result
    skip ".epub が無いため epubcheck をスキップします" unless result[:epub]

    report = `epubcheck #{result[:epub]} 2>&1`
    fatal_or_error = report.lines.select { it.match?(/^(FATAL|ERROR)/) }

    assert_empty fatal_or_error, <<~MSG
      epubcheck が FATAL / ERROR を報告しました:
      #{fatal_or_error.join}
    MSG
  end
end
