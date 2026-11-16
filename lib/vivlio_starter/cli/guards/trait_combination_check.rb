# frozen_string_literal: true

require_relative '../theme'
require_relative '../build/targets'

module VivlioStarter
  module CLI
    module Guards
      # 本の種類と軸（組方向・レイアウト）の値と、その組み合わせを検査する
      # （v2-architecture-spec.md §2.5）。vs build と vs preflight の入口で同じものを走らせる。
      #
      # 設定の読み込みは、知らない値を既定として読んで止めない（vs doctor・vs upgrade を
      # 起動できるようにするため）。値の誤りを著者に示すのは、この検査である。
      class TraitCombinationCheck < BaseCheck
        # 著者に示す軸の値の名前（テーマの supports: の検査）
        VALUE_LABELS = {
          writing_mode: { horizontal: '横書き', vertical: '縦書き' },
          layout: { reflowable: 'リフロー', fixed: '固定レイアウト' },
          targets: { pdf: '閲覧用 PDF', print_pdf: '印刷用 PDF', epub: 'EPUB', kindle: 'Kindle' }
        }.freeze

        # @param config [Data, nil] 検査する設定（既定: Common::CONFIG）
        # @param root [String] 本のルート（テーマを探す）
        # @param bundled_root [String] 同梱のテーマの置き場（対応するテーマの名前を示す）
        def initialize(config: Common::CONFIG, root: Dir.pwd, bundled_root: Theme::BUNDLED_ROOT)
          @config = config
          @root = root
          @bundled_root = bundled_root
          super()
        end

        # @return [Array<Violation>]
        def validate
          return [] unless @config

          # 固定レイアウトを 🔴 で止めている間は、索引の 🟡 を重ねない（組めない本に、次の直しを示さない）。
          # S9 で fixed_layout を外すと、🟡 が出るようになる
          [unknown_type, unknown_value(:writing_mode, BookTraits::WRITING_MODES),
           unknown_value(:layout, BookTraits::LAYOUTS), fixed_layout || fixed_layout_with_index,
           *theme_violations].compact
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
        # テーマが読めない（無い・壊れている・契約の版が合わない）なら 🔴 だけを出す。
        # 読めたら、知らないキーの 🟡 と、テーマが対応しない組方向・レイアウト・出力先の 🔴
        # （v2-architecture-spec.md §2.5）。固定レイアウトは上で止めているので、レイアウトは重ねない
        def theme_violations
          theme = Theme.resolve(Theme.selected_name(@config), root: @root)
          [*theme.warnings.map { warning(it) },
           unsupported(theme, :writing_mode, [traits.writing_mode], 'page.writing_mode'),
           (unsupported(theme, :layout, [traits.layout], 'page.layout') unless traits.fixed?),
           unsupported(theme, :targets, Build::Targets.resolve(@config).to_h.filter_map { |target, on| target if on }, 'output.targets')]
        rescue Theme::Error => e
          [error(e.message, detail: e.detail)]
        end

        # @param values [Array<Symbol>] 本が求める値（出力先は複数）
        def unsupported(theme, axis, values, key)
          missing = values - theme.supports.fetch(axis)
          return if missing.empty?

          value = missing.first
          label = VALUE_LABELS.fetch(axis).fetch(value)
          error("テーマ #{theme.name} は#{label}（#{key}: #{value}）に対応していません",
                detail: [alternatives(theme, axis, value, label), *("#{key} から #{value} を外すと組めます" if axis == :targets)])
        end

        # 対応するテーマを、本の themes/ と同梱のテーマから探して示す
        def alternatives(theme, axis, value, label)
          names = Theme.available(root: @root, bundled_root: @bundled_root)
                       .select { |name, found| name != theme.name && found.supports.fetch(axis).include?(value) }.keys.sort
          return "#{label}に対応するテーマは、まだ同梱されていません" if names.empty?

          "#{label}に対応するテーマ: #{names.join('・')}（config/book.yml の theme.name に書きます）"
        end

      end
    end
  end
end
