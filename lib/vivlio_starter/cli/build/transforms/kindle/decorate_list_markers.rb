# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/decorate_list_markers.rb
# ================================================================
# 責務:
#   箇条書きの印・番号を、実体の字で入れる
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 箇条書きの印・番号を、実体の字で入れる
      module Transforms::Kindle::DecorateListMarkers
        module_function

        # fancy list / outline-list のマーカーを実体注入する（nested-list-notation-spec.md §6.1）。
        # Kindle(KFX) は ::before をルールごと破棄するため、括弧付きマーカー・複合番号が
        # 不可視になる。<ol type> 属性の KFX 挙動も未実測のため、安全側で全 fancy 様式＋
        # outline-list を単一の注入機構で統一する。クリーン EPUB・PDF には注入しない
        # （Kindle 専用フェーズからのみ呼ばれる）。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = inject_fancy_list_markers!(doc)
            changed |= inject_outline_list_markers!(doc)
            changed |= textify_task_list_checkboxes!(doc)
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のリストへ実体マーカーを注入しました")
          end
          html_files
        end

        # タスクリストのチェックボックスを文字へ落とす（Kindle 専用）。
        #
        # KFX は ::before も appearance も解さないので、CSS で描いた枠が消えて
        # 「印の無い箇条書き」になる。実体の文字へ差し替えて意味を残す。
        #
        # **☑ ☐ を使わない。** 同梱の本文書体 7 種のいずれにも無く（HackGen だけが
        # 持つ）、使うとコード書体か OS 書体へ落ちて Type 3 混入の経路になる
        # （type3-font-embedding-notes.md §8）。□ ■ は全書体にある。
        # 仕様: markdown-notation-collision-spec.md §4
        TASK_CHECKBOX_GLYPHS = { checked: '■', unchecked: '□' }.freeze

        def textify_task_list_checkboxes!(doc)
          changed = false
          doc.css('li.task-list-item > input[type="checkbox"]').each do |input|
            glyph = input['checked'] ? TASK_CHECKBOX_GLYPHS[:checked] : TASK_CHECKBOX_GLYPHS[:unchecked]
            span = doc.create_element('span')
            span['class'] = 'vs-task-mark'
            span.content = glyph
            input.replace(span)
            changed = true
          end
          changed
        end

        # 前処理が付与したクラス名（vs-list-<様式>[-paren|-paren2]）の解析パターン
        FANCY_LIST_CLASS_PATTERN =
          /\bvs-list-(decimal|lower-alpha|upper-alpha|lower-roman|upper-roman)(-paren2|-paren)?\b/

        # ol.vs-fancy-list の各直下 li 先頭へ様式どおりのマーカー文字列を注入する。
        # 開始値は start 属性（無ければ 1）から復元する。
        def inject_fancy_list_markers!(doc)
          changed = false
          doc.css('ol.vs-fancy-list').each do |ol|
            style, separator = fancy_style_from_class(ol['class'])
            next unless style

            number = (ol['start'] || 1).to_i
            ol.xpath('./li').each do |li|
              changed |= inject_li_marker!(doc, li, fancy_marker_text(style, separator, number))
              number += 1
            end
          end
          changed
        end

        # div.outline-list 内の ol ツリーへ複合番号を注入する（ul は素通し）。
        # 番号表記は PDF / クリーン EPUB の CSS `counters(vs-outline, ".") ". "` と揃える
        # （トップ「1. 」・ネスト「1.1. 」）。
        def inject_outline_list_markers!(doc)
          changed = false
          doc.css('div.outline-list').each do |container|
            container.xpath('.//ol[not(ancestor::ol) and not(ancestor::ul)]').each do |ol|
              changed |= inject_outline_numbers!(doc, ol, [])
            end
          end
          changed
        end

        # クラス名から fancy の様式・区切りを復元する（[様式 Symbol, 区切り Symbol] or nil）
        def fancy_style_from_class(class_attr)
          m = class_attr.to_s.match(FANCY_LIST_CLASS_PATTERN)
          return nil unless m

          separator = { '-paren' => :paren, '-paren2' => :paren2 }.fetch(m[2], :period)
          [m[1].tr('-', '_').to_sym, separator]
        end

        # マーカー文字列（`C. ` / `iv) ` / `(2) ` 等・末尾半角スペース込み）
        def fancy_marker_text(style, separator, number)
          digits = fancy_number_text(style, number)
          case separator
          when :paren2 then "(#{digits}) "
          when :paren  then "#{digits}) "
          else "#{digits}. "
          end
        end

        # 整数を様式の数字表現へ（英字は a..z の 26 個まで・範囲超過は数字のままフォールバック）
        def fancy_number_text(style, number)
          case style
          in :lower_alpha if number.between?(1, 26) then (96 + number).chr
          in :upper_alpha if number.between?(1, 26) then (64 + number).chr
          in :lower_roman if number.positive? then integer_to_roman(number).downcase
          in :upper_roman if number.positive? then integer_to_roman(number)
          else number.to_s
          end
        end

        # 整数→ローマ数字（大文字）。減算表記（IV / IX / XL …）対応。
        ROMAN_PAIRS = [[1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'], [100, 'C'], [90, 'XC'],
                       [50, 'L'], [40, 'XL'], [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']].freeze

        def integer_to_roman(number)
          result = +''
          remainder = number
          ROMAN_PAIRS.each do |value, letters|
            count, remainder = remainder.divmod(value)
            result << letters * count
          end
          result
        end

        # ol の各 li に複合番号（prefix + 連番）を注入し、直下の ol へ再帰する
        def inject_outline_numbers!(doc, ol, prefix)
          changed = false
          number = 1
          ol.xpath('./li').each do |li|
            path = prefix + [number]
            changed |= inject_li_marker!(doc, li, "#{path.join('.')}. ")
            li.xpath('./ol').each { changed |= inject_outline_numbers!(doc, it, path) }
            number += 1
          end
          changed
        end

        # li 先頭へ <span class="vs-li-marker"> を注入する。ルーズ形式（li 直下が <p>）は
        # 最初の <p> の内側へ入れ、マーカーが独立行にならないようにする。
        # 注入済みならスキップ（vs-adm-label の二重注入防止と同じ流儀・冪等）。
        def inject_li_marker!(doc, li, marker_text)
          return false if li.at_xpath("./span[@class='vs-li-marker'] | ./p/span[@class='vs-li-marker']")

          span = Nokogiri::XML::Node.new('span', doc)
          span['class'] = 'vs-li-marker'
          span.content = marker_text
          first_element = li.element_children.first
          target = first_element&.name == 'p' ? first_element : li
          target.prepend_child(span)
          true
        end
      end
    end
  end
end
