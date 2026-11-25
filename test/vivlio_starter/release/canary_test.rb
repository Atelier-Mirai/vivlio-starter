# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/canary_test.rb
#
# 依存カナリアテスト（CN）— test-suite-expansion-spec.md §14
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
#   - 組むのはリポジトリの本の写し（node_modules を除く）。vs は npx vivliostyle で組み、
#     npx はプロジェクトの node_modules を PATH より先に使うので、リポジトリの中で組むと
#     最新版ではなく package.json の版で組んでしまう（改善案 #166）
#   - 上流の破壊はこちらの欠陥ではないため、rake test:release には含めない
# =============================================================================

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../support/build_helper"

class CanaryTest < Minitest::Test
  # 本を組むのに要らないもの。node_modules を除くのが要（npx に PATH の最新版を使わせる）。
  # 残りは gem のソース・開発文書・生成物で、写す時間を縮めるために除く
  NOT_FOR_BOOK = %w[node_modules .git lib test docs output tmp sources].freeze
  BUILD_PRODUCT = /\.(pdf|epub|kpf|gem|jpg)\z/

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

      with_book_copy do
        with_path_prefix(latest_bin) { build_and_inspect(latest_version) }
      end
    end
  end

  private

  def build_and_inspect(latest_version)
    # 組む前に、npx が入れたての最新版を使うことを確かめる。違えば、カナリアが
    # 別の版で組むことになり、上流の破壊を見逃す
    used_version = `npx vivliostyle --version 2>/dev/null`.strip
    assert_equal latest_version, used_version, "カナリアが最新版で組んでいません（npx が別の版を使います）"

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
    puts "\n[canary] @vivliostyle/cli #{latest_version.tr("\n", ' ')} の警告差分（#{flagged.size} 件）:"
    flagged.each { puts "  #{it}" }
  end

  # リポジトリの本を node_modules を除いて一時フォルダへ写し、その中で実行する。
  # 写しの上の探索で別の node_modules に当たらないよう、一時フォルダ（/var/folders 配下）に置く
  def with_book_copy
    Dir.mktmpdir("vs-canary-book") do |book|
      Dir.children(Dir.pwd)
         .reject { NOT_FOR_BOOK.include?(it) || it.match?(BUILD_PRODUCT) }
         .each { FileUtils.cp_r(it, book, preserve: true) }
      Dir.chdir(book) { yield }
    end
  end

  # PATH の先頭へ一時的にディレクトリを足す（このプロセス内のみ・必ず復元）
  def with_path_prefix(dir)
    original = ENV.fetch("PATH")
    ENV["PATH"] = "#{dir}:#{original}"
    yield
  ensure
    ENV["PATH"] = original
  end
end
