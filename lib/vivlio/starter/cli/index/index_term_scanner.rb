# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/index/index_term_scanner.rb
# ================================================================
# 責務:
#   Markdown ファイルをスキャンし、索引語記法を検出・変換する。
#   - [用語|読み] 記法を検出し、<dfn> または <span> タグに変換
#   - [用語] 記法（読み省略）を検出し、MeCab で読みを推測
#   - 初出は <dfn>、2回目以降は <span> タグを使用
#   - マッチ情報を .cache/index_matches.yml に保存
#
# Ruby 4.0.0:
#   - Set が組み込み化され、require "set" が不要
#   - Set[] リテラル構文を使用
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'
require_relative 'yomi_inferrer'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        # 索引語スキャン・タグ付けクラス
        class IndexTermScanner
          # 索引語マッチの正規表現
          # [用語|読み] または [用語] 形式を検出
          # ただし、[text](url) 形式のリンクは除外（後ろに ( が続く場合はスキップ）
          INDEX_TERM_PATTERN = /\[([^\[\]\n|]+)(?:\|([^\[\]\n]+))?\](?!\()/

          attr_reader :seen_terms, :term_occurrence, :index_data, :matches

          def initialize
            @seen_terms = Set[]
            @term_occurrence = Hash.new(0)
            @index_data = Hash.new { |h, k| h[k] = Set[] }
            @matches = []
            @yomi_inferrer = YomiInferrer.new
          end

          # 全章ファイルをスキャンして索引語をタグ付け
          # @param chapters [Array<String>] 対象章のファイル名リスト（例: ['11-basics', '12-advanced']）
          def scan_all_chapters!(chapters)
            Common.log_action('索引語のスキャンを開始します...')

            chapters.each do |chapter|
              md_file = "#{chapter}.md"
              next unless File.exist?(md_file)

              scan_and_tag_file!(md_file)
            end

            save_matches!
            Common.log_success("索引語スキャン完了: #{@matches.size} 件の索引語を検出")
          end

          # 単一ファイルをスキャンしてタグ付け
          # @param md_file [String] Markdown ファイルパス
          def scan_and_tag_file!(md_file)
            content = File.read(md_file, encoding: 'utf-8')
            file_basename = File.basename(md_file, '.md')

            Common.log_info("スキャン中: #{md_file}")

            # コードブロック内を除外してスキャン
            new_content = process_content_with_code_block_exclusion(content, file_basename)

            if new_content != content
              File.write(md_file, new_content, encoding: 'utf-8')
              Common.log_success("#{md_file}: 索引語をタグ付けしました")
            end
          end

          private

          # コードブロックを除外してコンテンツを処理
          def process_content_with_code_block_exclusion(content, file_basename)
            lines = content.lines
            result = []
            in_code_block = false

            lines.each do |line|
              stripped = line.lstrip

              # コードブロックの開始・終了を検出
              if stripped.start_with?('```') && !stripped.start_with?('```include:')
                in_code_block = !in_code_block
                result << line
                next
              end

              if in_code_block
                result << line
              else
                result << process_line(line, file_basename)
              end
            end

            result.join
          end

          # 1行を処理して索引語をタグ付け
          def process_line(line, file_basename)
            line.gsub(INDEX_TERM_PATTERN) do |_match|
              term_text = ::Regexp.last_match(1)
              yomi_raw = ::Regexp.last_match(2)

              # 読みがなければ MeCab で推測
              yomi = yomi_raw || @yomi_inferrer.infer(term_text)

              process_term(term_text, yomi, file_basename)
            end
          end

          # 索引語を処理してタグを生成
          def process_term(term_text, yomi, file_basename)
            @term_occurrence[term_text] += 1
            occurrence_num = @term_occurrence[term_text]

            # ID の生成（ハッシュベースで一意性を保証）
            anchor_id = "idx-#{term_text.hash.abs.to_s(36)}-#{occurrence_num}"

            # 初出判定（O(1) の高速検索）
            is_first = !@seen_terms.include?(term_text)
            @seen_terms << term_text if is_first

            tag_name = is_first ? 'dfn' : 'span'

            # 索引データの蓄積（Set で重複を自動排除）
            @index_data[term_text] << {
              yomi: yomi,
              link: "#{file_basename}.html##{anchor_id}",
              file: file_basename,
              is_definition: is_first
            }

            # マッチ情報を記録
            @matches << {
              id: anchor_id,
              term: term_text,
              yomi: yomi,
              file: file_basename,
              is_definition: is_first,
              tag_type: tag_name
            }

            # タグを生成して返す
            %(<#{tag_name} id="#{anchor_id}" class="index-term" data-yomi="#{yomi}">#{term_text}</#{tag_name}>)
          end

          # マッチ情報を .cache/index_matches.yml に保存
          def save_matches!
            cache_dir = '.cache'
            FileUtils.mkdir_p(cache_dir)

            cache_file = File.join(cache_dir, 'index_matches.yml')

            data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => @matches.size,
              'terms' => @index_data.transform_values(&:to_a),
              'matches' => @matches
            }

            File.write(cache_file, data.to_yaml, encoding: 'utf-8')
            Common.log_info("索引データを保存: #{cache_file}")
          end
        end
      end
    end
  end
end
