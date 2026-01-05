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
          INDEX_TERM_PATTERN = /\[([^\[\]\n]+)\](?!\()/

          attr_reader :seen_terms, :term_occurrence, :index_data, :matches

          def initialize
            @seen_terms = Set[]
            @term_occurrence = Hash.new(0)
            @index_data = Hash.new { |h, k| h[k] = Set[] }
            @matches = []
            @yomi_inferrer = YomiInferrer.new
            @config_terms = load_config_terms
          end

          # config/index_terms.yml を読み込む
          def load_config_terms
            config_file = 'config/index_terms.yml'
            unless File.exist?(config_file)
              Common.log_info("索引語辞書が見つかりません: #{config_file}")
              return []
            end

            begin
              data = YAML.load_file(config_file)
              terms = data['terms'] || []
              Common.log_info("索引語辞書から #{terms.size} 件の語句をロードしました")
              terms
            rescue StandardError => e
              Common.log_warn("config/index_terms.yml の読み込みに失敗しました: #{e.message}")
              []
            end
          end

          # 全章ファイルをスキャンして索引語をタグ付け
          # @param chapters [Array<String>] 対象章のファイル名リスト（例: ['11-basics', '12-advanced']）
          def scan_all_chapters!(chapters)
            Common.log_action("索引語のスキャンを開始します... (対象: #{chapters.size} 章)")

            chapters.each do |chapter|
              # pre_process 済みのルート直下ファイルを優先（contents/ を直接書き換えない）
              root_md_file = "#{chapter}.md"

              unless File.exist?(root_md_file)
                Common.log_warn("スキップ (ルートに展開された Markdown が見つかりません): #{root_md_file}")
                next
              end

              scan_and_tag_file!(root_md_file)
            end

            save_matches!
            Common.log_success("索引語スキャン完了: #{@matches.size} 件の索引語を検出")
          end

          # 単一ファイルをスキャンしてタグ付け
          # @param md_file [String] Markdown ファイルパス
          def scan_and_tag_file!(md_file)
            content = File.read(md_file, encoding: 'utf-8')
            file_basename = File.basename(md_file, '.md')

            match_count_before = @matches.size
            Common.log_info("スキャン中: #{md_file} ...")

            # コードブロック内を除外してスキャン
            new_content = process_content_with_code_block_exclusion(content, file_basename)

            match_count_after = @matches.size
            diff = match_count_after - match_count_before

            if diff > 0
              File.write(md_file, new_content, encoding: 'utf-8')
              Common.log_success("#{md_file}: #{diff} 件の索引語をタグ付けしました")
            else
              Common.log_info("#{md_file}: 索引語は見つかりませんでした")
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
            # 1. まず [用語|読み] または [用語] 記法を処理
            processed_line = line.gsub(INDEX_TERM_PATTERN) do |_match|
              term_with_optional_yomi = ::Regexp.last_match(1)
              term_text, yomi_raw = extract_term_and_yomi(term_with_optional_yomi)

              # 脚注構文 [^id] は索引対象から除外
              if term_text&.start_with?('^')
                ::Regexp.last_match(0)
              else
                # 読みの決定順序:
                # 1. 記法で指定された読み [用語|読み]
                # 2. config/index_terms.yml に定義された読み
                # 3. MeCab による推測
                yomi = yomi_raw || lookup_config_yomi(term_text) || @yomi_inferrer.infer(term_text)

                process_term(term_text, yomi, file_basename)
              end
            end

            # 2. 次に config/index_terms.yml に基づく自動タグ付け
            apply_auto_indexing(processed_line, file_basename)
          end

          def extract_term_and_yomi(raw_text)
            return [raw_text, nil] unless raw_text&.include?('|')

            pipe_count = raw_text.count('|')

            # 読み指定は「用語|読み」の1本区切りのみ許可し、それ以外はリテラル扱い
            return [raw_text, nil] unless pipe_count == 1

            term_part, yomi_part = raw_text.split('|', 2)

            if term_part.nil? || term_part.empty? || yomi_part.nil? || yomi_part.empty?
              [raw_text, nil]
            else
              [term_part, yomi_part]
            end
          end

          # config/index_terms.yml から読みを検索
          def lookup_config_yomi(term_text)
            config = @config_terms.find { |t| t['term'] == term_text }
            config ? config['yomi'] : nil
          end

          # config/index_terms.yml に基づく自動タグ付けを適用
          def apply_auto_indexing(line, file_basename)
            return line if @config_terms.empty?

            result = line
            @config_terms.each do |config|
              term = config['term']
              yomi = config['yomi'] || @yomi_inferrer.infer(term)

              # すでにタグ付けされた部分を保護（二重タグ付け防止）
              # タグ自体とその中身を一時的に置換する
              placeholders = {}
              # index-term クラスを持つ span または dfn タグを最短一致でマッチさせる
              # [修正] multiline オプションを考慮しなくても良いが、念のため /m は使わず、
              # タグの中身に他のタグが含まれないことを前提とする（現状の仕様）
              protected_line = result.gsub(/(<(span|dfn)[^>]*class="index-term"[^>]*>.*?<\/\2>)/) do |match|
                token = "[[IDX_TOKEN_#{placeholders.size}]]"
                placeholders[token] = match
                token
              end

              # pattern が指定されていればそれを使用、なければ完全一致
              pattern = if config['pattern']
                          begin
                            p_str = config['pattern'].to_s
                            if p_str.start_with?('/') && p_str.end_with?('/')
                              Regexp.new(p_str[1...-1])
                            else
                              Regexp.new(p_str)
                            end
                          rescue StandardError
                            Regexp.new(Regexp.escape(term))
                          end
                        else
                          Regexp.new(Regexp.escape(term))
                        end

              # 保護された状態の行に対して、用語を置換
              replaced_line = protected_line.gsub(pattern) do |match|
                # マッチした箇所が保護トークン内でないことを確認（念のため）
                if match.start_with?('[[IDX_TOKEN_')
                  match
                else
                  process_term(match, yomi, file_basename)
                end
              end

              # 保護していたタグを元に戻す
              placeholders.each do |token, original|
                replaced_line.gsub!(token, original)
              end

              result = replaced_line
            end
            result
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
              'yomi' => yomi,
              'link' => "#{file_basename}.html##{anchor_id}",
              'file' => file_basename,
              'is_definition' => is_first
            }

            # マッチ情報を記録
            @matches << {
              'id' => anchor_id,
              'term' => term_text,
              'yomi' => yomi,
              'file' => file_basename,
              'is_definition' => is_first,
              'tag_type' => tag_name
            }

            # タグを生成して返す
            %(<#{tag_name} id="#{anchor_id}" class="index-term" data-yomi="#{yomi}">#{term_text}</#{tag_name}>)
          end

          # 索引データを index_matches.yml に保存
          def save_matches!
            cache_file = 'index_matches.yml'

            # 用語名でソートして可読性を向上
            sorted_terms = @index_data.keys.sort.each_with_object({}) do |term, hash|
              hash[term] = @index_data[term].to_a
            end

            data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => @matches.size,
              'terms' => sorted_terms,
              'matches' => @matches
            }

            File.write(cache_file, data.to_yaml, encoding: 'utf-8')
            Common.log_info("索引データを保存: #{cache_file} (合計: #{@matches.size} 件)")
            if @matches.any?
              Common.log_warn("読み間違いがないか #{cache_file} を確認してください")
            else
              Common.log_warn('索引語が1件も検出されませんでした。config/index_terms.yml や原稿の記法を確認してください。')
            end
          end
        end
      end
    end
  end
end
