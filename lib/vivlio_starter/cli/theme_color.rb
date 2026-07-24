# frozen_string_literal: true

module VivlioStarter
  module CLI
    # ================================================================
    # テーマ・アクセント色の解決（色名/hex → リテラル hex）と混色。
    # ================================================================
    # パレットの正典は stylesheets/theme.css の --accent-*。本モジュールはその Ruby 側の写しで、
    # 2 つの用途で共用する:
    #   - Kindle 用リテラル焼き込み（KFX は var()/color-mix 非対応のため、book-settings.css に
    #     テーマ色を具体色で焼く。kindle-theme-color-literalize-spec.md）。
    #   - techbook の画像化アセットの色決定（Techbook::Processor#theme_color_hex）。
    # ================================================================
    module ThemeColor
      # パレット不明・空・不正値のフォールバック（theme.css の既定テーマ yellow）。
      DEFAULT = '#f0a000'

      # theme.css の --accent-* と一致させること（12 色）。
      PALETTE = {
        'yellow' => '#f0a000', 'orange' => '#ea580c', 'red' => '#dc2626',
        'magenta' => '#e11d48', 'purple' => '#7c3aed', 'indigo' => '#4f46e5',
        'navy' => '#1e40af', 'blue' => '#0ea5e9', 'cyan' => '#06b6d4',
        'teal' => '#0d9488', 'green' => '#16a34a', 'lime' => '#65a30d'
      }.freeze

      module_function

      # 色名 / hex（3・6・8 桁）/ 0x → hex 文字列。3 桁・8 桁はそのまま返す（techbook 互換）。
      # **解決不能（空・未知色名・注入文字列）は nil** を返す——呼び出し側が既定色や fallback を
      # 明示的に当てられるようにするため（to_hex6 の fallback を機能させる鍵）。
      def resolve(color)
        raw = color.to_s.strip.downcase
        return nil if raw.empty?
        return raw if raw.match?(/\A#(?:\h{3}|\h{6}|\h{8})\z/)
        return "##{raw}" if raw.match?(/\A(?:\h{3}|\h{6}|\h{8})\z/)
        return "##{raw.delete_prefix('0x')}" if raw.match?(/\A0x(?:\h{6}|\h{8})\z/)

        PALETTE[raw]
      end

      # Kindle リテラル用: 必ず #rrggbb（6 桁）へ正規化する。resolve 結果を 6 桁化し、
      # 解釈不能なら fallback（既定は DEFAULT）を 6 桁化して返す。book.yml 由来の不正値による
      # CSS 注入・構文破壊を構造的に防ぐ（戻り値は必ず /\A#\h{6}\z/）。
      # @return [String] "#rrggbb"
      def to_hex6(color, fallback: DEFAULT)
        normalize_hex6(resolve(color)) || normalize_hex6(resolve(fallback)) || DEFAULT
      end

      # #rgb → #rrggbb 展開・#rrggbbaa → #rrggbb 切詰（alpha 破棄）。それ以外は nil。
      def normalize_hex6(hex)
        body = hex.to_s.strip.delete_prefix('#')
        return nil unless body.match?(/\A(?:\h{3}|\h{6}|\h{8})\z/)

        case body.length
        when 3 then "##{body.chars.map { it * 2 }.join}"
        when 6 then "##{body}"
        when 8 then "##{body[0, 6]}"
        end
      end

      # WCAG の相対輝度（0.0〜1.0）。地色の明るさに応じて載せる文字色を白/黒へ
      # 切り替えるために使う（簡易アバターの自動生成・talk-auto-avatar-spec.md §2.2）。
      # @param hex6 [String] "#rrggbb"（to_hex6 の出力）
      def luminance(hex6)
        channels = hex6.delete_prefix('#').scan(/../).map { it.to_i(16) / 255.0 }
        linear = channels.map { it <= 0.03928 ? it / 12.92 : (((it + 0.055) / 1.055)**2.4) }
        (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2])
      end

      # accent を白と混色して #rrggbb を返す（ratio = accent の割合・0.0〜1.0）。
      # KFX は color-mix() 非対応のため、CSS の color-mix(in srgb, accent R%, white) を事前計算する。
      # @param hex6 [String] "#rrggbb"（to_hex6 の出力）
      def mix_with_white(hex6, ratio)
        rgb = hex6.delete_prefix('#').scan(/../).map { it.to_i(16) }
        mixed = rgb.map { ((it * ratio) + (255 * (1.0 - ratio))).round.clamp(0, 255) }
        format('#%02x%02x%02x', *mixed)
      end
    end
  end
end
