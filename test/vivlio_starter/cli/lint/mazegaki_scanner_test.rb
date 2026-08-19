# frozen_string_literal: true

# ================================================================
# Test: cli/lint/mazegaki_scanner_test.rb
# ================================================================
# テスト対象:
#   交ぜ書き辞書の第 2 層（lib/vivlio_starter/cli/lint/mazegaki_scanner.rb）
#
# 検証内容（仕様: mazegaki-two-tier-spec.md §3）:
#   MS-01: 語をまたぐマッチを出さない（開始が形態素の頭でない）
#   MS-02: 語の途中で終わるマッチを出さない（終了が形態素の切れ目でない）
#   MS-03: 両端が助詞・助動詞のマッチを出さない
#   MS-04: 同じ綴りでも、語として成立する文では拾う（MS-01〜03 の裏）
#   MS-05: 出荷データの語を拾う
#   MS-06: ProseChecker が第 1 層と合流させ、長いほうを残す
#   MS-07: --fix は判定した位置だけを置換する
#   MS-08: 除外リストは第 2 層にも効く
#   MS-09: MeCab が無い環境では第 2 層が丸ごと黙る（第 1 層は動く）
#
#   強調記法（仕様: inline-emphasis-word-split-spec.md）:
#   EM-01: 語の途中の強調でガードがすり抜けない（誤検出）
#   EM-02: 語の途中の強調で語が分断されても拾う（取りこぼし）
#   EM-03: 記法の外にある語は今までどおり（`2 * 3 * 4`・`snake_case`）
#   EM-04: --fix は語の内側に記法があるとき置換しない（記法を黙って落とさない）
#   EM-05: --fix は記法が語の外なら置換する
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/lint/prose_checker'

