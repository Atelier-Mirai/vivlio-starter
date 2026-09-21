# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/dictionary_conflict_test.rb
#
# 辞書の整合性（DC）
#
# 【検証内容】
#   DC-01: scripts/dict_conflicts.rb → exit 0（辞書どうしが逆を向いていない）
#
# 【実行方法】
#   rake test:manual   （リポジトリルートで実行。2 秒ほど）
#
# 【なぜリリースゲートに置くか】
#   ML-01 が「この本の原稿に指摘が無い」を見張るのに対し、こちらは
#   **配る辞書そのもの**を見張る。辞書は scaffold に載って全ての本へ渡るので、
#   矛盾を抱えたまま出荷すると、著者は消せない指摘を踏む——直すと別のルールが
#   鳴り、戻すと元のルールが鳴る。原因は辞書側にあるため、原稿をいくら読んでも
#   分からない。この本に用例が無い語でも刺さるので、原稿の検査では捕まらない。
#
#   rake test には入れない。辞書を育てている最中は赤くなるのが当たり前で、
#   コードの回帰でないもので通常テストが落ちると、赤の意味が薄れるためである。
#
# 【検査が見るもの】
#   1. 自前辞書の expected を spellcheck-tech-word が叱らないか
#      （上流の実装を実際に呼ぶ。癖まで真似ずに済む）
#   2. 自前辞書どうし・自分自身と逆を向いていないか
#   3. 同じ expected を別ファイルが宣言していないか
#      （prh はファイルをまたぐと後のパターンを黙って捨てる）
#
# 【注意】
#   node と spellcheck-tech-word が要る。無ければ skip する（終了コード 2）。
# =============================================================================

require "English"
require "shellwords"
require "minitest/autorun"

class DictionaryConflictTest < Minitest::Test
  SCRIPT = File.expand_path("../../../scripts/dict_conflicts.rb", __dir__)

  UNAVAILABLE = 2 # 上流辞書が見つからず検査できない

  class << self
    def result
      @result ||= begin
        output = `ruby #{SCRIPT.shellescape} 2>&1`
        { status: $CHILD_STATUS.exitstatus, output: output }
      end
    end
  end

  def test_dictionaries_do_not_contradict_each_other
    result = self.class.result

    skip "spellcheck-tech-word が見つかりません（この検査は実物の辞書が要る）" if result[:status] == UNAVAILABLE

    assert_equal 0, result[:status], <<~MSG
      辞書どうしが食い違っています。著者はこの指摘を消せません。

      #{result[:output]}
    MSG
  end
end
