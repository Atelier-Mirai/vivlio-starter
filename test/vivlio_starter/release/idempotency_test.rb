# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/idempotency_test.rb
#
# 冪等性テスト（ID）— docs/specs/test-suite-expansion-spec.md §12
#
# 【検証内容】
#   ID-01: vs build を 2 回連続実行しても 2 回目が成功し、意味的同一性が保たれる
#   ID-02: 設定復元（doctor --fix の config 部）の 2 回目は変更ゼロ（DR-03 の全体版）
#   ID-03: build → clean → build でも成果物が同等
#
# 【「意味的同一性」の定義（spec §12.3）】
#   PDF は CreationDate / ID 等を含むためバイト比較はできない。
#   ページ数・各ページ抽出テキスト・アウトライン構造・サイズ近似（±1%）で比較する。
#
# 【実行方法】
#   rake test:manual   （ビルドを 3 回実行するため最も遅いテスト。10 分弱）
# =============================================================================

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "digest"
require_relative "../support/build_helper"

class IdempotencyTest < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle qpdf gs].freeze

  # PDF スナップショット（意味的同一性の比較単位）
  Snapshot = Data.define(:page_count, :texts, :outline, :size)

  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")

    missing = REQUIRED_TOOLS.reject { system("which #{it} >/dev/null 2>&1") }
    skip "ビルドに必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?
  end

  # ID-01 + ID-03: build ×2 → clean → build の 3 成果物がすべて意味的に一致する
  # （ビルドが極めて高コストのため、1 メソッドに連続シナリオとして集約する）
  def test_should_produce_semantically_identical_pdfs_across_rebuilds
    first = build_and_snapshot!("1回目のビルド")
    second = build_and_snapshot!("2回目のビルド（連続実行）")
    assert_semantic_equal first, second, "連続 2 回目のビルド結果が 1 回目と異なります"

    run_vs!("clean")
    third = build_and_snapshot!("clean 後のビルド")
    assert_semantic_equal first, third, "clean 後のビルド結果が初回と異なります"
  end

  # ID-02: 完全なプロジェクトに対する設定復元の 2 回目は何も変更しない
  def test_should_not_change_anything_on_second_config_restore
    require "vivlio_starter/cli"
    require "vivlio_starter/cli/doctor"

    Dir.mktmpdir("vs-idem") do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("config")
        File.write("config/book.yml", "book:\n  main_title: 'idem'\n")
        File.write("config/catalog.yml", "PREFACE:\nCHAPTERS:\nAPPENDICES:\nPOSTFACE:\n")
        File.write("config/page_presets.yml", "presets: {}\n")

        # 1 回目: 欠落分（textlint 系・辞書ディレクトリ）が復元される
        capture_io { VivlioStarter::CLI::DoctorCommands.diagnose_config_files!(fix: true, yes: true) }
        state_after_first = config_state

        # 2 回目: 変更ゼロであるべき
        capture_io { VivlioStarter::CLI::DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

        assert_equal state_after_first, config_state, "2 回目の復元で config/ が変化しました"
        assert_empty Dir.glob("config/**/*.bak.*"), "2 回目の復元でバックアップが作られました"
      end
    end
  end

  private

  def run_vs!(args)
    output = `#{VsTestSupport::VsBuilder.repo_vs_command} #{args} 2>&1`
    assert_predicate $?, :success?, "vs #{args} が失敗しました:\n#{output.lines.last(15).join}"
    output
  end

  def build_and_snapshot!(label)
    run_vs!("build")
    pdf = VsTestSupport::VsBuilder.find_latest_pdf
    refute_nil pdf, "#{label}: PDF が見つかりません"

    Snapshot.new(
      page_count: VsTestSupport::PdfInspector.page_texts(pdf).size,
      texts: VsTestSupport::PdfInspector.page_texts(pdf),
      outline: VsTestSupport::PdfInspector.outline_titles(pdf),
      size: File.size(pdf)
    )
  end

  def assert_semantic_equal(expected, actual, message)
    assert_equal expected.page_count, actual.page_count, "#{message}（ページ数）"
    assert_equal expected.outline, actual.outline, "#{message}（アウトライン構造）"

    text_diffs = expected.texts.zip(actual.texts).each_with_index
                         .select { |(a, b), _i| a != b }
                         .map { |_pair, i| "p.#{i + 1}" }
    assert_empty text_diffs, "#{message}（本文テキスト相違ページ: #{text_diffs.join(', ')}）"

    size_drift = (actual.size - expected.size).abs.to_f / expected.size
    assert_operator size_drift, :<=, 0.01,
                    "#{message}（ファイルサイズ乖離 #{(size_drift * 100).round(2)}% > 1%）"
  end

  # config/ 配下の全ファイルパスと内容ハッシュのスナップショット
  def config_state
    Dir.glob("config/**/*", File::FNM_DOTMATCH)
       .select { File.file?(it) }
       .sort
       .to_h { [it, Digest::SHA256.file(it).hexdigest] }
  end
end
