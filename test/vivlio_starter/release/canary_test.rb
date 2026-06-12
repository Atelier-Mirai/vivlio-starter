# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/canary_test.rb
#
# 依存カナリアテスト（CN）— docs/specs/test-suite-expansion-spec.md §14
#
# 【検証内容】
#   CN-01: @vivliostyle/cli の最新版でマニュアルがビルドでき、Type 3 フォントが
#          混入しない（上流更新による破壊・VFM 脚注問題の再来を検知）
#   CN-02: 最新版ビルドの 🟡/🔴 行を一覧表示する（差分の観測。失敗にはしない）
#
# 【実行方法】
#   rake test:canary    （ネットワーク必須。リリース判定には含めない）
#
# 【注意】
#   - グローバル npm 環境を汚さない: 一時ディレクトリへ --prefix インストールし、
#     PATH の先頭に向けて実行する
#   - 上流の破壊はこちらの欠陥ではないため、rake test:release には含めない
# =============================================================================

require "minitest/autorun"
require "tmpdir"
require_relative "../support/build_helper"

class CanaryTest < Minitest::Test
  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")
    skip "npm が見つかりません" unless system("which npm >/dev/null 2>&1")
  end

  # CN-01 + CN-02: 最新の @vivliostyle/cli でビルドし、フォント健全性と警告差分を観測する
  # （最新版の導入が高コストのため 1 メソッドに集約）
  def test_should_build_with_latest_vivliostyle_cli
    Dir.mktmpdir("vs-canary-npm") do |prefix|
      installed = system(
        "npm install --prefix #{prefix} --loglevel=error @vivliostyle/cli@latest",
        out: File::NULL, err: File::NULL
      )
      skip "@vivliostyle/cli@latest の取得に失敗しました（ネットワーク未接続の可能性）" unless installed

      latest_bin = File.join(prefix, "node_modules", ".bin")
      latest_version = `PATH=#{latest_bin}:$PATH vivliostyle --version 2>/dev/null`.strip

      with_path_prefix(latest_bin) do
        success, output = VsTestSupport::VsBuilder.build!(
          vs_command: VsTestSupport::VsBuilder.repo_vs_command
        )

        # CN-01: ビルド成功 + Type 3 なし
        assert success, <<~MSG
          @vivliostyle/cli #{latest_version} でビルドが失敗しました（上流の破壊的変更の可能性）:
          #{output.lines.last(20).join}
        MSG

        pdf = VsTestSupport::VsBuilder.find_latest_pdf
        refute_nil pdf
        type3 = VsTestSupport::PdfInspector.fonts(pdf).select(&:type3?)
        assert_empty type3,
                     "@vivliostyle/cli #{latest_version} で Type 3 フォントが再発しました: " \
                     "#{type3.map(&:name).uniq.join(', ')}"

        # CN-02: 警告差分の観測（失敗にはしない）
        flagged = output.lines.select { it.include?("🟡") || it.include?("🔴") }
        puts "\n[canary] @vivliostyle/cli #{latest_version} の警告差分（#{flagged.size} 件）:"
        flagged.each { puts "  #{it}" }
      end
    end
  end

  private

  # PATH の先頭へ一時的にディレクトリを足す（このプロセス内のみ・必ず復元）
  def with_path_prefix(dir)
    original = ENV.fetch("PATH")
    ENV["PATH"] = "#{dir}:#{original}"
    yield
  ensure
    ENV["PATH"] = original
  end
end
