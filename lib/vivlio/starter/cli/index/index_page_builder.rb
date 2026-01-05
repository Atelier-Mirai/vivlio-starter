# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/index/index_page_builder.rb
# ================================================================
# 責務:
#   索引ページ (99-index.html) を生成する。
#   - .cache/index_matches.yml から索引データを読み込み
#   - 用語を五十音順でソート
#   - 「あ行」「か行」などでグループ化
#   - CSS target-counter 対応の HTML を生成
#
# Ruby 4.0.0:
#   - Set が組み込み化され、require "set" が不要
# ================================================================

require 'yaml'
require 'fileutils'
require 'cgi'
require_relative '../common'
require_relative 'hierarchical_index'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        # 索引ページ生成クラス
        class IndexPageBuilder
          # 五十音の行判定用マッピング
          KANA_ROWS = {
            'あ' => /^[あ-おぁ-ぉ]/,
            'か' => /^[か-ごゕゖ]/,
            'さ' => /^[さ-ぞ]/,
            'た' => /^[た-ど]/,
            'な' => /^[な-の]/,
            'は' => /^[は-ぽ]/,
            'ま' => /^[ま-も]/,
            'や' => /^[や-よゃゅょ]/,
            'ら' => /^[ら-ろ]/,
            'わ' => /^[わ-んゎ]/
          }.freeze

          SYMBOL_ROW_LABEL = '記号'
          NUMBER_ROW_LABEL = '数字'

          DIGIT_REGEX = /\A[0-9０-９]\z/

          ALPHA_ROWS = ('A'..'Z').each_with_object({}) do |letter, hash|
            hash[letter] = /^[#{letter.downcase}#{letter}]/
          end.freeze

          attr_reader :index_data, :hierarchical_index

          def initialize
            @index_data = {}
            @hierarchical_index = HierarchicalIndex.new
          end

          # 索引ページを生成
          # @param cache_file [String] 索引データのキャッシュファイルパス
          # @param output_file [String] 出力 HTML ファイルパス
          def build!(cache_file = 'index_matches.yml', output_file = '_indexpage.html')
            unless File.exist?(cache_file)
              Common.log_warn("索引データが見つかりません: #{cache_file}")
              Common.log_warn('vs index:match を先に実行してください')
              return nil
            end

            load_index_data!(cache_file)

            if @index_data.empty?
              Common.log_warn('索引データが空です')
              return nil
            end

            html = generate_html
            File.write(output_file, html, encoding: 'utf-8')
            Common.log_success("索引ページを生成しました: #{output_file}")
            output_file
          end

          private

          # 索引データを読み込み
          def load_index_data!(cache_file)
            data = YAML.load_file(cache_file, permitted_classes: [Time, Symbol])
            @index_data = data['terms'] || {}

            # HierarchicalIndex にエントリを追加
            @index_data.each do |term, occurrences|
              occurrences.each do |occ|
                link = occ['link'] || occ[:link]
                @hierarchical_index.add_entry(term, link)
              end
            end

            # 同一ページの重複を排除（Phase 3）
            @hierarchical_index.deduplicate_same_page!

            Common.log_info("索引データを読み込み: #{@index_data.size} 件の用語")
            Common.log_info("重複排除後リンク数: #{@hierarchical_index.link_count} 件")
          end

          # HTML を生成
          def generate_html
            sorted_terms = sort_terms_by_yomi
            groups = group_by_kana_row(sorted_terms)

            <<~HTML
              <!DOCTYPE html>
              <html lang="ja">
              <head>
                <meta charset="UTF-8">
                <title>索引</title>
                <link rel="stylesheet" href="stylesheets/index.css">
              </head>
              <body class="index-page">
                <section class="index">
                  <h1>索引</h1>
                  #{generate_index_sections(groups)}
                </section>
              </body>
              </html>
            HTML
          end

          # 用語を読みでソート
          def sort_terms_by_yomi
            @index_data.sort_by do |_term, occurrences|
              first_yomi = occurrences.first['yomi'] || occurrences.first[:yomi] || ''
              first_yomi.to_s
            end
          end

          # 五十音の行ごとにグループ化
          def group_by_kana_row(sorted_terms)
            groups = Hash.new { |h, k| h[k] = [] }

            sorted_terms.each do |term, occurrences|
              first_yomi = occurrences.first['yomi'] || occurrences.first[:yomi] || term
              row = determine_kana_row(first_yomi.to_s, term)
              groups[row] << [term, occurrences]
            end

            # 行の順序を維持
            ordered_rows = [SYMBOL_ROW_LABEL, NUMBER_ROW_LABEL] + ('A'..'Z').to_a + %w[あ か さ た な は ま や ら わ] + ['その他']
            ordered_rows.filter_map do |row|
              [row, groups[row]] if groups.key?(row)
            end.to_h
          end

          # 読みの先頭から五十音の行を判定
          def determine_kana_row(yomi, term)
            term_char = term.to_s[0]

            symbol_row = match_symbol_row(term_char)
            return symbol_row if symbol_row

            number_row = match_number_row(term_char)
            return number_row if number_row

            row = match_alpha_row(term_char)
            return row if row

            first_char = yomi[0]

            row = match_alpha_row(first_char)
            return row if row

            row = match_kana_row(first_char)
            return row if row

            'その他'
          end

          def match_kana_row(char)
            return nil unless char

            KANA_ROWS.each do |row, pattern|
              return row if char.match?(pattern)
            end

            nil
          end

          def match_alpha_row(char)
            return unless char

            ALPHA_ROWS.each do |row, regex|
              return row if regex.match?(char)
            end

            nil
          end

          def match_symbol_row(char)
            return unless char

            SYMBOL_ROW_LABEL unless char.match?(/[[:alnum:]]/)
          end

          def match_number_row(char)
            return unless char

            NUMBER_ROW_LABEL if DIGIT_REGEX.match?(char)
          end

          # 索引セクションの HTML を生成
          def generate_index_sections(groups)
            groups.map do |row, terms|
              next if terms.empty?

              <<~SECTION
                <div class="index-section" data-initial="#{row}">
                  <h2>#{row}</h2>
                  <dl class="index-list">
                    #{generate_term_entries(terms)}
                  </dl>
                </div>
              SECTION
            end.compact.join("\n")
          end

          # 用語エントリの HTML を生成
          def generate_term_entries(terms)
            terms.map do |term, _occurrences|
              escaped_term = CGI.escapeHTML(term.to_s)
              links = generate_page_links(term)
              <<~ENTRY
                <dt>#{escaped_term}</dt>
                <dd>#{links}</dd>
              ENTRY
            end.join
          end

          # ページリンクの HTML を生成
          # CSS target-counter でページ番号を自動挿入
          # Phase 3: 同一ページ重複排除済みリンクを使用
          def generate_page_links(term)
            # HierarchicalIndex から重複排除済みリンクを取得
            links = @hierarchical_index.entries[term] || []

            links.map do |link|
              %(<a href="#{link}"></a>)
            end.join(', ')
          end
        end
      end
    end
  end
end