class TestMazegakiScanner < Minitest::Test
  PC       = VivlioStarter::CLI::Lint::ProseChecker
  Scanner  = VivlioStarter::CLI::Lint::MazegakiScanner

  def setup
    skip 'MeCab が無い環境では第 2 層を検証できない' unless Scanner.available?
  end

  # 原稿を一時ファイルへ書いて検査する（check はパスを受け取るため）
  def check(markdown, **)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'chapter.md')
      File.write(path, markdown)
      return PC.check(path, **)
    end
  end

  def labels(markdown, **) = check(markdown, **).map(&:label)

  # MS-01/02/03: 語をまたぐマッチは、形態素の境界を見れば全部落ちる。
  # 正規表現だけでは外せなかった型なので、これが第 2 層の存在理由そのものになる。
  def test_should_not_flag_matches_that_span_word_boundaries
    text = <<~MD
      使う回数を減らすと保守が楽になる。
      という回答が返ってきた。
      日本語いろはを学ぶ。
      障害の説明であり患者は増える傾向にある。
    MD

    assert_empty labels(text)
  end

  # MS-04: 同じ綴りでも、1 語として成立する文なら拾う。
  def test_should_flag_mecab_only_words_when_they_stand_as_a_word
    text = <<~MD
      工事でう回する必要がある。
      語いが豊富な文章を書く。
      インフルエンザにり患する。
    MD

    assert_equal ['う回 => 迂回', '語い => 語彙', 'り患 => 罹患'], labels(text)
  end

  # MS-05: 出荷データ（SudachiDict 由来）の語を拾う。
  def test_should_flag_words_from_the_shipped_data
    assert_equal ['あいさつ文 => 挨拶文'], labels("あいさつ文を差し込む。\n")
    assert_equal ['かつお節 => 鰹節'],     labels("かつお節でだしを取る。\n")
    assert_equal ['あばら骨 => 肋骨'],     labels("あばら骨を折った。\n")
  end

  # MS-02 の裏。名詞の見出しが活用語尾のぶんだけはみ出さないこと。
  # 「引っかかった」を「引っ掻かった」にしてはならない。
  def test_should_not_flag_a_noun_that_ends_inside_an_inflected_verb
    assert_empty labels("どのルールに引っかかったかがわかる。\n")
    assert_empty labels("ビルド成果物ごとにハッシュを持つ。\n")
  end

  # MS-06: 第 1 層と第 2 層が同じ行に当たったら、長いほうを残す。
  def test_should_merge_both_tiers_and_keep_the_longer_word
    text = "だ円の面積を求め、工事でう回する。\n"

    assert_equal ['だ円 => 楕円', 'う回 => 迂回'], labels(text).sort_by { text.index(it[/\A\S+/]) }
  end

  # MS-02: コード領域は Masking が退避するので、綴りを解説する行を壊さない。
  def test_should_not_flag_inside_code_spans
    assert_empty labels("`う回` と `あいさつ文` は綴りの説明です。\n")
  end

  # MS-07: --fix は判定した位置だけを置換する。同じ行に「語として成立しない
  # 同じ綴り」があっても、そちらは触らない。
  def test_should_replace_only_the_judged_span
    text = "使う回数は減るが、工事でう回する。\n"

    assert_equal "使う回数は減るが、工事で迂回する。\n", PC.fix_mazegaki(text)
  end

  # MS-07: 行数と、コード領域の中身を保つ。
  def test_should_preserve_line_count_and_code_spans_on_fix
    text = "あいさつ文を書く。\n`あいさつ文` は綴りの説明。\nあばら骨を折った。\n"
    fixed = PC.fix_mazegaki(text)

    assert_equal text.lines.size, fixed.lines.size
    assert_equal "挨拶文を書く。\n`あいさつ文` は綴りの説明。\n肋骨を折った。\n", fixed
  end

  # MS-08: 除外リストは層を問わず効く。窓口が層ごとに分かれると著者が二度学ぶ。
  def test_should_respect_the_allowlist_in_the_second_tier
    allowlist = PC.send(:compile_allowlist_entry, 'あいさつ文')

    assert_empty labels("あいさつ文を差し込む。\n", allowlist: [allowlist])
    assert_equal "あいさつ文を差し込む。\n", PC.fix_mazegaki("あいさつ文を差し込む。\n", [allowlist])
  end

  # EM-01: 前後を制約するガードが、語の途中の `**` ですり抜けていた。
  # `結**合し**直した` は生の行では `合` の直前が `*` になる。
  def test_should_not_be_fooled_by_emphasis_inside_a_word
    assert_empty labels("結**合し**直した処理。\n")
    assert_empty labels("使**う回**数を減らす。\n")
  end

  # EM-02: 逆向きの穴。語が記法で割れると当たらなくなっていた。
  def test_should_still_flag_a_word_split_by_emphasis
    assert_equal ['だ円 => 楕円'],         labels("だ**円**の面積を求める。\n")
    assert_equal ['あいさつ文 => 挨拶文'], labels("あいさつ**文**を差し込む。\n")
    assert_equal ['かぎ括弧 => 鉤括弧'],   labels("か**ぎ括弧**を使う。\n")
  end

  # EM-03: 記法でない記号を壊さない。判断の根拠は VFM の実際の出力。
  def test_should_leave_non_emphasis_markers_alone
    assert_empty labels("2 * 3 * 4 の計算を書く。\n")
    assert_empty labels("snake_case_name という名前。\n")
  end

  # EM-04: 語の内側に記法があるときは置換しない。`だ**円**` を `楕円` にすると
  # `**` が黙って消える——著者の書いた記法を lint が落とすのは避ける。
  def test_should_not_replace_when_emphasis_sits_inside_the_word
    assert_equal "だ**円**の面積。\n", PC.fix_mazegaki("だ**円**の面積。\n")
    assert_equal "あいさつ**文**を差し込む。\n", PC.fix_mazegaki("あいさつ**文**を差し込む。\n")
  end

  # EM-05: 記法が語の外なら、記法を保ったまま置換する。
  def test_should_replace_and_keep_emphasis_outside_the_word
    assert_equal "**楕円**と完璧な実装。\n", PC.fix_mazegaki("**だ円**と完ぺきな実装。\n")
  end

  # MS-09: MeCab が無い環境。第 2 層は黙り、第 1 層だけが残る。
  # available? のメモを潰して再判定させる（reset! はそのための入口）。
  def test_should_fall_back_to_the_first_tier_without_mecab
    Scanner.reset!
    Scanner.instance_variable_set(:@available, false)

    assert_empty Scanner.scan('工事でう回する。')
    assert_equal ['だ円 => 楕円'], labels("だ円の面積を求め、工事でう回する。\n")
  ensure
    Scanner.reset!
  end
end
