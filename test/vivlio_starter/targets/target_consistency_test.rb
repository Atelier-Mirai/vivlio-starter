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
#   rake test:targets   （実マニュアルを最小セットの targets でビルドするため最も遅い。
#                          単体＋全部入りに絞って軽量化。通常 test からは除外）
#                          combo セット: 各フォーマット単体＋（epub+kindle）＋全部入り
#                          （pdf/print_pdf/epub の現状は 4 ビルド。kindle 実装後 6 ビルド）
#   ※ リポジトリルートで実行すること。ビルドのたびにルート直下の *.pdf / *.epub を
#     クリーンするため、既存の成果物は再生成される。
# =============================================================================

require "minitest/autorun"
require "fileutils"
require_relative "../support/build_helper"

class TargetConsistencyTest < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle qpdf gs unzip].freeze

  # 検証する targets の組み合わせ（最小セット）
  # --------------------------------------------------------------------------
  # 旧版は全部分集合（2^n−1）を実ビルドしていたが、本テストが捕まえたいのは
  # 「他ターゲットの同居による共有状態の汚染（例: print_pdf 本文欠落 ②）」であり、
  # それは "全部入り（最大干渉）" で顕在化する。よって
  #   各フォーマット単体（baseline）＋ epub↔kindle ペア（共有 HTML 汚染の直接検証）
  #   ＋ 全部入り（最大干渉）
  # に絞れば検出力を保ったまま大幅に軽量化できる（pdf/print_pdf/epub/kindle で
  # 2^4−1=15 → 6 ビルド）。docs/specs/epub-kindle-target-split-spec.md §5-2。
  #
  # kindle はターゲット実装後（pipeline に kindle_target? が入った時点）に自動で
  # 有効化される。未実装の間は kindle を除いた 3 フォーマット（4 ビルド）で回す。
  FORMATS = %w[pdf print_pdf epub kindle].freeze

  # repo ソースに kindle ターゲットが実装されているか（実ビルドを伴わない軽量判定）。
  def self.kindle_available?
    src = File.expand_path("../../../../lib/vivlio_starter/cli/build/pipeline.rb", __dir__)
    File.exist?(src) && File.read(src).include?("def kindle_target?")
  end

  def self.active_formats
    kindle_available? ? FORMATS : (FORMATS - %w[kindle])
  end

  # 単体 ＋ epub+kindle ペア（両方 active のとき）＋ 全部入り を生成する。
  def self.build_combos(formats)
    combos = formats.to_h { |fmt| [fmt, [fmt]] }
    combos["epub+kindle"] = %w[epub kindle] if (%w[epub kindle] - formats).empty?
    combos[formats.join("+")] = formats
    combos
  end

  COMBOS    = build_combos(active_formats).freeze
  FULL_KEY  = active_formats.join("+").freeze
  # クリーン EPUB を含む全 combo キー（クリーン回帰ガードの走査対象）。
  EPUB_COMBO_KEYS = COMBOS.select { |_key, targets| targets.include?("epub") }.keys.freeze
  # Kindle を含む全 combo キー（Kindle 劣化の走査対象・…-kindle.epub を検査）。
  KINDLE_COMBO_KEYS = COMBOS.select { |_key, targets| targets.include?("kindle") }.keys.freeze

  # build.yml が再生成する派生ファイル（ビルド後に元へ戻す）
  GENERATED_FILES = ["vivliostyle.config.js", File.join("stylesheets", "page-settings.css")].freeze

  PdfSnap  = Data.define(:page_count, :texts, :outline, :size, :body)
  # vs_kindle / vs_code_epub / math_px は Kindle 専用 rewrite の痕跡（§5-3）。
  # クリーン EPUB（:epub）では 0/false、Kindle EPUB（…-kindle.epub）では検出されるべき。
  EpubSnap = Data.define(:spine, :body, :size, :webp_files, :unresolved_images,
                         :legacy_code_gutters, :math_ex_units,
                         :vs_kindle, :vs_code_epub, :math_px)

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
  # ⑦（docs/specs/epub-backlink-dedup-isolation-spec.md）実装により、PDF を併せて
  # ビルドしても EPUB は Step 8（backlink dedup）前の章 HTML から生成される
  # （run_step_epub 冒頭で pre-dedup スナップショットを復元）。このためリフロー EPUB は
  # 「全 † / 全出現リンク」を保ち、epub 単体（dedup 非実行）と pdf+epub（PDF 側のみ dedup）
  # とで本文が完全一致する。† を除かずに比較してこの隔離を保証する（dedup が EPUB へ
  # 漏れると † 数差として即座に検知される）。
  def test_epub_consistent_across_single_and_combined
    base = fetch!("epub", :epub)
    combined_keys_including("epub").each do |key|
      other = fetch!(key, :epub)
      assert_equal base.spine, other.spine, "epub spine: 単体と「#{key}」で不一致"
      assert_equal base.body.count("†"), other.body.count("†"),
                   "epub の † 数: 単体と「#{key}」で不一致（⑦ dedup 隔離の回帰）"
      assert_equal base.body, other.body, "epub 本文: 単体と「#{key}」で不一致"
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
    snap = self.class.snapshots.fetch(FULL_KEY)
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
    snap = self.class.snapshots.fetch(FULL_KEY)
    assert_equal snap[:pdf].outline, snap[:print_pdf].outline,
                 "pdf と print_pdf のアウトラインが一致しません"
  end

  # 【クリーン EPUB の回帰ガード】<img> 参照がすべて EPUB 内の実体に解決する。
  # クリーン EPUB（Kobo/Apple Books）は WebP を高画質維持するため、WebP が残ること自体は正常
  # （EPUB 3.3 で image/webp はコアメディアタイプ）。WebP ゼロは Kindle 側で検査する（§4・§5-3）。
  def test_clean_epub_images_resolve
    EPUB_COMBO_KEYS.each do |key|
      snap = fetch!(key, :epub)
      assert_empty snap.unresolved_images,
                   "クリーン epub「#{key}」に解決できない <img src> があります: #{snap.unresolved_images.first(5).join(', ')}"
    end
  end

  # 【クリーン EPUB 非汚染ガード・§5-3】Kindle 専用 rewrite（vs-kindle マーカー・コードテーブル化・
  # 数式 px 属性）がクリーン EPUB には一切現れない（::before 角タブ・var()・SVG・WebP を維持）。
  def test_clean_epub_has_no_kindle_degradation
    EPUB_COMBO_KEYS.each do |key|
      snap = fetch!(key, :epub)
      refute snap.vs_kindle, "クリーン epub「#{key}」に vs-kindle マーカーが付いてはいけない"
      assert_equal 0, snap.vs_code_epub,
                   "クリーン epub「#{key}」にコードテーブル化（vs-code-epub）が現れてはいけない"
      assert_equal 0, snap.math_px,
                   "クリーン epub「#{key}」に数式 px 属性が現れてはいけない"
    end
  end

  # 【Kindle EPUB の回帰ガード・§5-2/§5-3】Kindle 中間 EPUB は WebP が 1 つも残らず（Kindle 非対応）、
  # <img> 参照が解決し、コードの絶対配置ガターが残らず（テーブル化済み）、数式 ex が残らない（em 化済み）。
  # さらに Kindle 専用 rewrite の痕跡（vs-kindle・コードテーブル・数式 px）が確かに現れる。
  def test_kindle_epub_is_degraded_for_amazon
    KINDLE_COMBO_KEYS.each do |key|
      snap = fetch!(key, :kindle)
      assert_empty snap.webp_files,
                   "kindle epub「#{key}」に WebP が残っています（Kindle 変換不能）: #{snap.webp_files.first(5).join(', ')}"
      assert_empty snap.unresolved_images,
                   "kindle epub「#{key}」に解決できない <img src> があります: #{snap.unresolved_images.first(5).join(', ')}"
      assert_equal 0, snap.legacy_code_gutters,
                   "kindle epub「#{key}」に Prism の絶対配置ガターが残っています（テーブル化されていない）"
      assert_equal 0, snap.math_ex_units,
                   "kindle epub「#{key}」の数式寸法に ex 単位が残っています（em へ変換されていない）"
      assert snap.vs_kindle, "kindle epub「#{key}」に vs-kindle マーカーが必要"
      assert_operator snap.vs_code_epub, :>, 0, "kindle epub「#{key}」にコードテーブル（vs-code-epub）が必要"
      assert_operator snap.math_px, :>, 0, "kindle epub「#{key}」に数式 px 属性が必要"
    end
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

    # 1 つの targets 構成でビルドし、生成された成果物のスナップショットを返す。
    # Kindle を含む構成は中間 EPUB（…-kindle.epub）を検査するため --no-clean で残す。
    def build_one!(targets)
      cleanup_artifacts!
      value = targets.join(", ")
      extra_args = targets.include?("kindle") ? "--no-clean" : ""
      captured = nil
      VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s*)targets:\s*[^\n]*$/, "\\1targets: #{value}") do
        ok, output = VsTestSupport::VsBuilder.build!(vs_command: VsTestSupport::VsBuilder.repo_vs_command,
                                                     extra_args: extra_args)
        raise "vs build（targets: #{value}）が失敗しました:\n#{output.lines.last(20).join}" unless ok

        captured = capture(targets)
      end
      captured
    end

    # targets に含まれるフォーマットだけ成果物を取得する。
    # epub=クリーン EPUB（…-kindle.epub を除く）、kindle=Kindle 中間 EPUB（…-kindle.epub）。
    def capture(targets)
      {
        pdf:       targets.include?("pdf")       ? pdf_snapshot(find_viewing_pdf) : nil,
        print_pdf: targets.include?("print_pdf") ? pdf_snapshot(find_print_pdf)   : nil,
        epub:      targets.include?("epub")      ? epub_snapshot(find_clean_epub)  : nil,
        kindle:    targets.include?("kindle")    ? epub_snapshot(find_kindle_epub) : nil
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

      raw = VsTestSupport::EpubInspector.raw_xhtml(path)
      EpubSnap.new(
        spine: VsTestSupport::EpubInspector.spine_documents(path),
        body: VsTestSupport::EpubInspector.body_text(path),
        size: File.size(path),
        webp_files: VsTestSupport::EpubInspector.webp_files(path),
        unresolved_images: VsTestSupport::EpubInspector.unresolved_image_refs(path),
        legacy_code_gutters: raw.scan("line-numbers-rows").size,
        math_ex_units: raw.scan(/vs-math[^>]*style="[^"]*\dex/).size,
        # Kindle 専用 rewrite の痕跡（§5-3）。
        # 文字列の素朴な include? だと、開発者ガイド（61-developer.md）が
        # vs-kindle / vs-code-epub という仕組みを解説する地の文・コード例に誤反応する。
        # クリーン EPUB はそれらの「実マーカー」（body の class・テーブルの class）を
        # 持たないことが要件なので、マーカーそのものを検出する。
        vs_kindle: raw.match?(/<body[^>]*\bvs-kindle\b/),
        vs_code_epub: raw.scan(/<table[^>]*\bvs-code-epub\b/).size,
        math_px: raw.scan(/vs-math[^>]*\s(?:width|height)="\d+"/).size
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

    # クリーン EPUB（Kindle 中間 …-kindle.epub を除く）
    def find_clean_epub
      Dir.glob("*.epub").reject { it.end_with?("-kindle.epub") }.max_by { File.mtime(it) }
    end

    # Kindle 中間 EPUB（--no-clean で残した …-kindle.epub）
    def find_kindle_epub
      Dir.glob("*-kindle.epub").max_by { File.mtime(it) }
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
      (Dir.glob("*.pdf") + Dir.glob("*.epub") + Dir.glob("*.kpf")).each { FileUtils.rm_f(it) }
    end
  end

  private

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
