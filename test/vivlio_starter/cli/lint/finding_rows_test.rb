# frozen_string_literal: true

# ================================================================
# Test: cli/lint/finding_rows_test.rb
# ================================================================
# テスト対象:
#   3 つの検査で集約表示を揃える整形（lib/vivlio_starter/cli/lint/finding_rows.rb）
#
# 検証内容:
#   FR-01: 件数の多い順に並ぶ
#   FR-02: 件数が同じなら最初の出現行の早い順に並ぶ（sort_by は安定ではない）
#   FR-03: 出現行は重複を畳んで昇順にする
#   FR-04: 出現行が 10 を超えると … で省く
#   FR-05: 件数は呼び出し側の値をそのまま使う（検査ごとに数え方が違うため）
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/lint/finding_rows'

class TestFindingRows < Minitest::Test
  FR = VivlioStarter::CLI::Lint::FindingRows

  def row(count, label, lines) = { count: count, label: label, lines: lines }

  # FR-01: 件数の多い順
  def test_should_sort_by_count_descending
    rows = FR.arrange([row(1, 'a', [5]), row(3, 'b', [90]), row(2, 'c', [1])])

    assert_equal %w[b c a], rows.map { it[:label] }
  end

  # FR-02: 同数なら最初の出現行の早い順。著者が原稿を上から直せるようにするため
  def test_should_break_ties_by_first_line
    rows = FR.arrange([row(2, 'late', [300, 310]), row(2, 'early', [7, 400]), row(2, 'mid', [50])])

    assert_equal %w[early mid late], rows.map { it[:label] }
  end

  # FR-03: 同じ行に 2 度出ても表示は 1 度。並びも昇順に直す
  def test_should_fold_duplicate_lines_and_sort_them
    rows = FR.arrange([row(3, 'a', [30, 10, 10])])

    assert_equal '10, 30', rows.first[:lines]
  end

  # FR-04: 11 行目以降は … に畳む（画面を出現行で埋めない）
  def test_should_truncate_lines_beyond_the_limit
    rows = FR.arrange([row(12, 'a', (1..12).to_a)])

    assert_equal '1, 2, 3, 4, 5, 6, 7, 8, 9, 10, …', rows.first[:lines]
  end

  # FR-05: 件数は触らない。スペルチェックは出現行数、他は指摘の個数で数えており、
  # ここで数え直すとどちらかの検査の意味が変わってしまう
  def test_should_keep_the_caller_count_untouched
    rows = FR.arrange([row(9, 'a', [1, 1, 2])])

    assert_equal 9, rows.first[:count], '行を畳んでも件数は呼び出し側のまま'
  end

  # 出現行が空でも落ちない（行番号を持たない指摘があり得る）
  def test_should_survive_rows_without_lines
    rows = FR.arrange([row(1, 'no-line', []), row(1, 'has-line', [4])])

    assert_equal %w[no-line has-line], rows.map { it[:label] }, '行なしは先頭に置く'
    assert_equal '', rows.first[:lines]
  end
end
