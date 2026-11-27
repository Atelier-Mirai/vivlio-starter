# frozen_string_literal: true

# ================================================================
# Test: cli/lint/fix_invariant_test.rb
# ================================================================
# テスト対象:
#   vs lint --fix の不変条件——「--fix が書き換えるのは、表示で指摘した箇所だけ」。
#
# なぜ要るか:
#   解析パス（表示）と修正パス（--fix）は経路が違う。表示の段でだけ抑止していたものを
#   --fix が直す食い違いが 6 回出た（lint-false-positive-notes.md §7）。単体テストは
#   textlint を差し替えて動かすので、この種の食い違いはここでしか捕まらない。
#
# 手口:
#   記法と抑止を網羅した見本原稿（fixtures/lint_fix_invariant/before.md）に、**出荷している
#   雛形の設定**（lib/project_scaffold/config）で実物の textlint を当て、結果を期待値
#   （after.md）と突き合わせる。期待値で変わるのは 3・29・45 行目だけ——表示される指摘のうち
#   直してよいもの（`(2026年)` → `（2026年）`、著者の規則 `ユーザ` → `ユーザー`、正しい綴りの後ろの `ruby`、
#   活用形の「気付い」→「気づい」）である。
#
#   見本原稿の各行が守りを確かめるもの:
#     5 行目  disabled_rules（一つ）・trim_long_vowel の上流項目（ディレクタ・ベンダ・メンバ）
#     7 行目  ふりがな（`{沢山|たくさん}`。「沢山 => たくさん」は表示されるが直さない）
#     9 行目  相互参照のラベル（`@ruby-sample`・`@pageref:javascript-intro`）
#     11 行目 数式の中の半角かっこ・値つきの属性記法
#     13-14   次行抑止の行の数式と属性記法（復元の順序）
#     16-18   出力例の囲み（ラベル・Ruby・交ぜ書き）
#     20 行目 クラス属性 / 22-23 番号付きリストの記号
#     25 行目 〘`〙 の後ろのコード・名前の一部の小文字（ruby/ruby.wasm・javascript.info。後者は prh にも当たる）（改善案 #170）
#     27 行目 英字の語の後ろのかっこの読み（**Unicode**（ユニコード））
#     29 行目 同じ段落の 2 つ目の当たり（上流の規則は最初の 1 か所しか照合しなかった）
#     31-45   改善案 #180: 語の途中の大小（WEBrick）・git のコマンド・剰余の %・訳語に添えた原語と
#             カギかっこの文言・「の時・分」「通り道」・算用数字の「2 通り」（指摘だけ）・データ展開の行・
#             「気付く」の活用形（直す）
#     47 行目 改善案 #181: 同じ段落の 2 つの「じゃんけん」（形態素解析が頭の「じゃ」を接続詞に切る）
#
# 前提:
#   textlint とプリセットが入っていない環境（CI など）では skip する。
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class TestLintFixInvariant < Minitest::Test
  REPO     = File.expand_path('../../../..', __dir__)
  FIXTURES = File.join(REPO, 'test/vivlio_starter/fixtures/lint_fix_invariant')

  def test_fix_rewrites_only_what_the_analysis_reports
    skip 'textlint が見つかりません（この検査は実物の textlint が要る）' unless textlint_available?

    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(REPO, 'lib/project_scaffold/config'), File.join(dir, 'config'))
      FileUtils.mkdir_p(File.join(dir, 'contents'))
      chapter = File.join(dir, 'contents', '98-fixture.md')
      FileUtils.cp(File.join(FIXTURES, 'before.md'), chapter)

      # 指摘が残るので終了コードは 1 になる（`沢山 => たくさん` は表示されるが直さない）。見ない
      _out, err, = Open3.capture3(RbConfig.ruby, '-I', File.join(REPO, 'lib'), File.join(REPO, 'bin/vs'),
                                  'lint', '98', '--fix', chdir: dir)

      assert_equal File.read(File.join(FIXTURES, 'after.md')), File.read(chapter),
                   "--fix が表示と食い違う書き換えをした（lint-false-positive-notes.md §7）\n#{err}"
    end
  end

  # 31-45 行目（改善案 #180）は、表示でも指摘しない。「2 通り」だけは指摘を残し、--fix では直さない
  def test_analysis_leaves_the_lines_of_improvement_180_alone
    skip 'textlint が見つかりません（この検査は実物の textlint が要る）' unless textlint_available?

    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(REPO, 'lib/project_scaffold/config'), File.join(dir, 'config'))
      FileUtils.mkdir_p(File.join(dir, 'contents'))
      FileUtils.cp(File.join(FIXTURES, 'before.md'), File.join(dir, 'contents', '98-fixture.md'))

      out, = Open3.capture3(RbConfig.ruby, '-I', File.join(REPO, 'lib'), File.join(REPO, 'bin/vs'), 'lint', '98', chdir: dir)
      labels = out.lines.grep(/件\s+\[/).map(&:strip)

      %w[WEBr git ％ パス アクティビティ のとき とおり道 JavaScript].each do |word|
        assert labels.none? { it.include?(word) }, "#{word} を含む指摘が出た:\n#{labels.join("\n")}"
      end
      assert labels.any? { it.include?('2 通り => 二通り') }, "算用数字の「2 通り」は指摘を残す:\n#{labels.join("\n")}"
      assert labels.any? { it.include?('気付い => 気づい') }, "「気付く」の活用形も指摘する:\n#{labels.join("\n")}"
      assert labels.none? { it.include?('接続詞（じゃ）') }, "「じゃんけん」を接続詞の連続と読んだ（改善案 #181）:\n#{labels.join("\n")}"
    end
  end

  private

  def textlint_available?
    _out, status = Open3.capture2e(ENV.fetch('VIVLIO_TEXTLINT_BIN', 'textlint'), '--version')
    status.success?
  rescue SystemCallError
    false
  end
end
