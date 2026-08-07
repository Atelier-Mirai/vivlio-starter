# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/type3/techbook_type3_test.rb
#
# Techbook モードの Type 3 フォント検証（T3）— 実ビルドを伴う回帰テスト
#
# 【背景】
#   `output.pdf.techbook` は既定 false だが、**false 側は実ビルドを一度も
#   通っていなかった**（2026-08-07 調査）。単体テストは
#   `cli/techbook/processor_test.rb` に 4 件あるものの、いずれも Processor が
#   何もしないことの確認で、パイプライン全体を通した検証ではない。
#   実ビルド系テスト（test:layout / test:targets）はプロジェクトの book.yml を
#   そのまま読むため、そこが true である限り false は永久に未検証だった。
#
#   Type 3 フォントは技術書典等の入稿で不可。Chromium は同梱フォントに無い文字を
#   OS フォントへフォールバックしたり faux-bold を合成すると Type 3 で埋め込む。
#   techbook モードはこれを潰しにいく機能なので、「潰せているか」を数で押さえる。
#   背景の全容は `test/vivlio_starter/fixtures/type3/README.md`。
#
# 【検証内容】
#   - techbook: false でも全章ビルドが成功し、十分な本文を持つ PDF ができる
#   - techbook: true でも全章ビルドが成功する
#   - techbook: true の Type 3 が false より**厳密に少ない**（モードが効いている証明）
#   - techbook: true の Type 3 が既知の水準を超えない（悪化の検知・ラチェット）
#
# 【実行方法】
#   rake test:type3   （全章ビルドを 2 回回すため 10 分以上かかる。通常 test からは除外）
#   ※ リポジトリルートで実行すること。ルート直下の *.pdf を再生成する。
#
# 【経緯】
#   2026-08-07 時点では techbook: true でも 32 件残っていた。原因は showcase / mermaid の
#   生成 SVG——`<img>` 参照の独立文書なので本文の @font-face が届かず、OS の既定和文
#   フォント（Hiragino）へ落ちて Type 3 化していた。SVG 自身にサブセットフォントを
#   持たせて解消し、**0 件**になった（`type3-font-embedding-notes.md`）。
# =============================================================================

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../support/build_helper'

class TechbookType3Test < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle].freeze

  # 本文が十分にあることの下限。前付・奥付だけの PDF（数ページ）を弾く。
  MIN_PAGES = 100

  # techbook: true で許容する Type 3 の件数。**0 が正**（2026-08-07 に達成）。
  # 増えたら入稿できない PDF を作っているということなので、緩めずに原因を潰すこと。
  TRUE_TYPE3_CEILING = 0

  class << self
    # 2 回のビルドはテストメソッドごとに繰り返さず、初回アクセス時に 1 度だけ行う。
    def results = @results ||= build_both!

    private

    def build_both!
      dir = Dir.mktmpdir('vs-type3')
      { false => nil, true => nil }.to_h do |techbook, _|
        [techbook, measure(techbook, dir)]
      end
    end

    # techbook を指定して全章ビルドし、成果物の指標を返す。
    # targets も pdf 単体に固定する（EPUB/Kindle を巻き込むと時間が倍増し、
    # Type 3 の観測には寄与しないため）。
    def measure(techbook, dir)
      VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s*)targets:\s*[^\n]*$/, '\1targets: pdf') do
        VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s*)techbook:\s*[^\n]*$/, "\\1techbook: #{techbook}") do
          ok, output = VsTestSupport::VsBuilder.build!(vs_command: VsTestSupport::VsBuilder.repo_vs_command)
          raise "vs build（techbook: #{techbook}）が失敗しました:\n#{output.lines.last(20).join}" unless ok

          snapshot(techbook, dir)
        end
      end
    end

    def snapshot(techbook, dir)
      src = VsTestSupport::VsBuilder.find_latest_pdf
      raise "ビルド後に PDF が見つかりません（techbook: #{techbook}）" unless src

      path = File.join(dir, "techbook_#{techbook}.pdf")
      FileUtils.cp(src, path)

      type3 = VsTestSupport::PdfInspector.fonts(path).select(&:type3?)
      { path:, pages: PDF::Reader.new(path).page_count,
        type3_count: type3.size, type3_pages: type3.map(&:page).uniq.size }
    end
  end

  def setup
    skip 'config/book.yml が見つかりません（リポジトリルートで実行してください）' unless File.exist?('config/book.yml')

    missing = REQUIRED_TOOLS.reject { |t| system("which #{t} > /dev/null 2>&1") }
    skip "必要なツールがありません: #{missing.join(', ')}" unless missing.empty?
  end

  # techbook: false でもビルドが成立し、本文のある PDF ができること（未検証だった経路）
  def test_should_build_successfully_with_techbook_disabled
    result = self.class.results[false]

    assert_operator result[:pages], :>=, MIN_PAGES,
                    "techbook: false のビルドが #{result[:pages]} ページしかありません（本文欠落の疑い）"
  end

  # techbook: true でもビルドが成立すること
  def test_should_build_successfully_with_techbook_enabled
    result = self.class.results[true]

    assert_operator result[:pages], :>=, MIN_PAGES,
                    "techbook: true のビルドが #{result[:pages]} ページしかありません（本文欠落の疑い）"
  end

  # 比較の前提: false 側には Type 3 が実際に出ていること。
  # ここが 0 になったら「true が効いている」の検証が空振りしているので気づけるようにする。
  def test_should_emit_type3_fonts_without_techbook
    result = self.class.results[false]

    assert_operator result[:type3_count], :>, 0,
                    'techbook: false で Type 3 が 0 件です。比較テストが無意味になっているので前提を見直してください'
  end

  # モードが効いていること: true の Type 3 が false より厳密に少ない
  def test_should_reduce_type3_fonts_with_techbook
    off = self.class.results[false]
    on  = self.class.results[true]

    assert_operator on[:type3_count], :<, off[:type3_count],
                    "techbook: true が Type 3 を減らせていません " \
                    "(true: #{on[:type3_count]} 件 / false: #{off[:type3_count]} 件)"
  end

  # 悪化の検知: true の Type 3 が既知の水準を超えない
  def test_should_not_regress_type3_count_with_techbook
    on = self.class.results[true]

    assert_operator on[:type3_count], :<=, TRUE_TYPE3_CEILING,
                    "techbook: true の Type 3 が #{on[:type3_count]} 件に増えました" \
                    "（既知の水準 #{TRUE_TYPE3_CEILING} 件・#{on[:type3_pages]} ページに出現）。" \
                    '入稿用 PDF の品質が落ちているので原因を特定してください'
  end
end
