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
#   （after.md）と突き合わせる。期待値で変わるのは 3 行目だけ——表示される指摘のうち
#   直してよいもの（`(2026年)` → `（2026年）`、著者の規則 `ユーザ` → `ユーザー`）である。
#
#   見本原稿の各行が守りを確かめるもの:
#     5 行目  disabled_rules（一つ）・trim_long_vowel の上流項目（ディレクタ・ベンダ・メンバ）
#     7 行目  ふりがな（`{沢山|たくさん}`。「沢山 => たくさん」は表示されるが直さない）
#     9 行目  相互参照のラベル（`@ruby-sample`・`@pageref:javascript-intro`）
#     11 行目 数式の中の半角かっこ・値つきの属性記法
#     13-14   次行抑止の行の数式と属性記法（復元の順序）
#     16-18   出力例の囲み（ラベル・Ruby・交ぜ書き）
#     20 行目 クラス属性 / 22-23 番号付きリストの記号
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

  private

  def textlint_available?
    _out, status = Open3.capture2e(ENV.fetch('VIVLIO_TEXTLINT_BIN', 'textlint'), '--version')
    status.success?
  rescue SystemCallError
    false
  end
end
