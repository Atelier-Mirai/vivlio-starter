# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # textlint の出力を日本語化するフォーマッター
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
