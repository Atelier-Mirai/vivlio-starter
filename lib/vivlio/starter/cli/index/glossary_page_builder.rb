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

        # 先頭文字を正規化（ひらがな→行に変換）
        def normalize_initial(yomi)
          return 'その他' if yomi.nil? || yomi.empty?

          first_char = yomi[0]
          
          # ひらがなの行を判定
          case first_char
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
        def render_definition(definition)
          return '' if definition.nil? || definition.empty?

          # 簡易 Markdown 変換
          text = definition.to_s.strip
          text = text.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
          text = text.gsub(/\*(.+?)\*/, '<em>\1</em>')
          text = text.gsub(/`(.+?)`/, '<code>\1</code>')
          text = text.gsub(/\n/, '<br>')
          
          %(<p class="glossary-text">#{text}</p>)
        end

        # 戻りリンクを構築
        def build_backlinks(term)
          sources = term['backlink_sources']
          return '' unless sources&.any?

          links = sources.map do |source|
            chapter = source['chapter'] || source[:chapter]
            occurrence = source['occurrence'] || source[:occurrence] || 1
            # anchor_id が明示的に指定されていればそれを使用、なければ生成
            anchor_id = source['anchor_id'] || source[:anchor_id] || "gls-src-#{chapter}-#{occurrence}"
            
            # target-counter で PDF 時にページ番号を表示
            %(<a href="#{chapter}.html##{anchor_id}" class="glossary-backlink">#{chapter}</a>)
          end.uniq

          <<~HTML.chomp
            <p class="glossary-backlinks">
              本文へ戻る: #{links.join(', ')}
            </p>
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
