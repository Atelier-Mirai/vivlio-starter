# frozen_string_literal: true

# ================================================================
# Class: GlossaryPageBuilder
# ----------------------------------------------------------------
# 責務:
#   glossary_terms.yml から _glossarypage.html を生成
#   用語集ページの HTML 出力を担当
#
# 主要メソッド:
#   - build!: 用語集ページを生成
#   - glossary_enabled?: 用語集機能が有効か
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'
require_relative 'glossary_terms_manager'

module Vivlio
  module Starter
    module CLI
      # 用語集ページを生成するクラス
      class GlossaryPageBuilder
        GLOSSARY_FILE = 'config/glossary_terms.yml'
        OUTPUT_FILE = '_glossarypage.html'

        def initialize
          @config = load_glossary_config
          @terms_manager = GlossaryTermsManager.new
        end

        # 用語集ページを生成
        # @return [String, nil] 出力ファイルパス、または nil（用語がない場合）
        def build!
          terms = @terms_manager.load_existing_terms
          
          if terms.empty?
            Common.log_info('用語集に登録された用語がありません')
            # 以前のビルドで生成された _glossarypage.html が残っている場合は削除
            cleanup_stale_glossary_page!
            return nil
          end

          # 読み順でソート
          sorted_terms = terms.sort_by { it['yomi'] || it['term'] }

          # HTML 生成
          html = build_html(sorted_terms)
          File.write(OUTPUT_FILE, html, encoding: 'utf-8')

          Common.log_success("用語集ページを生成しました: #{OUTPUT_FILE}")
          OUTPUT_FILE
        end

        # 用語集機能が有効か
        # @return [Boolean]
        def glossary_enabled?
          @config[:enabled] == true
        end

        private

        # 以前のビルドで残った _glossarypage.html を削除
        def cleanup_stale_glossary_page!
          return unless File.exist?(OUTPUT_FILE)

          FileUtils.rm_f(OUTPUT_FILE)
          Common.log_info("用語集が空のため #{OUTPUT_FILE} を削除しました")
        end

        # 設定を読み込み
        def load_glossary_config
          glossary = Common::CONFIG.glossary
          glossary.respond_to?(:to_h) ? glossary.to_h : (glossary || {})
        rescue StandardError
          {}
        end

        # HTML を構築
        def build_html(terms)
          title = @config[:title] || '用語集'
          
          <<~HTML
            <!DOCTYPE html>
            <html lang="ja">
            <head>
              <meta charset="UTF-8">
              <title>#{title}</title>
              <link rel="stylesheet" href="stylesheets/glossary.css">
            </head>
            <body class="glossary-page">
              <section class="glossarypage" role="doc-glossary">
                <h1 class="glossary-title">#{title}</h1>
                <dl class="glossary-list">
                  #{build_term_entries(terms)}
                </dl>
              </section>
            </body>
            </html>
          HTML
        end

        # 用語エントリを構築
        def build_term_entries(terms)
          # 読みの先頭文字でグループ化
          grouped = group_by_initial(terms)

          entries = []
          grouped.each do |initial, group_terms|
            entries << build_group_header(initial)
            group_terms.each { entries << build_term_entry(it) }
          end

          entries.join("\n")
        end

        # 読みの先頭文字でグループ化
        def group_by_initial(terms)
          terms.group_by do |term|
            yomi = term['yomi'] || term['term']
            normalize_initial(yomi)
          end.sort.to_h
        end

        # 先頭文字を正規化（ひらがな/カタカナ→行に変換）
        # カタカナも対応するひらがなの行に分類する
        def normalize_initial(yomi)
          return 'その他' if yomi.nil? || yomi.empty?

          first_char = yomi[0]
          
          # カタカナをひらがなに変換して判定
          normalized_char = katakana_to_hiragana(first_char)
          
          case normalized_char
          when /[あ-おぁ-ぉ]/ then 'あ'
          when /[か-こが-ご]/ then 'か'
          when /[さ-そざ-ぞ]/ then 'さ'
          when /[た-とだ-ど]/ then 'た'
          when /[な-の]/ then 'な'
          when /[は-ほば-ぼぱ-ぽ]/ then 'は'
          when /[ま-も]/ then 'ま'
          when /[や-よゃ-ょ]/ then 'や'
          when /[ら-ろ]/ then 'ら'
          when /[わ-んを]/ then 'わ'
          when /[a-zA-Z]/ then 'A-Z'
          when /[0-9]/ then '0-9'
          else 'その他'
          end
        end

        # カタカナをひらがなに変換
        # @param char [String] 単一文字
        # @return [String] ひらがな（カタカナ以外はそのまま）
        def katakana_to_hiragana(char)
          return char unless char.match?(/[\u30A0-\u30FF]/)

          # カタカナ→ひらがな変換（Unicodeコードポイントで96ずらす）
          (char.ord - 96).chr('UTF-8')
        end

        # グループヘッダーを構築
        def build_group_header(initial)
          %(<div class="glossary-group-header" role="heading" aria-level="2">#{initial}</div>)
        end

        # 用語エントリを構築
        def build_term_entry(term)
          term_text = term['term']
          yomi = term['yomi'] || term_text
          definition = term['definition'] || ''
          slug = generate_slug(term_text)
          backlinks = build_backlinks(term)

          <<~HTML.chomp
            <dt id="gls-#{slug}" class="glossary-term">
              <ruby>#{escape_html(term_text)}<rp>(</rp><rt>#{escape_html(yomi)}</rt><rp>)</rp></ruby>
            </dt>
            <dd class="glossary-definition">
              #{render_definition(definition)}
              #{backlinks}
            </dd>
          HTML
        end

        # 説明文をレンダリング（Markdown 対応）
        # ## → h4, ### → h5, #### → h6, * → ul/li に変換
        def render_definition(definition)
          return '' if definition.nil? || definition.empty?

          lines = definition.to_s.strip.split("\n")
          html_parts = []
          current_list = []

          lines.each do |line|
            # リスト項目の処理
            if line.match?(/^\s*\*\s+/)
              current_list << line.sub(/^\s*\*\s+/, '').strip
              next
            end

            # リストが終了した場合、先にリストを出力
            unless current_list.empty?
              html_parts << render_list(current_list)
              current_list = []
            end

            # 見出しの処理（## → h4, ### → h5, #### → h6）
            case line
            when /^####\s+(.+)$/
              html_parts << %(<h6 class="glossary-h6">#{render_inline(::Regexp.last_match(1))}</h6>)
            when /^###\s+(.+)$/
              html_parts << %(<h5 class="glossary-h5">#{render_inline(::Regexp.last_match(1))}</h5>)
            when /^##\s+(.+)$/
              html_parts << %(<h4 class="glossary-h4">#{render_inline(::Regexp.last_match(1))}</h4>)
            when /^\s*$/
              # 空行はスキップ
              next
            else
              # 通常のテキスト行
              html_parts << %(<p class="glossary-text-line">#{render_inline(line)}</p>)
            end
          end

          # 残りのリストを出力
          html_parts << render_list(current_list) unless current_list.empty?

          %(<div class="glossary-body">#{html_parts.join("\n")}</div>)
        end

        # リスト項目をul/liに変換
        def render_list(items)
          return '' if items.empty?

          li_tags = items.map { %(<li>#{render_inline(it)}</li>) }.join("\n")
          %(<ul class="glossary-list-items">\n#{li_tags}\n</ul>)
        end

        # インライン要素の変換（強調、コードなど）
        def render_inline(text)
          result = escape_html(text.to_s)
          result = result.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
          result = result.gsub(/\*(.+?)\*/, '<em>\1</em>')
          result = result.gsub(/`(.+?)`/, '<code>\1</code>')
          result
        end

        # 戻りリンクを構築（ページ番号のみ表示、章番号・出現順でソート）
        # PDF では target-counter で自動的にページ番号が表示される
        # 注: 同一ページへの複数リンクは CSS target-counter により同じページ番号で表示される
        def build_backlinks(term)
          sources = term['backlink_sources']
          return '' unless sources&.any?

          # 章番号と出現順で昇順ソート（重複排除はしない）
          sorted_sources = sources.sort_by do |source|
            chapter = source['chapter'] || source[:chapter]
            occurrence = source['occurrence'] || source[:occurrence] || 1
            # 章番号を抽出してソート（例: "08-web" → 8）
            chapter_num = chapter.to_s[/\A(\d+)/, 1]&.to_i || 999
            [chapter_num, occurrence]
          end

          links = sorted_sources.map do |source|
            chapter = source['chapter'] || source[:chapter]
            occurrence = source['occurrence'] || source[:occurrence] || 1
            anchor_id = source['anchor_id'] || source[:anchor_id] || "gls-src-#{chapter}-#{occurrence}"

            classes = ['glossary-backlink']
            classes << 'frontmatter' if chapter.to_s.start_with?('00-')

            # リンクテキストは空にし、CSS で target-counter によるページ番号のみ表示
            %(<a href="#{chapter}.html##{anchor_id}" class="#{classes.join(' ')}"></a>)
          end

          <<~HTML.chomp
            <p class="glossary-backlinks">#{links.join(' ')}</p>
          HTML
        end

        # スラッグを生成（アンカー ID 用）
        def generate_slug(term)
          # 日本語を含む場合は URI エンコード風に変換
          term.downcase
              .gsub(/\s+/, '-')
              .gsub(/[^\p{L}\p{N}\-]/, '')
        end

        # HTML エスケープ
        def escape_html(text)
          text.to_s
              .gsub('&', '&amp;')
              .gsub('<', '&lt;')
              .gsub('>', '&gt;')
              .gsub('"', '&quot;')
        end
      end
    end
  end
end
