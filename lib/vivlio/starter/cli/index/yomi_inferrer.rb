# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/index/yomi_inferrer.rb
# ================================================================
# 責務:
#   MeCab を使用して日本語テキストの読み（ひらがな）を推測する。
#   - 形態素解析で各形態素の読み情報を取得
#   - カタカナをひらがなに変換
#   - MeCab が利用できない場合は元のテキストをそのまま返す
#
# 依存:
#   - natto gem (MeCab Ruby バインディング)
#   - MeCab 本体（システムにインストール済みであること）
# ================================================================

require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        # MeCab による読み推測クラス
        class YomiInferrer
          def initialize
            @mecab = nil
            @available = nil
          end

          # テキストの読みを推測
          # @param text [String] 読みを推測するテキスト
          # @return [String] ひらがなの読み（推測できない場合は元のテキスト）
          def infer(text)
            return text unless available?

            yomi_parts = []

            mecab.parse(text) do |node|
              next if node.is_eos?

              # 読み情報を取得（feature の 8 番目 = カタカナ読み）
              features = node.feature.split(',')
              reading = features[7] if features.size > 7

              yomi_parts << if reading && reading != '*' && !reading.empty?
                              katakana_to_hiragana(reading)
                            else
                              # 読みが取得できない場合は表層形をそのまま使用
                              node.surface
                            end
            end

            result = yomi_parts.join
            result.empty? ? text : result
          end

          # MeCab が利用可能かどうか
          def available?
            return @available unless @available.nil?

            @available = begin
              require 'natto'
              # MeCab の初期化を試行
              @mecab = Natto::MeCab.new
              true
            rescue LoadError => e
              Common.log_warn("natto gem がインストールされていません: #{e.message}")
              Common.log_warn('索引機能では MeCab による読み推測が利用できません')
              Common.log_warn('gem install natto を実行してください')
              false
            rescue StandardError => e
              Common.log_warn("MeCab の初期化に失敗しました: #{e.message}")
              Common.log_warn('MeCab がシステムにインストールされているか確認してください')
              Common.log_warn('macOS: brew install mecab mecab-ipadic')
              Common.log_warn('Ubuntu: sudo apt-get install mecab libmecab-dev mecab-ipadic-utf8')
              false
            end
          end

          private

          # MeCab インスタンスを取得
          def mecab
            @mecab ||= begin
              require 'natto'
              Natto::MeCab.new
            end
          end

          # カタカナをひらがなに変換
          # @param str [String] カタカナ文字列
          # @return [String] ひらがな文字列
          def katakana_to_hiragana(str)
            str.tr('ァ-ヶ', 'ぁ-ゖ')
          end
        end
      end
    end
  end
end
