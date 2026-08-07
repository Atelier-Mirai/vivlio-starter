# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/type3/google_fonts_type3_test.rb
#
# 同梱書体以外（Google Fonts）を指定したときの Type 3 検証 — 実ビルドを伴う回帰テスト
#
# 【背景】
#   Type 3 対策は同梱書体（Zen 3 種）を前提に組み上げた。だが `typography` は
#   任意の書体名を受け付け、同梱以外なら Google Fonts から取得する。**取得経路は
#   置き場もファイル名も同梱と違う**ため、対策が素通りしうる。
#
#   実際 2026-08-08 に、`SvgFontEmbedder#heading_font_path` が `fonts/<slug>/` しか
#   見ておらず、Google Fonts の置き場 `fonts/google/<slug>/` を素通りしていた。
#   サブセットを埋め込めない生成 SVG は OS の和文フォント（Hiragino）へ落ち、
#   Type 3 が再発する。1 章だけのビルドで 5 件を再現・修正した。
#   このテストはその再発を全章ビルドで見張る。
#
# 【2 書体を選ぶ理由】
#   Google Fonts の日本語 55 書体のうち**太字を持つのは 24・持たないのが 31**
#   （`type3-font-embedding-notes.md` §6.3）。この 2 群は通る道が違う。
#
#   - 太字あり → 実 Bold を埋め込む。Klee One は 400/600 で **太字が 700 ではない**
#     実例なので、`700` 決め打ちへの逆戻りも同時に検知できる
#   - 太字なし → 疑似太字（faux-bold）を合成させてはならない。
#     `font-synthesis-weight: none` で合成を止め、強調は見出し書体で代用する。
#     この代用が壊れると Type 3 が戻る
#
# 【検証内容】
#   - どちらの書体でも全章ビルドが成功し、十分な本文を持つ PDF ができる
#   - どちらの書体でも Type 3 が 0 件（同梱書体と同じ水準）
#
# 【実行方法】
#   rake test:type3   （techbook_type3_test.rb と合わせて全章ビルド 4 回・20 分以上）
#   ※ リポジトリルートで実行すること。ルート直下の *.pdf を再生成する。
#   ※ 初回は書体を Google Fonts から取得するのでネットワークが要る。
#      取得物と google-fonts.css はテスト終了時に元へ戻す。
# =============================================================================

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../support/build_helper'

