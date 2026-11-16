# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/values.rb
# ================================================================
# 責務:
#   テーマのオプションの値を、宣言（type:・default:・default_from:・min:・max:・unit:）から読み、
#   CSS へ書く形にする（theme-contract-spec.md §3.3）。
#
# 値の決まり方:
#   book.yml に書いた値が読めればそれ、空欄か読めなければ default_from: の先のオプションの値、
#   それも無ければ default:。読めない値の 🟡 は PreProcessCommands::ThemeValidator が一度だけ出す
#   （ここは章ごとに呼ばれるので知らせない）。
# ================================================================

require_relative '../theme_color'
require_relative '../units'

module VivlioStarter
  module CLI
    module Theme
      # オプションの値の読み方と書き方
      module Values
        # 色: HEX（#・0x・裸の 3/6/8 桁）
        HEX = /\A(?:#|0x)?(\h{3}|\h{6}|\h{8})\z/i

        # 色: 公開する 12 色を指す var()（配色のテーマの tokens: が書く形）
        ACCENT_VAR = /\Avar\(--book-accent-([a-z]+)\)\z/

        # 数: 数だけか、単位を付けた数（unit: と同じ単位だけ。倍率は em）
        NUMBER = /\A(\d+(?:\.\d+)?)([a-z%]*)\z/i

        module_function

        # book.yml の theme: の下に書いた値（空欄は nil）
        # @param theme_cfg [Data, Hash, nil] CONFIG.theme
        # @param option [Option]
        def written(theme_cfg, option)
          raw = option.path.reduce(theme_cfg) do |node, key|
            node.respond_to?(:to_h) && !node.is_a?(String) ? node.to_h[key] : nil
          end
          raw.to_s.strip.empty? ? nil : raw
        end

        # 書いた値を宣言で読む
        # @return [Array(Object, Symbol)] [読んだ値, 直した理由]。理由は nil（そのまま）・:too_small・
        #   :too_large（端へ寄せた）・:invalid（読めない）・:length（倍率の数に長さを書いた）
        def parse(option, raw)
          text = raw.to_s.strip
          case option.type
          when 'color' then color?(text) ? [text, nil] : [nil, :invalid]
          when 'number' then parse_number(option, text, option.unit)
          when 'ratio' then parse_number(option, text, 'em')
          when 'enum'
            value = text.downcase
            option.values.include?(value) ? [value, nil] : [nil, :invalid]
          else [raw, nil]
          end
        end

        # 今の設定でのオプションの値（読んだ後の形。色は書いた字、数は Float）
        # @param options [Array<Option>] default_from: の先を探す並び
        def effective(option, theme_cfg, options)
          raw = written(theme_cfg, option)
          value, = parse(option, raw) unless raw.nil?
          return value unless value.nil?

          if option.default_from
            source = options.find { it.path == [option.default_from.to_sym] }
            return effective(source, theme_cfg, options) if source
          end
          option.default.nil? ? nil : parse(option, option.default).first
        end

        # CSS の値へ書く。倍率は百分率にする（1.2 → 120%）。字の大きさの倍率を em で書くと、Vivliostyle が
        # px に直すときに丸め、両端揃えの字の位置がずれる（% はずれない。theme-contract-spec.md §3.4 の決め 3）
        def css(option, value)
          case option.type
          when 'color' then css_color(value.to_s)
          when 'number' then "#{format_number(value)}#{option.unit}"
          when 'ratio' then "#{format_number(value.to_f * 100)}%"
          when 'string' then %("#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
          else value.to_s
          end
        end

        # 色の名前・HEX・12 色の var() のどれか
        def color?(text)
          t = text.downcase
          ThemeColor::PALETTE.key?(t) || t.match?(HEX) || t.match?(ACCENT_VAR)
        end

        # 12 色は var(--book-accent-<名前>) に、HEX は # 付きの小文字にする
        def css_color(text)
          t = text.strip.downcase
          if ThemeColor::PALETTE.key?(t) then "var(--book-accent-#{t})"
          elsif (m = t.match(HEX)) then "##{m[1]}"
          else t
          end
        end

        # 数を読み、min:・max: の外は端へ寄せる。unit: のある数は、その単位を付けて書いてもよい。
        # 倍率（ratio）は em を付けてよい（`1.2` と `1.2em` は同じ）。ほかの単位の長さ（12pt）は :length
        def parse_number(option, text, unit)
          m = text.match(NUMBER)
          return [nil, :invalid] unless m
          unless m[2].empty? || m[2].casecmp?(unit.to_s)
            return [nil, Units.length_to_mm(text) ? :length : :invalid]
          end

          number = m[1].to_f
          if option.min && number < option.min then [option.min.to_f, :too_small]
          elsif option.max && number > option.max then [option.max.to_f, :too_large]
          else [number, nil]
          end
        end

        # 末尾の 0 を落とす（1.20 → 1.2 / 36.0 → 36）
        def format_number(value)
          rounded = value.to_f.round(2)
          rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end
      end
    end
  end
end
