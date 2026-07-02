# frozen_string_literal: true

module VivlioStarter
  module CLI
    # 印刷単位の変換定数と長さパーサを一元管理する。
    # 基準は「1 inch = 25.4mm = 72pt」「1Q = 0.25mm」の 2 関係のみで、
    # 他の係数はすべてここから導出する（近似値の直書きを排除するため）。
    # 仕様: docs/specs/page-unit-conversion-spec.md
    module Units
      MM_PER_INCH = 25.4
      PT_PER_INCH = 72.0
      MM_PER_PT   = MM_PER_INCH / PT_PER_INCH   # 0.3527777…
      PT_PER_MM   = PT_PER_INCH / MM_PER_INCH   # 2.8346456…
      MM_PER_Q    = 0.25
      PT_PER_Q    = MM_PER_Q * PT_PER_MM        # 0.7086614…

      module_function

      # CSS 長さ文字列を mm の Float へ変換する。
      # 受理: mm / cm / in / pt / Q（大文字小文字不問）、単位なしの数値（mm とみなす）。
      # 解釈できない値（em・% など文脈依存の単位や非数値）は nil を返し、
      # 既定値の選択は呼び出し側に委ねる（黙って 0 扱いにしない）。
      # @param value [Object] CSS 長さ（例: '22mm', '10pt', '88Q', 22）
      # @return [Float, nil]
      def length_to_mm(value)
        s = value.to_s.strip
        case s
        in '' then nil
        in /\A(-?[\d.]+)\s*mm\z/i then Regexp.last_match(1).to_f
        in /\A(-?[\d.]+)\s*cm\z/i then Regexp.last_match(1).to_f * 10.0
        in /\A(-?[\d.]+)\s*in\z/i then Regexp.last_match(1).to_f * MM_PER_INCH
        in /\A(-?[\d.]+)\s*pt\z/i then Regexp.last_match(1).to_f * MM_PER_PT
        in /\A(-?[\d.]+)\s*q\z/i  then Regexp.last_match(1).to_f * MM_PER_Q
        in /\A-?[\d.]+\z/         then s.to_f
        else nil
        end
      end

      # 文字サイズを正規単位 pt の文字列へ変換する。
      # Q → pt 変換、素の数値 → 'pt' 付与（CSS 不正値の予防）、pt はそのまま。
      # それ以外（px / em 等）は CSS として有効な可能性があるため素通しする。
      # @param value [Object] 文字サイズ（例: '10pt', '24Q', 10.5）
      # @return [String, nil] 'Xpt' 形式など。value が nil/空なら nil
      def font_size_to_pt(value)
        s = value.to_s.strip
        case s
        in '' then nil
        in /\A[\d.]+\s*q\z/i then format_pt(s.to_f * PT_PER_Q)
        in /\A[\d.]+\z/      then format_pt(s.to_f)
        else s
        end
      end

      # pt 文字列から数値部を取り出す（'10.5pt' → 10.5、pt 以外は nil）
      def pt_value(value) = value&.to_s&.strip&.match(/\A([\d.]+)\s*pt\z/i)&.[](1)&.to_f

      # pt 数値を CSS 値文字列へ整形（小数 3 桁丸め。17.0 → '17.0pt'）
      def format_pt(value) = "#{value.to_f.round(3)}pt"
    end
  end
end
