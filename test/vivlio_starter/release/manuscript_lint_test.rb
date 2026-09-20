# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/manuscript_lint_test.rb
#
# 原稿の文章品質（ML）
#
# 【検証内容】
#   ML-01: リポジトリルートで vs lint → exit 0（指摘ゼロ）
#
# 【実行方法】
#   rake test:manual   （リポジトリルートで実行。10 秒ほど）
#
# 【なぜリリースゲートに置くか】
#   同じ並びの MB-03 が「ビルドの警告ゼロ」を見張っているのと対になる。
#   こちらは「原稿の指摘ゼロ」で、出荷する本そのものの状態を certify する。
#
#   rake test には入れない。原稿を書いている最中は当然のように赤くなり、
#   コードの回帰でないもので通常テストが落ちると、赤の意味が薄れるためである。
#
# 【逃げ道を作らない】
#   MB-03 には allowed_warnings.yml があるが、こちらには置かない。いま指摘は
#   0 件で、最初から例外表を用意すると「0 件を保つ」規律がすぐ緩む。抑止が
#   要る箇所は原稿へ `<!-- no-lint -->` を置く——理由がその場に残るほうがよい。
#
# 【注意】
#   リポジトリのソースコード（ruby -Ilib bin/vs）を実行するため、
#   インストール済み gem の状態には依存しない。出荷するコードで点検する。
# =============================================================================

require "English"
require "minitest/autorun"
require_relative "../support/build_helper"

class ManuscriptLintTest < Minitest::Test
  class << self
    # 10 秒ほどかかるので 1 回だけ実行し、結果を共有する
    def lint_result
      @lint_result ||= begin
        command = "#{VsTestSupport::VsBuilder.repo_vs_command} lint 2>&1"
        output  = `#{command}`
        { success: $CHILD_STATUS.success?, output: output }
      end
    end
  end

  def test_manuscript_has_no_lint_findings
    skip "textlint が見つかりません（この検査は実物の textlint が要る）" unless textlint_available?

    result = self.class.lint_result

    assert result[:success], <<~MSG
      vs lint が指摘を返しました。原稿を直すか、意図した表記なら該当行の前へ
      <!-- no-lint --> を置いてください（範囲なら no-lint-start / no-lint-end）。

      #{findings(result[:output])}
    MSG
  end

  private

  # 指摘の行だけを抜き出す（"  3件  [prh] …" と、その次の "行: …"）
  def findings(output)
    output.lines.grep(/件\s{2}\[|^\s+行: /).join
  end

  def textlint_available?
    system("which textlint > /dev/null 2>&1")
  end
end
