# frozen_string_literal: true

# ================================================================
# Class: BacklinkDeduplicator
# ================================================================
# 責務:
#   PageMappingExtractor が取得したページマッピングを基に、
#   HTML ファイルからバックリンクの重複を排除する。
#
# 処理対象:
#   1. _glossarypage.html — 同一ページへの重複バックリンクを削除
#   2. 本文 HTML — 同一ページ内の2回目以降の glossary-link（†）を削除
#
# 依存:
#   - Nokogiri（HTML パーサー）
#   - PageMappingExtractor::PageMapping（ページマッピングデータ）
# ================================================================

require 'nokogiri'
require 'set'

module Vivlio
  module Starter
    module CLI
      module Build
        # ページマッピングを使って HTML のバックリンク重複を排除する
        class BacklinkDeduplicator
          # 処理結果を保持する Data オブジェクト
          Result = Data.define(:glossary_removed, :body_removed, :files_modified)

          def initialize(page_mapping)
            @page_mapping = page_mapping
            @glossary_removed = 0
            @body_removed = 0
            @files_modified = []
          end

          # 重複排除を実行するメインメソッド
          # @return [Result] 処理結果
          def deduplicate!
            # --- Phase 1: ページマッピングからルックアップテーブルを構築 ---
            anchor_to_page = build_anchor_to_page_lookup

            if anchor_to_page.empty?
              Common.log_info('[backlink-dedup] glossary-link のページマッピングが空です。スキップします')
              return build_result
            end

            Common.log_info("[backlink-dedup] #{anchor_to_page.size} 件の anchor → page マッピングを構築しました")

            # --- Phase 2: 用語集ページのバックリンク重複排除 ---
            deduplicate_glossary_backlinks!(anchor_to_page)

            # --- Phase 3: 本文HTMLの†重複排除 ---
            deduplicate_body_glossary_links!(anchor_to_page)

            build_result
          end

          private

          attr_reader :page_mapping

          # anchor_id → (spine_index, page_index) のルックアップを構築
          # @return [Hash{String => Array(Integer, Integer)}]
          def build_anchor_to_page_lookup
            page_mapping.mappings.each_with_object({}) do |entry, lookup|
              lookup[entry.anchor_id] = [entry.spine_index, entry.page_index]
            end
          end

          # --- 用語集ページ（_glossarypage.html）の重複排除 ---

          # 同一用語について、同じページを指すバックリンクの2件目以降を削除
          def deduplicate_glossary_backlinks!(anchor_to_page)
            glossary_file = '_glossarypage.html'
            return unless File.exist?(glossary_file)

            html = File.read(glossary_file, encoding: 'utf-8')
            doc = Nokogiri::HTML5(html)

            # 各 .glossary-backlinks（用語ごとのバックリンク群）を処理
            doc.css('p.glossary-backlinks').each do |backlinks_p|
              deduplicate_backlinks_in_paragraph!(backlinks_p, anchor_to_page)
            end

            write_if_changed!(glossary_file, html, doc)
          end

          # 1つの <p class="glossary-backlinks"> 内の重複を排除
          # 同一 (spine_index, page_index) を指す <a> の2件目以降を削除
          def deduplicate_backlinks_in_paragraph!(paragraph, anchor_to_page)
            seen_pages = Set.new
            links_to_remove = []

            paragraph.css('a.glossary-backlink').each do |link|
              # href="08-web.html#gls-src-08-web-ウェブサイト-4" から anchor_id を抽出
              href = link['href'].to_s
              anchor_id = extract_anchor_id_from_href(href)
              page_key = anchor_to_page[anchor_id]

              # マッピングが見つからない場合はそのまま残す
              next unless page_key

              if seen_pages.include?(page_key)
                links_to_remove << link
              else
                seen_pages.add(page_key)
              end
            end

            # 2件目以降を削除し、前後の空白ノードも整理
            links_to_remove.each do |link|
              remove_link_and_adjacent_whitespace!(link)
              @glossary_removed += 1
            end
          end

          # --- 本文 HTML の†重複排除 ---

          # 同一ページ内で同じ用語への glossary-link が複数ある場合、2件目以降を削除
          def deduplicate_body_glossary_links!(anchor_to_page)
            # マッピングから対象ファイルを特定（anchor_id のプレフィックスから章を推定）
            target_files = detect_body_html_files(anchor_to_page)

            target_files.each do |html_file|
              next unless File.exist?(html_file)

              deduplicate_single_body_file!(html_file, anchor_to_page)
            end
          end

          # 単一の本文 HTML ファイル内で glossary-link の重複を排除
          def deduplicate_single_body_file!(html_file, anchor_to_page)
            html = File.read(html_file, encoding: 'utf-8')
            doc = Nokogiri::HTML5(html)

            # ページ＋用語の組み合わせで重複を追跡
            # キー: "(spine_index, page_index, glossary_href)" → 最初の出現のみ残す
            seen_on_page = Set.new
            links_to_remove = []

            doc.css('a.glossary-link').each do |link|
              anchor_id = link['id'].to_s
              next unless anchor_id.start_with?('gls-src-')

              glossary_href = link['href'].to_s  # "_glossarypage.html#gls-ウェブサイト"
              page_key = anchor_to_page[anchor_id]

              # マッピングが見つからない場合はそのまま残す
              next unless page_key

              # (spine, page, 用語href) の3つ組で一意性を判定
              dedup_key = [page_key[0], page_key[1], glossary_href]

              if seen_on_page.include?(dedup_key)
                links_to_remove << link
              else
                seen_on_page.add(dedup_key)
              end
            end

            return if links_to_remove.empty?

            # 2件目以降の†リンクを削除
            links_to_remove.each do |link|
              link.remove
              @body_removed += 1
            end

            write_if_changed!(html_file, html, doc)
          end

          # --- ヘルパーメソッド ---

          # href 文字列から anchor_id を抽出
          # "08-web.html#gls-src-08-web-ウェブサイト-4" → "gls-src-08-web-ウェブサイト-4"
          def extract_anchor_id_from_href(href) = href.split('#', 2).last.to_s

          # anchor_to_page のキーから対象の本文 HTML ファイルを特定
          # "gls-src-08-web-ウェブサイト-4" → "08-web.html"
          def detect_body_html_files(anchor_to_page)
            anchor_to_page.keys
                          .filter_map { extract_chapter_from_anchor_id(it) }
                          .uniq
                          .map { "#{it}.html" }
                          .select { File.exist?(it) }
          end

          # anchor_id から章ベース名を抽出
          # "gls-src-08-web-ウェブサイト-4" → "08-web"
          # パターン: gls-src-<chapter>-<slug>-<num>
          def extract_chapter_from_anchor_id(anchor_id)
            # "gls-src-" を除去してから、章名部分（数字-英字）を抽出
            rest = anchor_id.delete_prefix('gls-src-')
            # 章名は "NN-name" 形式（例: "08-web", "00-preface"）
            rest[/\A(\d+-[a-z_]+)/i, 1]
          end

          # リンク要素とその前後の不要な空白テキストノードを削除
          def remove_link_and_adjacent_whitespace!(link)
            # リンクの直前のテキストノードが空白のみなら削除
            prev_node = link.previous
            prev_node.remove if prev_node&.text? && prev_node.content.match?(/\A\s+\z/)

            link.remove
          end

          # 変更がある場合のみファイルを書き込み
          def write_if_changed!(file_path, original_html, doc)
            new_html = serialize_html(doc)
            return if new_html == original_html

            File.write(file_path, new_html, encoding: 'utf-8')
            @files_modified << file_path
            Common.log_success("[backlink-dedup] #{File.basename(file_path)} を更新しました")
          end

          # Nokogiri ドキュメントを HTML 文字列に変換
          # Nokogiri のデフォルト出力ではなく、元の形式に近い形で出力
          def serialize_html(doc)
            doc.to_html(encoding: 'UTF-8')
          end

          # 処理結果を構築
          def build_result
            Result.new(
              glossary_removed: @glossary_removed,
              body_removed: @body_removed,
              files_modified: @files_modified
            )
          end
        end
      end
    end
  end
end
