# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/targets/target_consistency_test.rb
#
# ターゲット整合性テスト（TG）— 実ビルドを伴う回帰テスト
#
# 【背景】
#   output.targets を `pdf, print_pdf, epub` にしてビルドすると、入稿用 PDF
#   （print_pdf）の本文が欠落し titlepage/legalpage/colophon の 4 ページのみに
#   なる重大不具合があった（docs/specs/build-output-bugfix-spec.md ②）。
#   単体ターゲットでは正常だが複合ターゲットで壊れる種の回帰を、成果物どうしの
#   突き合わせで検知する。
#
# 【検証内容】
#   - 単体ターゲット（pdf / print_pdf / epub）がそれぞれ十分な本文を持つ
#   - 同一フォーマットの成果物が「単体ターゲット」と「複合ターゲット」で一致する
#     （pdf・print_pdf はページ数/本文/アウトライン/サイズ、epub は spine/本文）
#       ← これが ② を直接検知する
#   - フォーマット横断で本文量がほぼ揃う（print_pdf が 4 ページなら激減して失敗）
#   - print_pdf のページ数が pdf に近い
#   - epub の spine に前書き・後書き・奥付などの構成ページが含まれる（③-b 等）
#   - pdf と print_pdf のアウトライン（しおり）が一致する
#
# 【実行方法】
#   rake test:targets   （実マニュアルを 7 通りの targets でビルドするため最も遅い。
#                          20〜30 分程度。通常 test からは除外）
#   ※ リポジトリルートで実行すること。ビルドのたびにルート直下の *.pdf / *.epub を
#     クリーンするため、既存の成果物は再生成される。
# =============================================================================

require "minitest/autorun"
require "fileutils"
require_relative "../support/build_helper"

