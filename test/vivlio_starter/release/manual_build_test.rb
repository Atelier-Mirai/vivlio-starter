# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/manual_build_test.rb
#
# マニュアルフルビルド（MB）+ PDF フォント検査（FT）
# docs/specs/test-suite-expansion-spec.md §4 / §5
#
# 【検証内容】
#   MB-01: リポジトリルートで vs build → exit 0・PDF 生成
#   MB-02: 出力に 🔴 行が無い
#   MB-03: 出力に 🟡 行が無い（allowed_warnings.yml 記載分を除く）
#   MB-04: ビルドが git 作業ツリーを汚さない（§16-1）
#   FT-01: 生成 PDF に Type 3 フォントが存在しない
#   FT-02: 全フォントが埋め込み済み
#   FT-03: 標準添付書体が実際に使用されている
#
# 【実行方法】
#   rake test:manual   （リポジトリルートで実行。1 ビルド 2 分強かかる）
#
# 【注意】
#   ビルドはクラス全体で 1 回だけ実行し、ログと PDF を全テストで共有する。
#   リポジトリのソースコード（ruby -Ilib bin/vs）を直接実行するため、
#   インストール済み gem の状態には依存しない。
# =============================================================================

require "minitest/autorun"
require "yaml"
require_relative "../support/build_helper"

class ManualBuildTest < Minitest::Test
  ALLOWED_WARNINGS_PATH = File.expand_path("allowed_warnings.yml", __dir__)
  REQUIRED_TOOLS = %w[node vivliostyle qpdf gs].freeze

  # 標準添付書体（PDF にはサブセット接頭辞付きで埋め込まれるため部分一致で照合）
  STANDARD_FONT_NAMES = ["ZenOldMincho", "ZenKakuGothicNew"].freeze

  class << self
    # ビルドは高コスト（2 分強）のため 1 回だけ実行し、結果を全テストで共有する
    def build_result
      @build_result ||= run_build_once
    end

    private

    def run_build_once
      dirt_before = `git status --porcelain`
      success, output = VsTestSupport::VsBuilder.build!(
        vs_command: VsTestSupport::VsBuilder.repo_vs_command
      )
      {
        success: success,
        output: output,
        pdf: VsTestSupport::VsBuilder.find_latest_pdf,
        dirt_before: dirt_before,
        dirt_after: `git status --porcelain`
      }
    end
  end

  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")

    missing = REQUIRED_TOOLS.reject { system("which #{it} >/dev/null 2>&1") }
    skip "ビルドに必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?
  end

  # MB-01: フルビルドが成功し、PDF が生成される
  def test_should_build_manual_successfully
    result = self.class.build_result

    assert result[:success],
           "vs build が失敗しました\n#{result[:output].lines.last(20).join}"
    refute_nil result[:pdf], "PDF が生成されませんでした"
    assert File.size(result[:pdf]).positive?
  end

  # MB-02: エラー（🔴）が 1 行も出ていない
  def test_should_emit_no_error_lines
    errors = self.class.build_result[:output].lines.select { it.include?("🔴") }

    assert_empty errors, "ビルド出力に 🔴 エラーが含まれています:\n#{errors.join}"
  end

  # MB-03: 警告（🟡）が許容リスト記載分を除いて 1 行も出ていない
  def test_should_emit_no_warning_lines_except_allowed
    allowed = YAML.safe_load(File.read(ALLOWED_WARNINGS_PATH)).fetch("allowed", [])
    warnings = self.class.build_result[:output].lines
                   .select { it.include?("🟡") }
                   .reject { |line| allowed.any? { |pattern| line.include?(pattern) } }

    assert_empty warnings, <<~MSG
      ビルド出力に許容リスト外の 🟡 警告が含まれています:
      #{warnings.join}
      意図した警告であれば理由コメント付きで #{ALLOWED_WARNINGS_PATH} へ追加してください。
    MSG
  end

  # ビルドが書き込み得る領域（原稿・設定・素材）。追跡済み開発ファイル
  # （lib/ test/ docs/ 等）の変更はビルド中の開発者編集と区別できないため対象外
  # （ビルドがそこへ書き込む経路は存在しない）
  CONTENT_PREFIXES = %w[contents/ config/ images/ stylesheets/ covers/ codes/ templates/ data/ sources/].freeze

  # MB-04: ビルドが git 作業ツリーを汚さない
  # (a) 新たな未追跡エントリの出現 = 成果物の gitignore 漏れ
  # (b) 原稿・設定など追跡済みコンテンツの変更 = ビルドによる破壊
  def test_should_not_dirty_git_working_tree
    result = self.class.build_result
    new_dirt = result[:dirt_after].lines - result[:dirt_before].lines

    offending = new_dirt.select do |line|
      status = line[0, 2].to_s
      path = line[3..].to_s.strip
      status.include?("?") || CONTENT_PREFIXES.any? { path.start_with?(it) }
    end

    assert_empty offending, <<~MSG
      ビルドによって git 作業ツリーが汚れました（gitignore 漏れ、または原稿・設定への書き込み）:
      #{offending.join}
    MSG
  end

  # FT-01: Type 3 フォントが 1 つも埋め込まれていない（Chromium 由来の混入検知）
  def test_should_contain_no_type3_fonts
    type3 = pdf_fonts.select(&:type3?)

    assert_empty type3, <<~MSG
      Type 3 フォントが検出されました（Vivliostyle/Chromium 更新による再発の可能性）:
      #{type3.map { "  p.#{it.page} #{it.name}" }.uniq.join("\n")}
    MSG
  end

  # FT-02: すべてのフォントが埋め込み済み（非埋め込みは印刷所入稿で事故になる）
  def test_should_embed_all_fonts
    not_embedded = pdf_fonts.reject(&:embedded)

    assert_empty not_embedded, <<~MSG
      埋め込まれていないフォントが検出されました:
      #{not_embedded.map { "  p.#{it.page} #{it.name} (#{it.subtype})" }.uniq.join("\n")}
    MSG
  end

  # FT-03: 標準添付書体が実際に本文へ使用されている（差し替え漏れ・fallback 検知）
  def test_should_use_standard_bundled_fonts
    font_names = pdf_fonts.map(&:name).uniq

    STANDARD_FONT_NAMES.each do |expected|
      assert font_names.any? { it.include?(expected) },
             "標準添付書体 #{expected} が PDF 内に見つかりません（使用フォント: #{font_names.join(', ')}）"
    end
  end

  private

  def pdf_fonts
    result = self.class.build_result
    skip "PDF が無いためフォント検査をスキップします" unless result[:pdf]

    @pdf_fonts ||= VsTestSupport::PdfInspector.fonts(result[:pdf])
  end
end
