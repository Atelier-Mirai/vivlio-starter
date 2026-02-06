# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/index/index_match_scanner.rb
# ================================================================
# 責務:
#   Markdown ファイルをスキャンし、索引語記法を検出・変換する。
#   - [用語|読み] 記法を検出し、<dfn> または <span> タグに変換
#   - [用語] 記法（読み省略）を検出し、MeCab で読みを推測
#   - 初出は <dfn>、2回目以降は <span> タグを使用
#   - マッチ情報を _index_matches.yml に保存
#
# Ruby 4.0.0:
#   - Set が組み込み化され、require "set" が不要
#   - Set[] リテラル構文を使用
# ================================================================

require 'yaml'
require 'fileutils'
require 'cgi'
require_relative '../common'
require_relative 'yomi_inferrer'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        INDEX_TERMS_MISSING_MESSAGE = <<~MSG.freeze
          索引語辞書(config/index_terms.yml)が見つかりませんでした
          ⚠️  原稿に [用語|読み] という書き方で手動登録した語のみが索引に載ります
          ⚠️  自動索引機能を有効にするには: vs index:auto -> vs index:apply
        MSG

        def self.add_post_build_message(message)
          @post_build_messages ||= []
          @post_build_messages << message unless @post_build_messages.include?(message)
        end

        def self.flush_post_build_messages
          return if @post_build_messages.nil? || @post_build_messages.empty?

          @post_build_messages.each do |message|
            emit_index_message(message, use_log_warn: false)
          end

          @post_build_messages.clear
        end

        def self.emit_index_message(message, use_log_warn: true)
          message.each_line do |line|
            text = line.rstrip
            next if text.empty?

            if use_log_warn
              Common.log_warn(text)
            else
              Common.echo_always(text)
            end
          end
        end

        # 索引語スキャン・タグ付けクラス
        class IndexMatchScanner
          # 索引語マッチの正規表現
          # [用語|読み] または [用語] 形式を検出
          # ただし、[text](url) 形式のリンクは除外（後ろに ( が続く場合はスキップ）
          INDEX_TERM_PATTERN = /\[([^\[\]\n]+)\](?!\()/

          attr_reader :seen_terms, :term_occurrence, :index_data, :matches, :config_missing, :no_matches

          def initialize(defer_warnings: false)
            @seen_terms = Set[]
            @term_occurrence = Hash.new(0)
            @index_data = Hash.new { |h, k| h[k] = Set[] }
            @matches = []
            @yomi_inferrer = YomiInferrer.new
            @config_missing = false
            @no_matches = false
            @defer_warnings = defer_warnings
            @config_terms = load_config_terms
            @glossary_terms = load_glossary_terms
            @glossary_backlinks = Hash.new { |h, k| h[k] = [] }
          end

          # config/index_terms.yml を読み込む
          def load_config_terms
            config_file = 'config/index_terms.yml'
            unless File.exist?(config_file)
              if @defer_warnings
                @config_missing = true
              else
                IndexCommands.emit_index_message(INDEX_TERMS_MISSING_MESSAGE)
              end
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

          # config/glossary_terms.yml を読み込む
          def load_glossary_terms
            config_file = 'config/glossary_terms.yml'
            return {} unless File.exist?(config_file)

            begin
              data = YAML.load_file(config_file)
              terms = data['terms'] || []
              # 用語名をキーとしたハッシュに変換
              terms.to_h { |t| [t['term'], t] }
            rescue StandardError => e
              Common.log_warn("config/glossary_terms.yml の読み込みに失敗しました: #{e.message}")
              {}
            end
          end

          # 用語集のバックリンクを glossary_terms.yml に保存
          def save_glossary_backlinks!
            return if @glossary_backlinks.empty?

            config_file = 'config/glossary_terms.yml'
            return unless File.exist?(config_file)

            begin
              data = YAML.load_file(config_file)
              terms = data['terms'] || []

              terms.each do |term|
                term_name = term['term']
                next unless @glossary_backlinks.key?(term_name)

                term['backlink_sources'] = @glossary_backlinks[term_name]
              end

              data['terms'] = terms
              data['updated_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
              File.write(config_file, data.to_yaml, encoding: 'utf-8')
              Common.log_info("用語集のバックリンクを更新しました")
            rescue StandardError => e
              Common.log_warn("用語集のバックリンク保存に失敗しました: #{e.message}")
            end
          end

          # 全章ファイルをスキャンして索引語をタグ付け
          # @param chapters [Array<String>] 対象章のファイル名リスト（例: ['11-basics', '12-advanced']）
          # @param read_only [Boolean] 読み取り専用モード（ファイルを書き換えない、contents/ を優先）
          def scan_all_chapters!(chapters, read_only: false)
            Common.log_action("索引語のスキャンを開始します... (対象: #{chapters.size} 章)")

            chapters.each do |chapter|
              # ファイルを探す
              # read_only モードでは contents/ を優先（原稿のマークアップを検出するため）
              # 通常モードではルート直下を優先（pre_process 後のファイルを更新するため）
              md_file = find_chapter_file(chapter, prefer_contents: read_only)

              unless md_file
                Common.log_warn("スキップ (Markdown が見つかりません): #{chapter}")
                next
              end

              scan_and_tag_file!(md_file, read_only: read_only)
            end

            save_matches!
            save_glossary_backlinks!
            Common.log_success("索引語スキャン完了: #{@matches.size} 件の索引語を検出")
          end

          # 章ファイルを探す
          # @param chapter [String] 章名
          # @param prefer_contents [Boolean] contents/ ディレクトリを優先するか
          # @return [String, nil] ファイルパス
          def find_chapter_file(chapter, prefer_contents: false)
            root_file = "#{chapter}.md"
            contents_file = File.join(Common::CONTENTS_DIR, "#{chapter}.md")

            if prefer_contents
              # contents/ を優先
              return contents_file if File.exist?(contents_file)
              return root_file if File.exist?(root_file)
            else
              # ルート直下を優先
              return root_file if File.exist?(root_file)
              return contents_file if File.exist?(contents_file)
            end

            nil
          end

          # 単一ファイルをスキャンしてタグ付け
          # @param md_file [String] Markdown ファイルパス
          # @param read_only [Boolean] 読み取り専用モード（ファイルを書き換えない）
          def scan_and_tag_file!(md_file, read_only: false)
            content = File.read(md_file, encoding: 'utf-8')
            file_basename = File.basename(md_file, '.md')

            match_count_before = @matches.size
            Common.log_info("スキャン中: #{md_file} ...")

            # コードブロック内を除外してスキャン
            new_content = process_content_with_code_block_exclusion(content, file_basename)

            match_count_after = @matches.size
            diff = match_count_after - match_count_before

            if diff > 0
              # read_only モードでない場合のみファイルを書き換え
              unless read_only
                File.write(md_file, new_content, encoding: 'utf-8')
                Common.log_success("#{md_file}: #{diff} 件の索引語をタグ付けしました")
              else
                Common.log_success("#{md_file}: #{diff} 件の索引語を検出しました（読み取り専用）")
              end
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

              # 無効な用語をスキップ（元のテキストをそのまま返す）
              if skip_term?(term_text)
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

          # 索引対象として無効な用語かどうかを判定
          # @param term_text [String] 用語テキスト
          # @return [Boolean] スキップすべきならtrue
          def skip_term?(term_text)
            return true if term_text.nil? || term_text.empty?

            # 脚注構文 [^id] のみ除外
            return true if term_text.start_with?('^')

            # 著者が意図的にマークアップした用語は除外しない
            # 例: [!], [&&], [!DOCTYPE], [<h1>] など
            false
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

              # 振り仮名記法 {漢字|ふりがな} を保護（索引対象から除外）
              protected_line = protected_line.gsub(/(\{[^{}]*\|[^{}]*\})/) do |match|
                token = "[[RUBY_TOKEN_#{placeholders.size}]]"
                placeholders[token] = match
                token
              end

              # インラインコード `...` を保護（索引対象から除外）
              # コードブロック内のタグはHTMLでエスケープされるため、IDとして機能しない
              protected_line = protected_line.gsub(/(`[^`]+`)/) do |match|
                token = "[[CODE_TOKEN_#{placeholders.size}]]"
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

            # タグを生成して返す（HTMLタグをエスケープ）
            escaped_term = CGI.escapeHTML(term_text)
            escaped_yomi = CGI.escapeHTML(yomi.to_s)
            index_tag = %(<#{tag_name} id="#{anchor_id}" class="index-term" data-yomi="#{escaped_yomi}">#{escaped_term}</#{tag_name}>)

            # 用語集に登録されている場合は、用語集リンクを追加
            glossary_link = build_glossary_link(term_text, file_basename, occurrence_num)
            glossary_link ? "#{index_tag}#{glossary_link}" : index_tag
          end

          # 用語集インジケータ記号（固定）
          GLOSSARY_INDICATOR = '†'

          # 用語集リンクを生成
          # 常に†記号を上付きで表示し、クリックで用語集ページへジャンプ
          def build_glossary_link(term_text, file_basename, occurrence_num)
            return nil unless @glossary_terms.key?(term_text)

            slug = generate_glossary_slug(term_text)
            # 用語集へのバックリンク情報を記録（章+用語スラッグ+出現番号で一意化）
            gls_src_id = "gls-src-#{file_basename}-#{slug}-#{occurrence_num}"
            @glossary_backlinks[term_text] << {
              'chapter' => file_basename,
              'occurrence' => occurrence_num,
              'anchor_id' => gls_src_id
            }

            # 用語集へのリンクを生成（†記号を上付きで表示）
            %(<a id="#{gls_src_id}" class="glossary-link" href="_glossarypage.html#gls-#{slug}"><sup>#{GLOSSARY_INDICATOR}</sup></a>)
          end

          # 用語集スラッグを生成
          def generate_glossary_slug(term)
            term.downcase.gsub(/\s+/, '-').gsub(/[^\p{L}\p{N}\-]/, '')
          end

          # 索引データを _index_matches.yml に保存
          def save_matches!
            cache_file = '_index_matches.yml'

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
            if @matches.empty?
              if @defer_warnings
                @no_matches = true
              else
                IndexCommands.emit_index_message(INDEX_TERMS_MISSING_MESSAGE)
              end
            end
          end

        end
      end
    end
  end
end
