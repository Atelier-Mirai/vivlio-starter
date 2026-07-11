# frozen_string_literal: true

require_relative 'html_replacer'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 旧 config/post_replace_list.yml の組み込み置換ルール。
      # 適用エンジンは HtmlReplacer（保護モード・退避機構）を共用する。
      #
      # 各ルールの正規表現は旧 YAML の `f` 文字列と source が一致するよう
      # %r{...}m で記述している（`/m` は旧実装の Regexp.new(str, MULTILINE) 相当）。
      # 置換文字列の `$1`〜`$9` はエンジン側 replace_with_captures が手動展開するため
      # そのまま維持する（Ruby の `\1` へ書き換えない）。
      module ReplacementRules
        module_function

        # 1 ルール。mode は旧 rule_mode の推定結果を明示化したもの:
        #   :text_only … <pre>/<code>/全タグを退避しテキストノードのみに適用
        #   :tag_aware … <pre> ブロックのみ退避して全体に適用
        Rule = Data.define(:pattern, :replacement, :mode)

        CONTAINER_RULES = [
          # :::{.class} 記法（Pandoc 拡張風）を <div class="..."> に変換（開始）。
          # 複数クラス {.a .b .c} にも対応（先頭の . は任意、以降の . は後段ルールで除去）。
          Rule.new(%r{:{3,}\s*\{\.?([a-z0-9.\-_\s]+)\}}m, '<div class="$1">', :text_only),
          # 複数クラス指定で残った " ." を " " に整理（最大 4 クラスまで対応するため 3 回）。
          Rule.new(%r{(<div class="[^"]*?) \.}m, '$1 ', :tag_aware),
          Rule.new(%r{(<div class="[^"]*?) \.}m, '$1 ', :tag_aware),
          Rule.new(%r{(<div class="[^"]*?) \.}m, '$1 ', :tag_aware),
          # ::: ブロック終端を </div> に変換（終了）。
          Rule.new(%r{:{3,}}m, '</div>', :text_only)
        ].freeze

        # <hr> を改ページ用の <hr class="pagebreak"> に。
        PAGEBREAK_RULES = [
          Rule.new(%r{<hr>}m, '<hr class="pagebreak">', :tag_aware)
        ].freeze

        # 縦方向の余白を符号付きで挿入。単位付き @vspace を先に適用する
        # （単位なしルールが先に走ると数値だけ拾って単位が残るため）。
        # @nega / @posi（後方互換別名）・@comment / @commend（編集者コメント）は廃止済み。
        SPACING_MACRO_RULES = [
          Rule.new(%r{@vspace:(-?[\d.]+(?:lh|rem|em|mm|cm|pt|px))}m, '<div style="margin-top:$1"></div>', :text_only),
          Rule.new(%r{@vspace:(-?[\d.]+)}m, '<div style="margin-top:$1mm"></div>', :text_only)
        ].freeze

        # リストの先頭記号を装飾クラスに（▶＝青コメ / 囲み数字＝赤コメ）。
        LIST_DECORATION_RULES = [
          Rule.new(%r{<li[^>]*>▶}m, '<li class="aokome">', :tag_aware),
          Rule.new(%r{<li[^>]*>([❶-❿⓫-⓴]+)}m, '<li class="akakome"><span>$1</span>', :tag_aware)
        ].freeze

        # コード見出し（h6）を装飾クラス付きに（span は Nokogiri の自動補完で閉じる）。
        CODE_HEADING_RULES = [
          Rule.new(%r{<h6([^>]*)>}m, '<h6$1 class="codetitle"><span>', :tag_aware)
        ].freeze

        # 〘〙 を <kbd>...</kbd> に。
        KBD_RULES = [
          Rule.new(%r{〘}m, '<kbd>', :text_only),
          Rule.new(%r{〙}m, '</kbd>', :text_only)
        ].freeze

        # p/div/svg/image/hr のねじれ修正と空段落除去（順序厳守・15 ルール）。
        # 後段ルールは前段の結果に依存するため並びを変えないこと。
        PARAGRAPH_CLEANUP_RULES = [
          # p が余分に div を囲っているのを除去（div 先頭を裸に）。
          Rule.new(%r{<p>(<div class="[^"]+">)</p>}m, '$1', :tag_aware),
          # p と div の並び修正。
          Rule.new(%r{<p></div></p>}m, '</div>', :tag_aware),
          Rule.new(%r{<p></div>}m, '</div>', :tag_aware),
          Rule.new(%r{</div></p>}m, '</div>', :tag_aware),
          # div の直後に余分な </p> が来た場合の修正。
          Rule.new(%r{(<div class="[^"]+">)</p>}m, '$1', :tag_aware),
          # <p>(<div ...>) の余分な p を除去（前後の空白・改行を許容）。
          Rule.new(%r{<p>\s*(<div class="[^"]+">)}m, '$1', :tag_aware),
          # hr の前後の余分な p / </p> を除去。
          Rule.new(%r{(<hr class="[^"]+">)</p>}m, '$1', :tag_aware),
          Rule.new(%r{<p>(<hr class="[^"]+">)}m, '$1', :tag_aware),
          # <svg> / <image> を p が囲っているだけの場合、p を除去。
          Rule.new(%r{<p>(<svg [^>]+>)</p>}m, '$1', :tag_aware),
          Rule.new(%r{<p>(<image [^>]+>)}m, '$1', :tag_aware),
          Rule.new(%r{(<image [^>]+>)</p>}m, '$1', :tag_aware),
          Rule.new(%r{<p>(</svg>)}m, '$1', :tag_aware),
          Rule.new(%r{(</svg>)</p>}m, '$1', :tag_aware),
          # 空段落を除去（素 / 空白 / nbsp・ゼロ幅・双方向制御記号のみ）。
          Rule.new(%r{<p></p>}m, '', :tag_aware),
          Rule.new(%r{<p>\s*</p>}m, '', :tag_aware),
          Rule.new(
            %r{<p>(?:\s|\u{00A0}|\u{200B}|\u{200C}|\u{200D}|\u{2060}|\u{FEFF}|\u{180E}|\u{200E}|\u{200F}|&nbsp;|&#160;|&#xA0;)*</p>}m,
            '', :tag_aware
          )
        ].freeze

        # 段落末の {.aki} / {.aki2} をクラス化。
        SPACING_CLASS_RULES = [
          Rule.new(%r{<p>((?:(?!</p>).)*?)\{\.aki\}\s*</p>}m, '<p class="aki">$1</p>', :tag_aware),
          Rule.new(%r{<p>((?:(?!</p>).)*?)\{\.aki2\}\s*</p>}m, '<p class="aki2">$1</p>', :tag_aware)
        ].freeze

        # 旧 yml の記載順そのまま（順序変更禁止: 後段ルールは前段の結果に依存する）。
        ALL = (CONTAINER_RULES + PAGEBREAK_RULES + SPACING_MACRO_RULES +
               LIST_DECORATION_RULES + CODE_HEADING_RULES +
               KBD_RULES + PARAGRAPH_CLEANUP_RULES + SPACING_CLASS_RULES).freeze

        # 組み込みルール一式を適用する（旧 process_html_file(file, yaml_rules) 相当）。
        # @return [Hash] { changed: Boolean, replacements: Integer }
        def apply_builtin!(html_file) = HtmlReplacer.process_html_file(html_file, ALL)
      end
    end
  end
end