class TargetConsistencyTest < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle qpdf gs unzip].freeze

  # 検証する targets の組み合わせ（単体 3 + 複合 4）
  COMBOS = {
    "pdf"                => %w[pdf],
    "print_pdf"          => %w[print_pdf],
    "epub"               => %w[epub],
    "pdf+print_pdf"      => %w[pdf print_pdf],
    "pdf+epub"           => %w[pdf epub],
    "print_pdf+epub"     => %w[print_pdf epub],
    "pdf+print_pdf+epub" => %w[pdf print_pdf epub]
  }.freeze

  # build.yml が再生成する派生ファイル（ビルド後に元へ戻す）
  GENERATED_FILES = ["vivliostyle.config.js", File.join("stylesheets", "page-settings.css")].freeze

  PdfSnap  = Data.define(:page_count, :texts, :outline, :size, :body)
  EpubSnap = Data.define(:spine, :body, :size)

  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")

    missing = REQUIRED_TOOLS.reject { system("which #{it} >/dev/null 2>&1") }
    skip "ビルドに必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?
  end

  # === テスト本体（ビルドは self.class.snapshots で 1 回だけ実行される） ===

  # 単体ターゲットの各成果物が空・極小でない（catalog の章数に依存しない緩い下限）。
  # 「print_pdf 本文欠落で 4 ページ」のような degenerate は test_print_pdf_page_count_is_close_to_pdf
  # （pdf との相対比較）で確実に捕捉するため、ここは本→章数に依らない最小限の生存確認に留める。
  def test_single_targets_produce_substantial_body
    %w[pdf print_pdf].each do |fmt|
      snap = fetch!(fmt, fmt.to_sym)
      assert_operator snap.page_count, :>, 5,
                      "#{fmt} 単体のページ数が少なすぎます（#{snap.page_count} ページ）"
    end
    epub = fetch!("epub", :epub)
    assert_operator epub.body.length, :>, 10_000,
                    "epub 単体の本文が少なすぎます（#{epub.body.length} 文字）"
  end

  # 【②の中核】print_pdf が単体ターゲットと複合ターゲットで一致する
  def test_print_pdf_consistent_across_single_and_combined
    base = fetch!("print_pdf", :print_pdf)
    combined_keys_including("print_pdf").each do |key|
      assert_pdf_equal base, fetch!(key, :print_pdf), "print_pdf: 単体と「#{key}」で不一致"
    end
  end

  # pdf（閲覧用）が単体ターゲットと複合ターゲットで一致する
  def test_pdf_consistent_across_single_and_combined
    base = fetch!("pdf", :pdf)
    combined_keys_including("pdf").each do |key|
      assert_pdf_equal base, fetch!(key, :pdf), "pdf: 単体と「#{key}」で不一致"
    end
  end

  # epub が単体ターゲットと複合ターゲットで一致する（spine 構成・本文の実体）
  #
  # NOTE: 用語集オートリンクの脚注記号「†」は、PDF を併せてビルドすると Step 8
  #   （backlink dedup）が「同一 PDF ページ内の 2 回目以降の † を削除」するため、
  #   `epub` 単体（dedup なし＝† 全残）と `pdf+epub`（PDF のページ依存 dedup が共有
  #   HTML に反映＝† 一部削除）とで † の数が変わる。リフロー EPUB にページ概念は無く
  #   本来この差は生じるべきでない既知の不整合（docs/specs/build-output-bugfix-spec.md
  #   ⑦ / CHANGELOG「既知の不具合」参照）。本テストでは実体テキストの同一性を担保する
  #   ため † を除いて比較し、† dedup 差そのものは別途追跡する。
  def test_epub_consistent_across_single_and_combined
    base = fetch!("epub", :epub)
    combined_keys_including("epub").each do |key|
      other = fetch!(key, :epub)
      assert_equal base.spine, other.spine, "epub spine: 単体と「#{key}」で不一致"
      assert_equal strip_daggers(base.body), strip_daggers(other.body),
                   "epub 本文（†除く）: 単体と「#{key}」で不一致"
    end
  end

  # フォーマット横断で本文量がほぼ揃う（print_pdf 本文欠落をフォーマット間でも検知）
  def test_cross_format_body_volume_is_comparable
    pdf  = fetch!("pdf", :pdf).body.length
    ppdf = fetch!("print_pdf", :print_pdf).body.length
    epub = fetch!("epub", :epub).body.length

    assert_operator ppdf.to_f / pdf, :>=, 0.8,
                    "print_pdf の本文量が pdf の 80% 未満です（#{ppdf} / #{pdf}）"
    # epub は目次・前付がない一方リフローのため、pdf の 60% 以上あれば妥当とみなす
    assert_operator epub.to_f / pdf, :>=, 0.6,
                    "epub の本文量が pdf の 60% 未満です（#{epub} / #{pdf}）"
  end

  # print_pdf のページ数が pdf に近い（② では 4 ページ vs 数百ページで大きく乖離した）
  def test_print_pdf_page_count_is_close_to_pdf
    snap = self.class.snapshots.fetch("pdf+print_pdf+epub")
    pdf = snap[:pdf]
    ppdf = snap[:print_pdf]
    refute_nil pdf
    refute_nil ppdf

    tolerance = [(pdf.page_count * 0.1).ceil, 10].max
    diff = (ppdf.page_count - pdf.page_count).abs
    assert_operator diff, :<=, tolerance,
                    "print_pdf(#{ppdf.page_count}p) と pdf(#{pdf.page_count}p) のページ数乖離が大きすぎます"
  end

  # epub の spine に主要な構成ページが含まれる（③-b 奥付など）
  def test_epub_spine_includes_structural_pages
    spine = fetch!("epub", :epub).spine
    %w[00-preface _colophon 99-postface _glossarypage _indexpage].each do |doc|
      assert_includes spine, doc, "epub の spine に #{doc} が含まれていません"
    end
  end

  # pdf と print_pdf のアウトライン（しおり）が一致する
  def test_pdf_and_print_pdf_share_outline
    snap = self.class.snapshots.fetch("pdf+print_pdf+epub")
    assert_equal snap[:pdf].outline, snap[:print_pdf].outline,
                 "pdf と print_pdf のアウトラインが一致しません"
  end

  # epub の本文に代表的なマーカーが含まれる（実本文が EPUB へ届いているかの煙検査）
  def test_epub_contains_body_markers
    body = fetch!("epub", :epub).body
    %w[光電効果 ワークフロー プランク定数].each do |marker|
      assert_includes body, marker, "epub の本文にマーカー「#{marker}」が見つかりません"
    end
  end

  # === ビルド実行と成果物キャプチャ（クラスレベルで 1 回だけ） ===

  class << self
    def snapshots
      @snapshots ||= run_all_builds!
    end

    private

    def run_all_builds!
      generated = snapshot_generated
      COMBOS.transform_values { |targets| build_one!(targets) }
    ensure
      restore_generated(generated)
      cleanup_artifacts!
    end

    # 1 つの targets 構成でビルドし、生成された成果物のスナップショットを返す
    def build_one!(targets)
      cleanup_artifacts!
      value = targets.join(", ")
      captured = nil
      VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s*)targets:\s*[^\n]*$/, "\\1targets: #{value}") do
        ok, output = VsTestSupport::VsBuilder.build!(vs_command: VsTestSupport::VsBuilder.repo_vs_command)
        raise "vs build（targets: #{value}）が失敗しました:\n#{output.lines.last(20).join}" unless ok

        captured = capture(targets)
      end
      captured
    end

    # targets に含まれるフォーマットだけ成果物を取得する
    def capture(targets)
      {
        pdf:       targets.include?("pdf")       ? pdf_snapshot(find_viewing_pdf) : nil,
        print_pdf: targets.include?("print_pdf") ? pdf_snapshot(find_print_pdf)   : nil,
        epub:      targets.include?("epub")      ? epub_snapshot(find_epub)       : nil
      }
    end

    def pdf_snapshot(path)
      return nil unless path

      texts = VsTestSupport::PdfInspector.page_texts(path)
      PdfSnap.new(
        page_count: texts.size,
        texts: texts,
        outline: VsTestSupport::PdfInspector.outline_titles(path),
        size: File.size(path),
        body: normalize(texts.join)
      )
    end

    def epub_snapshot(path)
      return nil unless path

      EpubSnap.new(
        spine: VsTestSupport::EpubInspector.spine_documents(path),
        body: VsTestSupport::EpubInspector.body_text(path),
        size: File.size(path)
      )
    end

    # 閲覧用 PDF（*_print* を除く）
    def find_viewing_pdf
      Dir.glob("*.pdf").reject { it.include?("_print") }.max_by { File.mtime(it) }
    end

    # 入稿用 PDF
    def find_print_pdf
      Dir.glob("*_print*.pdf").max_by { File.mtime(it) }
    end

    def find_epub
      Dir.glob("*.epub").max_by { File.mtime(it) }
    end

    def normalize(text)
      text.gsub(/\s+/, "")
    end

    def snapshot_generated
      GENERATED_FILES.to_h { |path| [path, (File.read(path) if File.exist?(path))] }
    end

    def restore_generated(snapshot)
      snapshot.each do |path, content|
        if content
          File.write(path, content)
        elsif File.exist?(path)
          File.delete(path)
        end
      end
    end

    def cleanup_artifacts!
      (Dir.glob("*.pdf") + Dir.glob("*.epub")).each { FileUtils.rm_f(it) }
    end
  end

  private

  # 用語集オートリンクの脚注記号（†/‡）を除去する。
  # PDF のページ依存 dedup による † 差を吸収し、本文の実体テキストで比較するため。
  def strip_daggers(body)
    body.delete("†‡")
  end

  # 複合ターゲット（単体を除く）のうち、指定フォーマットを含むキー
  def combined_keys_including(target)
    COMBOS.select { |_key, targets| targets.include?(target) && targets.size > 1 }.keys
  end

  # 指定の組み合わせ・フォーマットの成果物スナップショットを取得（無ければ即失敗）
  def fetch!(combo_key, format)
    snap = self.class.snapshots.fetch(combo_key)[format]
    refute_nil snap, "「#{combo_key}」ビルドで #{format} 成果物が生成されませんでした"
    snap
  end

  # pdf / print_pdf の意味的同一性（idempotency_test と同じ観点）
  def assert_pdf_equal(expected, actual, message)
    assert_equal expected.page_count, actual.page_count,
                 "#{message}（ページ数: #{expected.page_count} vs #{actual.page_count}）"
    assert_equal expected.outline, actual.outline, "#{message}（アウトライン構造）"

    diff_pages = expected.texts.each_index.reject { |i| expected.texts[i] == actual.texts[i] }
    assert_empty diff_pages,
                 "#{message}（本文相違ページ: #{diff_pages.map { it + 1 }.first(10).join(', ')}）"

    drift = (actual.size - expected.size).abs.to_f / expected.size
    assert_operator drift, :<=, 0.02, "#{message}（サイズ乖離 #{(drift * 100).round(2)}% > 2%）"
  end
end
