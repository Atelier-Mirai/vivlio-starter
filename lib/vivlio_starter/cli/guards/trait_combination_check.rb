# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 本の種類と軸（組方向・レイアウト）の値と、その組み合わせを検査する
      # （v2-architecture-spec.md §2.5）。vs build と vs preflight の入口で同じものを走らせる。
      #
      # 設定の読み込みは、知らない値を既定として読んで止めない（vs doctor・vs upgrade を
      # 起動できるようにするため）。値の誤りを著者に示すのは、この検査である。
      class TraitCombinationCheck < BaseCheck
        # @param config [Data, nil] 検査する設定（既定: Common::CONFIG）
        def initialize(config: Common::CONFIG)
          @config = config
          super()
        end

        # @return [Array<Violation>]
        def validate
          return [] unless @config

          # 固定レイアウトを 🔴 で止めている間は、索引の 🟡 を重ねない（組めない本に、次の直しを示さない）。
          # S9 で fixed_layout を外すと、🟡 が出るようになる
          [unknown_type, unknown_value(:writing_mode, BookTraits::WRITING_MODES),
           unknown_value(:layout, BookTraits::LAYOUTS), fixed_layout || fixed_layout_with_index].compact
        end

        private

        def traits = @traits ||= BookTraits.resolve(@config)

        def unknown_type
          name = BookProfile.unknown_type(@config) or return

          error("config/book.yml の book.type に、知らない種類が書かれています: #{name}",
                detail: "書ける値: #{BookProfile.types.join('・')}")
        end

        # @param key [Symbol] page の下のキー
        # @param known [Array<Symbol>] 有効な値
        def unknown_value(key, known)
          raw = @config.dig(:page, key).to_s.strip
          return if raw.empty? || known.any? { it.to_s == raw.downcase }

          error("config/book.yml の page.#{key} に、知らない値が書かれています: #{raw}",
                detail: "書ける値: #{known.join('・')}")
        end

        # 固定レイアウトの経路は S9 で作る。無いまま組むとリフローの段が走り、壊れた本ができる
        # （v2-architecture-spec.md §8 の S5 の決め 2）。S9 で外す
        def fixed_layout
          return unless traits.fixed?

          error('固定レイアウト（page.layout: fixed）の本は、この版ではまだ組めません',
                detail: 'config/book.yml の page.layout を reflowable にしてください' \
                        "（book.type: picture_book の既定も fixed です）")
        end

        def fixed_layout_with_index
          return unless traits.fixed? && Common.truthy?(@config.dig(:index_glossary, :enabled))

          warning('固定レイアウトの本では、索引と用語集のページを作りません',
                  detail: 'config/book.yml の index_glossary.enabled を false にしてください')
        end
      end
    end
  end
end
