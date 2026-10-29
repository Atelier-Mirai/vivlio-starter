# frozen_string_literal: true

# ================================================================
# Test: build/lead_layout_test.rb
# ================================================================
# 章扉のリードと章題を、組まずに行へ分ける（LeadLayout・chapter-lead-size-spec.md §4.4）。
# 規則は、3 冊のリードを Vivliostyle で組んだ実物の改行と比べて決めたもの。書体は同梱の Noto Serif JP。
# 幅は「字の大きさに対する比」（全角 1 字 = 1.0）で渡す。
# ================================================================

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/build/lead_layout'

class TestLeadLayout < Minitest::Test
  LeadLayout = VivlioStarter::CLI::Build::LeadLayout
  FontMetrics = VivlioStarter::CLI::Build::FontMetrics
  FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)

  def fonts
    LeadLayout::Fonts.new(body: FontMetrics.load("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf"),
                          bold: FontMetrics.load("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Bold.ttf"),
                          code: FontMetrics.load("#{FONTS}/hackgen35/HackGen35ConsoleNF-Regular.ttf"))
  end

  def lines(html, limit, indent: 0.0) = LeadLayout.break_lines(LeadLayout.atoms(html, fonts), limit, indent:)

  # --- 行の詰め方 ---

  # 段落の頭は 1 字下げる（.chapter-lead p { text-indent: 1em }）
  def test_should_indent_first_line_of_paragraph
    assert_equal ['あ' * 9, 'あ' * 10, 'あ' * 10, 'あ'], lines('あ' * 30, 10, indent: 1.0)
  end

  # 行頭に来られない「。」は前の字と一緒に送る
  def test_should_not_start_line_with_closing_punctuation
    assert_equal ['あ' * 9, 'あ。い'], lines("#{'あ' * 10}。い", 10)
  end

  # 行末の終わり約物は半角に詰めて収める（Vivliostyle の text-spacing: auto）
  def test_should_trim_closing_punctuation_at_line_end
    assert_equal ["#{'あ' * 9}、", 'いいい'], lines("#{'あ' * 9}、いいい", 9.5)
  end

  # 和欧間のアキ（1/8 字）は空白の字なので、行末ではぶら下がって数えない
  def test_should_hang_autospace_at_line_end
    assert_equal ['あ' * 9, 'Ruby'], lines("#{'あ' * 9}Ruby", 9)
  end

  # ASCII の引用符の前後では折れない（「は"abc"を」は一続き）
  def test_should_not_break_around_ascii_quotes
    assert_equal ['あ' * 8, 'は"abc"を'], lines("#{'あ' * 8}は\"abc\"を", 9)
  end

  # 欧文の語の中は、ハイフンの後でだけ折れる（実物で「joyful-／janken」）
  def test_should_break_latin_word_only_after_hyphen
    assert_equal 'janken', lines("#{'あ' * 6}joyful-janken", 10).last
  end

  # 折れない並びが 1 行より長いときは、はみ出して次の折り目まで置く
  def test_should_overflow_unbreakable_run_longer_than_line
    assert_equal ['あ', 'supercalifragilistic', 'い'], lines('あsupercalifragilisticい', 5)
  end

  # 用語集の印 † の前では折れる。印から次の行が始まる（実物で「k平均法／†、ナイーブベイズ」）
  def test_should_break_before_glossary_mark
    mark = %q(<a class="glossary-link" href="#g"><sup>†</sup></a>)

    assert_equal [%q(ああ法), %q(†、い)], lines("ああ法#{mark}、い", 3.5)
  end

  # --- 字の幅 ---

  # 約物が並んだら詰める。終わり約物の後ろが終わり約物なら前を、始め括弧の前が約物なら始め括弧を半角に。
  # 「、「」は「「」だけを詰める（Vivliostyle は終わり約物の後ろが始め括弧でも前を詰めない）
  def test_should_trim_adjacent_punctuation
    assert_equal [0.5, 1.0], LeadLayout.trimmed_widths(LeadLayout.atoms('。」', fonts))
    assert_equal [1.0, 0.5], LeadLayout.trimmed_widths(LeadLayout.atoms('、「', fonts))
  end

  # 書体のカーニングを字の送りに足す（「す。」は 0.08 字詰まる）
  def test_should_add_kerning_to_advance
    assert_in_delta 0.92, LeadLayout.atoms('す。', fonts).first.width, 1e-9
  end

  # 書体ごとに送りを読む: インラインコードは HackGen（半角 0.604 字）、数式の画像は ex を x ハイトで、
  # 用語集の印 † は 0.7 倍の本文の書体に 0.1 字のアキ
  def test_should_measure_code_images_and_glossary_marks
    code = LeadLayout.atoms('<code>ab</code>', fonts)
    image = LeadLayout.atoms('<img style="vertical-align: -0.5ex; width: 10ex; height: 2ex;">', fonts)
    mark = LeadLayout.atoms('<a class="glossary-link" href="#g"><sup>†</sup></a>', fonts)

    assert_in_delta 0.604 * 2, code.sum(&:width), 1e-3
    assert_in_delta 5.14, image.first.width, 1e-9
    assert_in_delta 0.1 + (0.7 * fonts.body.advance('†')), mark.first.width, 1e-9
  end

  # @pageref は CSS が「（p.123）」を足す。組む前はページが分からないので 3 桁とみる
  def test_should_count_page_reference_suffix
    atoms = LeadLayout.atoms('<a class="cross-ref-link pageref" href="#x">第2章</a>', fonts)

    assert_equal '第2章（p.000）', atoms.map(&:char).join
  end

  # 行の幅は 1/64 px に切り上げ、1 単位の遊びを足す（74.08mm = 279.988px に 280px の行が入った）
  def test_should_round_width_up_like_chromium
    assert_operator LeadLayout.layout_px(74.08 * 96 / 25.4), :>=, 280.0
    assert_in_delta 280.015625, LeadLayout.layout_px(74.08 * 96 / 25.4), 1e-9
  end

  # --- 章題 ---

  def title_lines(segments, chars)
    LeadLayout.title_line_count(segments, metrics: FontMetrics.load("#{FONTS}/Noto_Sans_JP/NotoSansJP-Bold.ttf"),
                                          glossary_metrics: fonts.body, width_px: chars * 1.08 * 10, font_px: 10,
                                          letter_spacing: 0.08)
  end

  # 文節の境目でも、欧文の語の途中では折れない（「catalog」と「.yml」）。実物は 3 行だった
  def test_should_join_title_segments_inside_latin_word
    assert_equal 3, title_lines(['book', '.', 'yml・', 'catalog', '.', 'yml ', 'リファレンス'], 10)
  end

  # 1 行より長い文節は折れずにはみ出す（.vs-nobr は white-space: nowrap）。実物は 2 行だった
  def test_should_not_break_title_segment_longer_than_line
    assert_equal 2, title_lines(%w[相互 参照 （クロスリファレンス）], 10)
  end

  def test_should_count_single_line_title
    assert_equal 1, title_lines(%w[第1部 　 基礎 編], 10)
  end
end
