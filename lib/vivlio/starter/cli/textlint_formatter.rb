# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/textlint_formatter.rb
# ================================================================
# 責務:
#   textlint の英語エラーメッセージを日本語に翻訳する。
#
# 翻訳対象:
#   - "Disallow to use "!"" → "感嘆符「!」は使用しないでください"
#   - "Disallow to use "？"" → "疑問符「？」は使用しないでください"
#
# 用途:
#   - TextLintCommands から呼び出される
#   - 日本語ユーザー向けのエラーメッセージ改善
# ================================================================

module Vivlio
  module Starter
    module CLI
      # textlint 出力の日本語化フォーマッター
      class TextlintFormatter
        # エラーメッセージの日本語マッピング
        MESSAGE_TRANSLATIONS = {
          'Disallow to use "!"' => '感嘆符「!」は使用しないでください',
          'Disallow to use "！"' => '感嘆符「！」は使用しないでください',
          'Disallow to use "?"' => '疑問符「?」は使用しないでください',
          'Disallow to use "？"' => '疑問符「？」は使用しないでください'
        }.freeze

        def self.translate_output(output)
          return output if output.nil? || output.empty?

          translated = output.dup
          MESSAGE_TRANSLATIONS.each do |english, japanese|
            translated.gsub!(english, japanese)
          end
          translated
        end
      end
    end
  end
end
