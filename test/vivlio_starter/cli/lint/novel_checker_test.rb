# frozen_string_literal: true

# ================================================================
# Test: cli/lint/novel_checker_test.rb
# ================================================================
# テスト対象:
#   Lint::NovelChecker（小説の規則。novel-vertical-spec.md §6.2）を、ProseChecker.check を通して
#
# 検証内容:
#   - 規則ごとに、示すものと示さないもの（§6.2 の表の 2 列）
#   - 読者が見る字で見る（投稿サイトの記法・行内の属性・強調・コード・URL を外す）
#   - 閉じかっこの前の句点は、句点を付けない閉じかっこの多い章でだけ示す
#   - 字下げの規則は notation.web_novel で向きが変わる
#   - 半角の数字は縦書きの本だけで、横組みの箱の中は見ない
#   - 規則の組 novel のほかでは、どれも出ない
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/lint/prose_checker'
require 'vivlio_starter/cli/lint/rulesets'

class TestNovelChecker < Minitest::Test
  PC = VivlioStarter::CLI::Lint::ProseChecker
  NC = VivlioStarter::CLI::Lint::NovelChecker
  Rulesets = VivlioStarter::CLI::Lint::Rulesets

  def check(body, ruleset: 'novel', web_novel: true, vertical: true)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'chapter.md')
      File.write(path, body)
      PC.check(path, disabled_rules: Rulesets.disabled_by(ruleset), web_novel:, vertical:)
        .select { NC::RULES.include?(it.rule) }
    end
  end

  def lines_of(findings, rule) = findings.select { it.rule == rule }.map(&:line)

  def test_ellipsis_should_flag_odd_runs_and_substitutes
    findings = check("待って…\n待って……\n待って………\n待って・・・\n待って。。。\n中黒・で区切る。\n")

    assert_equal [1, 3, 4, 5], lines_of(findings, NC::ELLIPSIS_RULE)
  end

  def test_dash_should_flag_a_single_dash_but_not_ranges
    findings = check("光が――溢れた。\n光が―溢れた。\n光が—溢れた。\n1—3 頁と A―B 間。\n")

    assert_equal [2, 3], lines_of(findings, NC::DASH_RULE)
  end

  def test_space_after_mark_should_flag_a_mark_followed_by_a_letter
    findings = check(<<~MD)
      本当に！嘘でしょう？
      「えっ！」と言った。
      きゃっ！？　なに……！　驚き‼――
      本当に！　嘘でしょう？
      行末の感嘆！
    MD

    assert_equal [1], lines_of(findings, NC::SPACE_AFTER_MARK_RULE), "行末の「？」は示さない"
    assert_includes findings.map(&:label), '「！」の後に全角空白がありません（「！嘘」→「！　嘘」）'
  end

  # 読者が見る字で見る。行内の属性・強調・コードを外した後で続く字を見る
  def test_should_read_the_text_the_reader_sees
    findings = check("[えっ！]{.sesame}言った。**まさか！**と思う。`a！b` は見ない。\n")

    assert_equal [1, 1], lines_of(findings, NC::SPACE_AFTER_MARK_RULE)
  end

  # 「。」」で書きそろえた章（青空文庫の作品の多く）は示さず、句点を付けない書き方に混ざったものを示す
  def test_period_before_bracket_should_flag_only_the_minority
    mixed = check("「行こう」\n「待って」\n「わかった。」\n「（補足。）」\n")
    consistent = check("「行こう。」\n「待って。」\n「わかった」\n")

    assert_equal [3], lines_of(mixed, NC::PERIOD_BEFORE_BRACKET_RULE)
    assert_empty lines_of(consistent, NC::PERIOD_BEFORE_BRACKET_RULE)
  end

  # 投稿サイトの記法を読まない本では、行頭の全角空白は CSS の字下げに足されて 2 字下がる
  def test_paragraph_indent_should_flag_every_leading_space_without_web_novel
    findings = check("# 章\n\n　地の文。\n\n地の文。\n\n　「会話」\n", web_novel: false)

    assert_equal [3, 7], lines_of(findings, NC::PARAGRAPH_INDENT_RULE)
  end

  # 読む本では、章の中で混ざったときに少ない側（同数なら全角空白の無い側）。括弧の段落は数えない
  def test_paragraph_indent_should_flag_the_minority_with_web_novel
    findings = check("# 章\n\n　一。\n\n　二。\n\n三。\n\n「会話」\n\n- 箇条\n\n* * *\n")
    tie = check("　一。\n\n二。\n")
    even = check("　一。\n\n　二。\n\n「会話」\n")

    assert_equal [7], lines_of(findings, NC::PARAGRAPH_INDENT_RULE)
    assert_equal [3], lines_of(tie, NC::PARAGRAPH_INDENT_RULE)
    assert_empty lines_of(even, NC::PARAGRAPH_INDENT_RULE)
  end

  # 囲みの中（地付きの底本の表記など）と脚注の定義は、本文の段落の字下げで組まれないので数えない
  def test_paragraph_indent_should_skip_containers_and_footnote_definitions
    findings = check(<<~MD)
      　一[^1]。

      　二。

      [^1]: 注の文。

      :::{.text-right}
      底本：「本」
      入力：誰か
      :::
    MD

    assert_empty lines_of(findings, NC::PARAGRAPH_INDENT_RULE)
  end

  def test_halfwidth_digits_should_flag_three_or_more_digits_in_vertical_books
    source = <<~MD
      2026年に12人と100円。３００円と三百円。
      https://example.com/2026 と `2026` と ![図](img/2026.png){width=300px}

      :::{.note}
      注の中の 2026 は横組み。
      :::
    MD
    vertical = check(source)
    horizontal = check(source, vertical: false)

    assert_equal [1, 1], lines_of(vertical, NC::HALFWIDTH_DIGITS_RULE)
    assert_includes vertical.map(&:label), '半角の数字 3 桁以上は横に倒れて組まれます（「2026」→「二〇二六」か「２０２６」）'
    assert_empty lines_of(horizontal, NC::HALFWIDTH_DIGITS_RULE)
  end

  # 投稿サイトの記法は読み替えた字で見る。ルビの読みや傍点の印を地の文と取り違えない
  def test_should_read_web_novel_marks_as_the_build_does
    findings = check("|驚き《おどろき！》と《《本当に！》》　言った。|《題名》\n")

    assert_empty findings
  end

  def test_should_respect_no_lint_and_code_fences
    findings = check("<!-- no-lint -->\n待って…\n```\n待って…\n```\n")

    assert_empty findings
  end

  def test_should_be_silent_outside_the_novel_ruleset
    source = "待って…\n光が―溢れた。\n本当に！嘘。\n「a」「b」「c。」\n　頭。\n2026年。\n"

    refute_empty check(source)
    assert_empty check(source, ruleset: 'technical')
    assert_empty check(source, ruleset: 'minimal')
  end

  def test_rules_can_be_disabled_one_by_one
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'chapter.md')
      File.write(path, "待って…\n光が―溢れた。\n")
      findings = PC.check(path, disabled_rules: Rulesets.disabled_by('novel') + [NC::ELLIPSIS_RULE],
                                web_novel: true, vertical: true)

      assert_equal [NC::DASH_RULE], findings.map(&:rule).grep(/\Anovel-/)
    end
  end
end