class GoogleFontsType3Test < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle].freeze

  # 本文が十分にあることの下限。前付・奥付だけの PDF（数ページ）を弾く。
  MIN_PAGES = 100

  # 同梱書体と同じ水準を要求する。**0 が正**——緩めると入稿できない PDF を作る。
  TYPE3_CEILING = 0

  # 太字を持つ書体（400/600）。太字が 700 でない実例を兼ねる。
  BOLD_FONT = 'Klee One'
  # 標準の太さしか配信されない書体（400 のみ）。強調はゴシック代用へ切り替わる。
  REGULAR_ONLY_FONT = 'Yusei Magic'

  # Google Fonts の取得先。ビルドが書き換える／新規に作るものを元へ戻すために見張る。
  GOOGLE_FONTS_DIR = File.join('stylesheets', 'fonts', 'google')
  GOOGLE_FONTS_CSS = File.join('stylesheets', 'fonts', 'google-fonts.css')

  class << self
    # ビルドはテストメソッドごとに繰り返さず、初回アクセス時に書体ごと 1 度だけ行う。
    def results = @results ||= build_all!

    private

    def build_all!
      dir = Dir.mktmpdir('vs-type3-google')
      [BOLD_FONT, REGULAR_ONLY_FONT].to_h { [it, measure(it, dir)] }
    end

    # 本文・見出しの両方をその書体にして全章ビルドする。
    # 見出しも変えるのは、生成 SVG（showcase / mermaid）のラベルが見出し書体で
    # 組まれるため——ここを同梱書体のままにすると肝心の経路を通らない。
    #
    # targets は pdf 単体、techbook は true に固定する。前者は EPUB/Kindle を
    # 巻き込むと時間が倍増して Type 3 の観測に寄与しないため、後者は入稿用の
    # 設定そのものを検証対象にするため（book.yml の現在値に依存させない）。
    def measure(font, dir)
      restore_google_fonts do
        VsTestSupport::BookYmlPatcher.rewrite_lines(
          [[/^(\s*)targets:\s*[^\n]*$/, '\1targets: pdf'],
           [/^(\s*)techbook:\s*[^\n]*$/, '\1techbook: true'],
           [/^(  body:\n    font: )[^\n]*/, "\\1#{font}"],
           [/^(  heading:\n    font: )[^\n]*/, "\\1#{font}"]]
        ) do
          ok, output = VsTestSupport::VsBuilder.build!(vs_command: VsTestSupport::VsBuilder.repo_vs_command)
          raise "vs build（#{font}）が失敗しました:\n#{output.lines.last(20).join}" unless ok

          snapshot(font, dir)
        end
      end
    end

    def snapshot(font, dir)
      src = VsTestSupport::VsBuilder.find_latest_pdf
      raise "ビルド後に PDF が見つかりません（#{font}）" unless src

      path = File.join(dir, "#{font.gsub(/\W+/, '_')}.pdf")
      FileUtils.cp(src, path)

      type3 = VsTestSupport::PdfInspector.fonts(path).select(&:type3?)
      { path:, pages: PDF::Reader.new(path).page_count,
        type3_count: type3.size, type3_pages: type3.map(&:page).uniq.size }
    end

    # 取得した書体ディレクトリと google-fonts.css を元の状態へ戻す。
    # 書体は数 MB あり、テストのたびに作業ツリーへ溜まると差分に紛れる。
    # 元からあったディレクトリ（著者が使っている書体）は消さない。
    def restore_google_fonts
      before = Dir.glob(File.join(GOOGLE_FONTS_DIR, '*'))
      css = File.read(GOOGLE_FONTS_CSS) if File.exist?(GOOGLE_FONTS_CSS)
      yield
    ensure
      (Dir.glob(File.join(GOOGLE_FONTS_DIR, '*')) - before).each { FileUtils.rm_rf(it) }
      File.write(GOOGLE_FONTS_CSS, css) if css
    end
  end

  def setup
    skip 'config/book.yml が見つかりません（リポジトリルートで実行してください）' unless File.exist?('config/book.yml')

    missing = REQUIRED_TOOLS.reject { |t| system("which #{t} > /dev/null 2>&1") }
    skip "必要なツールがありません: #{missing.join(', ')}" unless missing.empty?
  end

  # 太字を持つ Google Fonts でビルドが成立し、本文のある PDF ができること
  def test_should_build_successfully_with_bold_capable_google_font
    result = self.class.results[BOLD_FONT]

    assert_operator result[:pages], :>=, MIN_PAGES,
                    "#{BOLD_FONT} のビルドが #{result[:pages]} ページしかありません（本文欠落の疑い）"
  end

  # 標準の太さしか無い Google Fonts でもビルドが成立すること（ゴシック代用の経路）
  def test_should_build_successfully_with_regular_only_google_font
    result = self.class.results[REGULAR_ONLY_FONT]

    assert_operator result[:pages], :>=, MIN_PAGES,
                    "#{REGULAR_ONLY_FONT} のビルドが #{result[:pages]} ページしかありません（本文欠落の疑い）"
  end

  # 太字がある書体: 実 Bold が埋め込まれ、Type 3 が出ないこと
  def test_should_not_emit_type3_with_bold_capable_google_font
    result = self.class.results[BOLD_FONT]

    assert_operator result[:type3_count], :<=, TYPE3_CEILING,
                    "#{BOLD_FONT} で Type 3 が #{result[:type3_count]} 件出ています" \
                    "（#{result[:type3_pages]} ページに出現）。同梱書体では 0 件なので、" \
                    '同梱以外の書体でだけ対策が素通りしている疑いがあります。' \
                    'まず生成 SVG（showcase / mermaid）にサブセットが埋まっているかを見てください'
  end

  # 太字が無い書体: 疑似太字を合成せず、Type 3 が出ないこと
  def test_should_not_emit_type3_with_regular_only_google_font
    result = self.class.results[REGULAR_ONLY_FONT]

    assert_operator result[:type3_count], :<=, TYPE3_CEILING,
                    "#{REGULAR_ONLY_FONT} で Type 3 が #{result[:type3_count]} 件出ています" \
                    "（#{result[:type3_pages]} ページに出現）。太字を持たない書体なので、" \
                    'font-synthesis-weight: none が効かず疑似太字が合成された疑いがあります'
  end
end
