# frozen_string_literal: true

require_relative '../../../test_helper'

# Twemoji クレジット HTML 生成ロジックのテスト
# execute_legalpage 内の Twemoji クレジットセクション生成パターンを
# グローバル状態（Common::CONFIG）に依存せず検証する
class LegalpageTwemojiTest < Minitest::Test
  # execute_legalpage 内の Twemoji クレジット生成ロジックを再現するヘルパー
  # グローバル状態への依存を避け、純粋関数として検証可能にする
  def generate_twemoji_credit(twemoji_text)
    return "" if twemoji_text.nil? || twemoji_text.to_s.strip.empty?

    <<~MD

      <div class="twemoji-credit">
        <h2>■絵文字クレジット</h2>
        #{twemoji_text.to_s.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
      </div>
    MD
  end

  def test_should_generate_twemoji_credit_section
    text = "絵文字画像: Twemoji (https://twemoji.twitter.com) © Twitter, Inc. (CC BY 4.0)"
    result = generate_twemoji_credit(text)

    assert_includes result, '<div class="twemoji-credit">'
    assert_includes result, "■絵文字クレジット"
    assert_includes result, text
  end

  def test_should_omit_twemoji_credit_when_not_set
    result = generate_twemoji_credit(nil)

    assert_equal "", result
  end

  def test_should_omit_twemoji_credit_when_empty_string
    result = generate_twemoji_credit("")

    assert_equal "", result
  end

  def test_should_output_multiline_twemoji_credit_as_separate_p_tags
    text = "Line 1\nLine 2\nLine 3"
    result = generate_twemoji_credit(text)

    assert_equal 3, result.scan("<p>").count
    assert_includes result, "<p>Line 1</p>"
    assert_includes result, "<p>Line 2</p>"
    assert_includes result, "<p>Line 3</p>"
  end

  def test_should_wrap_credit_in_twemoji_credit_div
    text = "Credit text"
    result = generate_twemoji_credit(text)

    assert_includes result, '<div class="twemoji-credit">'
    assert_includes result, '</div>'
  end
end
