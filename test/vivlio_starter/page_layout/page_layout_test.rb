# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/page_layout/page_layout_test.rb
#
# Vivlio Starter 判型（ページプリセット）自動検証テスト
#
# 【実行方法】
#   プロジェクトディレクトリ（mybook/）で：
#     rake test:layout
#
#   または直接：
#     ruby test/vivlio_starter/page_layout/page_layout_test.rb
#
# 【注意】
#   vs build を実際に呼び出すため、通常の rake test からは除外されています。
#   手動確認や CI の専用ジョブで実行してください。
#
# 【必要gem】
#   gem install pdf-reader
# =============================================================================

require "minitest/autorun"
require "fileutils"
require "yaml"

begin
  require "pdf/reader"
rescue LoadError
  abort <<~MSG
    pdf-reader gem が見つかりません。インストールしてください：
      gem install pdf-reader
  MSG
end

# =============================================================================
# 定数
# =============================================================================

# 期待する仕上がり寸法（単位: pt）
PAGE_SIZES_PT = {
  a4: { width: 595.28, height: 841.89 },
  a5: { width: 419.53, height: 595.28 },
  b5: { width: 515.91, height: 728.50 }  # JIS B5
}.freeze

# プリセット名 → 期待判型
PRESET_EXPECTATIONS = {
  "a5_standard" => :a5,
  "a5_airy"     => :a5,
  "a5_compact"  => :a5,
  "a5_custom"   => :a5,
  "b5_standard" => :b5,
  "b5_compact"  => :b5,
  "b5_airy"     => :b5,
  "b5_custom"   => :b5,
  "a4_standard" => :a4,
  "a4_airy"     => :a4,
  "a4_compact"  => :a4,
  "a4_custom"   => :a4
}.freeze

# テスト対象プリセット（必要に応じて追加・削減）
TARGET_PRESETS = %w[
  a5_standard
  a5_airy
  a5_compact
  b5_standard
  b5_compact
  a4_standard
  a4_airy
].freeze

# MediaBox / CropBox / TrimBox の許容誤差（pt）
# Vivliostyle の浮動小数点丸め誤差を吸収する
TOLERANCE_PT = 2.0

BOOK_YML_PATH = "config/book.yml"

