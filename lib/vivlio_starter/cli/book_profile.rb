# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/book_profile.rb
# ================================================================
# 責務:
#   本の種類（book.type）ごとの、設定の既定値の組（v2-architecture-spec.md §2.2）
#
# 種類は「軸と機能の既定値の組」であって、コードの分岐の材料ではない。種類を読んでよいのは
# Common.load_config（ここの表を重ねる）・vs new・著者向けの表示だけで（同 §2.3）、
# ほかのコードは軸（BookTraits）か機能のキーを読む。book_type_usage_test.rb が見張る。
# ================================================================

require_relative 'config_keys'

module VivlioStarter
  module CLI
    # 本の種類ごとの、設定の既定値の組
    module BookProfile
      # 種類ごとに、ConfigKeys の既定値と違うキーだけを書く。
      #
      # 載せるのは ConfigKeys::KEYS にあるキーだけ（book_profile_test.rb が検査する）。
      # テーマの名前（theme.name）は S6、小説と絵本の判型のプリセット（page.use）は S8 で足す
      # （v2-architecture-spec.md §8 の S5 の決め 1）。
      PROFILES = {
        techbook: {},
        novel: {
          %i[page writing_mode]      => 'vertical',
          %i[page heading_numbering] => 'none',
          %i[index_glossary enabled] => false,
          %i[lint ruleset]           => 'novel',
          %i[metrics use]            => 'none',
          %i[notation web_novel]     => true
        },
        picture_book: {
          %i[page layout]            => 'fixed',
          %i[page heading_numbering] => 'none',
          %i[index_glossary enabled] => false,
          %i[lint ruleset]           => 'minimal',
          %i[metrics use]            => 'none'
        }
      }.freeze

      # book.type を書かなかった本（1.x の本）の種類
      DEFAULT_TYPE = ConfigKeys::KEYS.fetch(%i[book type]).default.to_sym

      module_function

      # 種類の名前の一覧（著者への案内と検査に使う）
      def types = PROFILES.keys

      # book.yml の生の値から、種類を決める。書かなければ techbook。
      #
      # 知らない名前も techbook として組み、名前の誤りは組み合わせの検査（vs build・vs preflight）が
      # 🔴 で示す。ここで止めないのは、設定の読み込みはモジュールの読み込みのときに走り、
      # 止めると vs doctor も vs upgrade も起動できなくなるためである
      #
      # @param raw [Hash] book.yml を読んだそのままのハッシュ（シンボルのキー）
      # @return [Symbol]
      def type_of(raw)
        name = written_type(raw)
        return DEFAULT_TYPE if name.empty?

        PROFILES.key?(name.to_sym) ? name.to_sym : DEFAULT_TYPE
      end

      # book.yml に書かれた book.type の字（書かなければ空）。名前の誤りを示すときにも使う
      #
      # @param raw [Hash] book.yml を読んだそのままのハッシュ
      # @return [String]
      def written_type(raw)
        book = raw.is_a?(Hash) ? raw[:book] : nil
        book.is_a?(Hash) ? book[:type].to_s.strip : ''
      end

      # 読み込んだ設定の book.type が知らない名前なら、その字を返す（正しければ nil）。
      # 組み合わせの検査（Guards::TraitCombinationCheck）が、名前の誤りを示すのに使う
      #
      # @param config [Data, nil] Common::CONFIG
      # @return [String, nil]
      def unknown_type(config)
        name = config&.book&.type.to_s.strip
        name unless name.empty? || PROFILES.key?(name.to_sym)
      end

      # 種類の既定値を、book.yml と同じ入れ子のハッシュにして返す

      #
      # @param type [Symbol]
      # @return [Hash]
      def defaults_for(type)
        PROFILES.fetch(type).each_with_object({}) do |(path, value), tree|
          *parents, leaf = path
          parents.reduce(tree) { |node, key| node[key] ||= {} }[leaf] = value
        end
      end
    end
  end
end
