# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/yomi_inferrer.rb
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
require_relative 'yomi_overrides'

module VivlioStarter
  module CLI
    module IndexCommands
      # MeCab による読み推測クラス
      class YomiInferrer
        def initialize
          @mecab = nil # 上位 NBEST 通りの解析を返す MeCab
          @available = nil
        end

        # テキストの読みを推測
        # @param text [String] 読みを推測するテキスト
        # @return [String] ひらがなの読み（推測できない場合は元のテキスト）
        def infer(text)
          # 読みの個人辞書（import で蓄積）を MeCab より優先する。
          override = overrides[text]
          return override if override

          return text unless available?

          nodes = plausible_analysis(text)
          result = join_readings(nodes.map { |surface, features, spaced| [reading_of(surface, features), spaced] })
          result.empty? ? text : result
        end

        # MeCab が利用可能かどうか
        # book.yml の index_glossary.use_mecab: false は「導入済みでも使わない」という
        # 著者の明示的な選択なので、導入案内の警告は出さずに静かに無効化する
        def available?
          return @available unless @available.nil?
          return @available = false if Common::CONFIG&.index_glossary&.use_mecab == false

          @available = begin
            require 'natto'
            # MeCab の初期化を試行
            @mecab = Natto::MeCab.new(nbest: NBEST)
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

        # MeCab に出させる解析の数
        NBEST = 5

        # 索引語の読みとしてありそうにない解析の印（品詞・細分類）。
        # 語だけを解析にかけると、短い漢語は人名や動詞として読まれやすい
        # （「全章」＝全〈チョン・姓〉＋章〈アキラ・名〉、「誤認識」＝誤〈誤る〉＋認識）。
        # 「章」は「章扉」「章番号」「単章ビルド」でもアキラと読まれていた（改善案 #99）
        UNLIKELY = ->(features) { features[2] == '人名' || features[0] == '動詞' }

        # 語の解析。上位 NBEST 通りのうち、人名・動詞を含まず、漢字の語にはどれも読みがある
        # 最初の解析を採る。見つからなければ最良の解析を使う（従来どおり）。英字やカタカナの
        # 未知語（「ビルド」）は読みがなくても表層形で読めるので、条件に含めない。
        # @return [Array<Array(String, Array<String>, Boolean)>] [表層形, 素性, 直前に空白があったか] の並び
        def plausible_analysis(text)
          analyses = [[]]
          mecab.parse(text) do |node|
            # 3 つめは直前に空白があったか（rlength は前の空白を含む長さ）
            node.is_eos? ? analyses << [] : analyses.last << [node.surface, node.feature.split(','), node.rlength > node.length]
          end
          analyses.reject!(&:empty?)
          analyses.find { |nodes| nodes.none? { |_, f| UNLIKELY.(f) } && nodes.all? { |s, f| readable?(s, f) } } ||
            analyses.first || []
        end

        # 語の読みをつなぐ。語の空白は、どちらかの側の読みに英字が残るときだけ残す。
        # 英字の語は綴りがそのまま読みになるので、空白を落とすと「fancy list」が「fancylist」、
        # 「Re:VIEW Starter」が「Re:VIEWStarter」になり、索引の並びも「fancy」で始まるほかの
        # 語との前後が変わる（改善案 #99）。仮名どうしの間は、仮名の読みの慣習どおり詰める。
        # @param parts [Array<Array(String, Boolean)>] [読み, 直前に空白があったか]
        def join_readings(parts)
          parts.each_with_index.map do |(reading, spaced), i|
            next reading unless i.positive? && spaced && [parts[i - 1][0], reading].any? { it.match?(/[A-Za-z0-9]/) }

            " #{reading}"
          end.join
        end

        # 素性に読みがあるか（feature の 8 番目 = カタカナ読み）
        def reading?(features) = features.size > 7 && !['*', ''].include?(features[7])

        # 読みを表層形で済ませられない（漢字を含むのに読みがない）語でないか
        def readable?(surface, features) = reading?(features) || !surface.match?(/\p{Han}/)

        # 1 語の読み。読みが取れない語（英字・未知語）は表層形のまま
        def reading_of(surface, features) = reading?(features) ? katakana_to_hiragana(features[7]) : surface

        # 読みの個人辞書（config/index_yomi_overrides.yml）を一度だけ読み込む。
        def overrides = @overrides ||= YomiOverrides.load

        # MeCab インスタンスを取得
        def mecab
          @mecab ||= begin
            require 'natto'
            Natto::MeCab.new(nbest: NBEST)
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