# =============================================================================
# BookYmlPatcher — config/book.yml のプリセット行を安全に書き換える
# =============================================================================
module BookYmlPatcher
  # 指定プリセットだけ有効化し、残りをコメントアウト。
  # ブロックを渡すと実行後に元の内容へ自動復元する。
  def self.apply(preset_name, &)
    raise "#{BOOK_YML_PATH} が見つかりません" unless File.exist?(BOOK_YML_PATH)

    original = File.read(BOOK_YML_PATH)

    patched = original.lines.map do |line|
      next line unless line.match?(/^\s*#?\s*use:\s*[a-z0-9_]+/)

      if line.match?(/use:\s*#{Regexp.escape(preset_name)}(\s|$)/)
        # 先頭の「# 」を除去して有効化（インデント保持）
        line.sub(/^(\s*)#\s*/, '\1').rstrip + "\n"
      else
        # コメントアウト（既にコメントならそのまま）
        line.match?(/^\s*#/) ? line : line.sub(/^(\s*)/, '\1# ')
      end
    end.join

    File.write(BOOK_YML_PATH, patched)

    if block_given?
      yield
    end
  ensure
    File.write(BOOK_YML_PATH, original) if block_given? && original
  end
end

# =============================================================================
# VsBuilder — vs build の実行と PDF 探索
# =============================================================================
module VsBuilder
  OUTPUT_DIRS = %w[dist output _dist _output].freeze

  def self.build!
    output = `vs build 2>&1`
    [$?.success?, output]
  end

  # 直近に更新されたPDFを返す
  def self.find_latest_pdf
    candidates = OUTPUT_DIRS
      .filter_map { |dir| Dir.glob("#{dir}/**/*.pdf") if Dir.exist?(dir) }
      .flatten
    candidates += Dir.glob("*.pdf")
    candidates.max_by { |f| File.mtime(f) }
  end
end

# =============================================================================
# PdfBoxVerifier — PDF の各ページボックスを期待値と照合する
# =============================================================================
module PdfBoxVerifier
  # 検証結果を表す値オブジェクト
  Result = Data.define(:page, :box_name, :ok, :actual_w, :actual_h,
                       :orientation, :expected_w, :expected_h)

  def self.verify_all_pages(pdf_path, expected_key)
    expected = PAGE_SIZES_PT.fetch(expected_key) do
      raise ArgumentError, "未知の判型キー: #{expected_key}"
    end

    reader = PDF::Reader.new(pdf_path)
    reader.pages.flat_map.with_index(1) do |page, page_num|
      check_page(page, page_num, expected)
    end
  end

  def self.check_page(page, page_num, expected)
    boxes = extract_boxes(page.attributes)
    boxes.filter_map do |box_name, coords|
      next unless coords

      check_box(coords, expected, page_num, box_name)
    end
  end
  private_class_method :check_page

  def self.extract_boxes(attrs)
    {
      media_box: attrs[:MediaBox],
      crop_box:  attrs[:CropBox],
      trim_box:  attrs[:TrimBox]
    }
  end
  private_class_method :extract_boxes

  # box: [x0, y0, x1, y1]
  def self.check_box(box, expected, page_num, box_name)
    w = (box[2] - box[0]).abs
    h = (box[3] - box[1]).abs

    portrait  = near?(w, expected[:width])  && near?(h, expected[:height])
    landscape = near?(w, expected[:height]) && near?(h, expected[:width])

    ok          = portrait || landscape
    orientation = landscape ? "landscape" : "portrait"

    Result.new(
      page:       page_num,
      box_name:   box_name,
      ok:         ok,
      actual_w:   w.round(2),
      actual_h:   h.round(2),
      orientation: orientation,
      expected_w: expected[:width],
      expected_h: expected[:height]
    )
  end
  private_class_method :check_box

  def self.near?(actual, expected)
    (actual - expected).abs <= TOLERANCE_PT
  end
  private_class_method :near?
end

# =============================================================================
# テスト本体
# =============================================================================
class PageLayoutTest < Minitest::Test
  # mybook/ ディレクトリで実行されているかチェック
  def setup
    skip "config/book.yml が見つかりません（mybook/ で実行してください）" \
      unless File.exist?(BOOK_YML_PATH)
  end

  # TARGET_PRESETS の各プリセットに対してテストメソッドを動的生成
  TARGET_PRESETS.each do |preset|
    define_method(:"test_preset_#{preset}") do
      expected_key = PRESET_EXPECTATIONS[preset]
      skip "#{preset} の期待値が未定義です" unless expected_key

      pdf_path = nil

      BookYmlPatcher.apply(preset) do
        success, build_log = VsBuilder.build!
        assert success, "vs build が失敗しました（preset: #{preset}）\n#{build_log.lines.last(10).join}"

        pdf_path = VsBuilder.find_latest_pdf
        assert pdf_path, "PDFが生成されませんでした（preset: #{preset}）"
      end

      results = PdfBoxVerifier.verify_all_pages(pdf_path, expected_key)
      failures = results.reject(&:ok)

      assert failures.empty?, build_failure_message(preset, expected_key, failures)
    end
  end

  private

  def build_failure_message(preset, expected_key, failures)
    exp = PAGE_SIZES_PT[expected_key]
    lines = failures.map do |r|
      "  p.#{r.page} #{r.box_name}: #{r.actual_w} x #{r.actual_h} pt " \
        "（期待: #{exp[:width]} x #{exp[:height]} pt）"
    end
    "判型ミスマッチ（preset: #{preset}）\n#{lines.join("\n")}"
  end
end
