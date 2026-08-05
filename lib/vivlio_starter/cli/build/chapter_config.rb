# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/chapter_config.rb
# ================================================================
# 責務:
#   book.yml の chapters に書かれた章番号の指定を解釈し、HTML を絞り込む。
#
# 章番号形式:
#   - 単一: "11" → [11]
#   - 範囲: "11-13" → [11, 12, 13]
#   - カンマ区切り: "11, 13, 15" → [11, 13, 15]
#   - 混合: "11-13, 91" → [11, 12, 13, 91]
#
# 「番号指定の綴り」を読むのはここが唯一の定義元である。
# 綴りが同型の実装が他に 2 つあるが、担うものが違うので寄せていない:
#   - CatalogLoader.parse_shorthand_to_numbers … catalog.yml のショートハンド。
#     区切りに空白も許し、数字以外は黙って捨てる（カタログは著者が並べる表なので、
#     読めない行で全体を止めない）
#   - TokenResolver::Resolver#normalize … CLI 引数。番号だけでなくスラグ・パスも
#     受け、返すのは Integer ではなくゼロ埋めトークン
# ================================================================

module VivlioStarter
  module CLI
    module Build
      # 章番号パース・ファイル解決モジュール
      module ChapterConfig
        # 番号指定の 1 要素。単一（"11"）と範囲（"11-13"）を 1 本で受ける。
        NUMBER_OR_RANGE = /\A(\d+)(?:-(\d+))?\z/

        module_function

        # 章の指定文字列を章番号の配列にする。
        # 例: "02, 11-13, 91" → [2, 11, 12, 13, 91]
        #
        # **数字と範囲だけで構成されていなければ nil を返す。** `chapters` には
        # "11-install" のようなファイルベース名も書けるので、呼び出し側は nil を
        # 「番号指定ではない」の合図として別の解釈へ進む。判定と展開を 1 本にまとめて
        # あるのは、呼び出し側が同じ綴りをもう一度走査せずに済ませるためである。
        #
        # 逆順の範囲（"13-11"）はその部分だけ落とす。展開すると著者が書いた向きと
        # 逆の章立てが黙ってできあがるため。
        # @param str [String, nil]
        # @return [Array<Integer>, nil] 番号指定でなければ nil
        def parse_chapter_numbers_from_string(str)
          parts = str.to_s.split(',').map(&:strip).reject(&:empty?)
          matched = parts.map { it.match(NUMBER_OR_RANGE) }
          return nil if matched.any?(&:nil?)

          matched.flat_map do |m|
            first = m[1].to_i
            last = m[2]&.to_i || first
            first <= last ? (first..last).to_a : []
          end.uniq.sort
        end

        # ディレクトリ内の *.html から、章番号レンジと keep_numbers でフィルタ
        # 注: アンダースコア始まりのファイルは \A(\d+)- パターンにマッチしないため自動的に除外される
        def htmls_for_range(base_dir, range, keep_numbers = nil)
          Dir.glob(File.join(base_dir, '*.html')).select do |path|
            bn = File.basename(path, '.html')
            n = bn[/\A(\d+)-/, 1]&.to_i
            n && range.include?(n) && (keep_numbers.nil? || keep_numbers.include?(n))
          end.sort
        end
      end
    end
  end
end
