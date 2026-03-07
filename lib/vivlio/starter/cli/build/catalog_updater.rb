# frozen_string_literal: true

require_relative 'catalog_loader'

# ================================================================
# File: lib/vivlio/starter/cli/build/catalog_updater.rb
# ================================================================
# 責務:
#   config/catalog.yml を自動的に更新する。
#   章の追加・削除・リネーム時に呼び出される。
#
# 呼び出し元:
#   - vs create: 新規章の追加
#   - vs delete: 章の削除
#   - vs rename: 章のリネーム
#   - vs renumber: 章番号の付け直し
#
# catalog.yml 構造:
#   PREFACE:    # 前書き（章番号 00）
#   CHAPTERS:   # 本文（章番号 01-89）
#   APPENDICES: # 付録（章番号 90-98）
#   POSTFACE:   # 後書き（章番号 99）
#
# 依存:
#   - CatalogLoader: catalog.yml の読み込み
# ================================================================

module Vivlio
  module Starter
    module CLI
      module Build
        # catalog.yml の自動更新モジュール
        # テキストベースで行単位に編集し、コメント行（# - 02-history 等）を完全に保持する
        module CatalogUpdater
          module_function

          CATALOG_FILE = CatalogLoader::CATALOG_FILE

          # ================================================================
          # Public API
          # ================================================================

          # 章を catalog.yml に追加
          # @param basename [String] 追加する章の basename（拡張子なし）
          def add_chapter(basename)
            unless File.exist?(CATALOG_FILE)
              create_initial_catalog_with(basename)
              Common.log_info("catalog.yml を作成し #{basename} を追加しました")
              return
            end

            lines = read_catalog_lines
            section = section_for_basename(basename)

            # 既にアクティブ（非コメント）として存在する場合はスキップ
            return if active_entry_exists?(lines, basename)

            insert_idx, indent = find_text_insertion_point(lines, section, basename)
            lines.insert(insert_idx, "#{indent}- #{basename}")
            write_catalog_lines(lines)
            Common.log_info("catalog.yml に #{basename} を追加しました（#{section}）")
          end

          # 章を catalog.yml から削除
          # @param basename [String] 削除する章の basename（拡張子なし）
          def remove_chapter(basename)
            return unless File.exist?(CATALOG_FILE)

            lines = read_catalog_lines
            idx = find_active_entry_line(lines, basename)
            return unless idx

            lines.delete_at(idx)
            write_catalog_lines(lines)
            Common.log_info("catalog.yml から #{basename} を削除しました")
          end

          # 章の basename を変更
          # @param old_basename [String] 旧 basename
          # @param new_basename [String] 新 basename
          def rename_chapter(old_basename, new_basename)
            return unless File.exist?(CATALOG_FILE)

            old_section = section_for_basename(old_basename)
            new_section = section_for_basename(new_basename)

            if old_section == new_section
              # 同一セクション内: 行内の basename を置換
              lines = read_catalog_lines
              idx = find_active_entry_line(lines, old_basename)
              if idx
                lines[idx] = lines[idx].sub(old_basename, new_basename)
                write_catalog_lines(lines)
                Common.log_info("catalog.yml: #{old_basename} → #{new_basename}")
              end
            else
              # セクション変更: 削除 → 追加
              remove_chapter(old_basename)
              add_chapter(new_basename)
              Common.log_info("catalog.yml: #{old_basename} → #{new_basename}（#{old_section} → #{new_section}）")
            end
          end

          # basename から適切なセクションを決定
          # @param basename [String]
          # @return [String] セクションキー
          def section_for_basename(basename)
            num = CatalogLoader.extract_chapter_number(basename)
            return 'CHAPTERS' unless num

            CatalogLoader.section_for_chapter_number(num)
          end

          # ================================================================
          # Private: ファイル I/O
          # ================================================================

          # catalog.yml を行配列として読み込む
          def read_catalog_lines
            File.readlines(CATALOG_FILE, encoding: 'utf-8', chomp: true)
          end

          # 行配列を catalog.yml に書き戻す
          def write_catalog_lines(lines)
            FileUtils.mkdir_p(File.dirname(CATALOG_FILE))
            File.write(CATALOG_FILE, lines.join("\n") + "\n", encoding: 'utf-8')
          end

          # ================================================================
          # Private: 行検索
          # ================================================================

          # アクティブ（非コメント）エントリ行のインデックスを返す
          # @return [Integer, nil]
          def find_active_entry_line(lines, basename)
            lines.index do |l|
              stripped = l.strip
              stripped == "- #{basename}" || stripped == "- #{basename}.md"
            end
          end

          # アクティブエントリとして存在するかチェック
          def active_entry_exists?(lines, basename)
            !!find_active_entry_line(lines, basename)
          end

          # 行から basename を抽出（アクティブ/コメント両方対応）
          # 例: "      - 21-html" → "21-html"
          #     "      # - 22-css" → "22-css"
          # @return [String, nil]
          def extract_basename_from_line(line)
            return unless line.match?(/^\s+#?\s*-\s+\S/)

            line.strip
                .sub(/^#\s*/, '')
                .sub(/^-\s+/, '')
                .sub(/\.md\s*$/, '')
                .strip
          end

          # ================================================================
          # Private: セクション・部タイトル構造の解析
          # ================================================================

          # セクションの行範囲を特定
          # @return [Array(Integer, Integer)] [開始行, 終了行]
          def find_section_boundaries(lines, section)
            start_idx = lines.index { |l| l.strip == "#{section}:" }
            return [nil, nil] unless start_idx

            # 次のセクションヘッダーを探す
            next_section_idx = nil
            (start_idx + 1...lines.length).each do |idx|
              if CatalogLoader::SECTION_KEYS.any? { lines[idx].strip == "#{it}:" }
                next_section_idx = idx
                break
              end
            end

            end_idx = (next_section_idx || lines.length) - 1

            # 末尾の空行・セクションコメント行を除外
            while end_idx > start_idx &&
                  (lines[end_idx].strip.empty? || lines[end_idx].match?(/^#/))
              end_idx -= 1
            end

            [start_idx, end_idx]
          end

          # セクション内の部タイトル範囲を検出
          # @return [Array<Hash>] { title:, header:, content_start:, end: }
          def detect_part_ranges(lines, section_start, section_end)
            parts = []

            (section_start + 1..section_end).each do |idx|
              line = lines[idx]
              next if line.match?(/^\s+#/)  # コメント行はスキップ

              # 部タイトル: インデントされたリスト項目で末尾が ":"
              next unless line.match?(/^\s+-\s+.+:\s*$/)

              parts << {
                title: line.strip.sub(/^-\s+/, '').sub(/:\s*$/, ''),
                header: idx,
                content_start: idx + 1
              }
            end

            # 各部の終了行を設定
            parts.each_with_index do |part, idx|
              part[:end] = if idx + 1 < parts.length
                             parts[idx + 1][:header] - 1
                           else
                             section_end
                           end
            end

            parts
          end

          # 章番号から所属する部を特定（コメント行も含めて判定）
          # @return [Hash, nil] 対象の部情報
          def determine_target_part(lines, parts, chapter_num)
            part_infos = parts.map do |part|
              nums = (part[:content_start]..part[:end]).filter_map do |idx|
                bn = extract_basename_from_line(lines[idx])
                bn && CatalogLoader.extract_chapter_number(bn)
              end
              part.merge(min_num: nums.min, max_num: nums.max)
            end

            part_infos.each_with_index do |part, idx|
              next_min = part_infos[idx + 1]&.dig(:min_num)
              if (part[:min_num].nil? || chapter_num >= part[:min_num]) &&
                 (next_min.nil? || chapter_num < next_min)
                return part
              end
            end

            part_infos.last
          end

          # ================================================================
          # Private: 挿入位置の計算
          # ================================================================

          # テキスト内の挿入位置とインデントを計算
          # @return [Array(Integer, String)] [挿入行インデックス, インデント文字列]
          def find_text_insertion_point(lines, section, basename)
            num = CatalogLoader.extract_chapter_number(basename) || 0
            section_start, section_end = find_section_boundaries(lines, section)

            # セクションが見つからない場合、末尾にセクションヘッダーを追加
            unless section_start
              lines << ''
              lines << "#{section}:"
              return [lines.length, '  ']
            end

            # 部タイトル構造を検出
            parts = detect_part_ranges(lines, section_start, section_end)

            if parts.any?
              target = determine_target_part(lines, parts, num)
              if target
                return find_sorted_insert_in_range(
                  lines, target[:content_start], target[:end], num, '      '
                )
              end
            end

            # フラットなセクション
            find_sorted_insert_in_range(lines, section_start + 1, section_end, num, '  ')
          end

          # 範囲内で章番号順の挿入位置を検索（コメント行も含めてソート位置を計算）
          # @return [Array(Integer, String)] [挿入行インデックス, インデント文字列]
          def find_sorted_insert_in_range(lines, range_start, range_end, num, indent)
            last_entry_idx = range_start - 1

            (range_start..range_end).each do |idx|
              bn = extract_basename_from_line(lines[idx])
              next unless bn

              entry_num = CatalogLoader.extract_chapter_number(bn)
              next unless entry_num

              return [idx, indent] if entry_num > num

              last_entry_idx = idx
            end

            [last_entry_idx + 1, indent]
          end

          # ================================================================
          # Private: 初期ファイル作成
          # ================================================================

          # catalog.yml が存在しない場合に初期作成
          def create_initial_catalog_with(basename)
            section = section_for_basename(basename)
            output = []

            output << default_header_comments
            output << ''

            CatalogLoader::SECTION_KEYS.each do |key|
              comments = default_section_comments[key] || []
              comments.each { output << it }
              output << "#{key}:"
              output << "  - #{basename}" if key == section
              output << ''
            end

            output << default_footer_comments

            FileUtils.mkdir_p(File.dirname(CATALOG_FILE))
            File.write(CATALOG_FILE, output.join("\n") + "\n", encoding: 'utf-8')
          end

          # デフォルトのヘッダーコメント
          def default_header_comments
            <<~HEADER.chomp
              # ========================================
              # ビルド対象にする章の指定
              # ========================================
              # 一部の章のみを対象としたい場合は、以下のように指定します。
                # - 11-install  # 拡張子(.md)は、省略できます。
                # - 12-tutorial
              # CHAPTERS: 11-12, 13-15, 25 # 章番号のみでのカンマ区切り, 範囲指定も指定可能です。
            HEADER
          end

          # デフォルトのセクションコメント
          def default_section_comments
            {
              'PREFACE' => ['## まえがき'],
              'CHAPTERS' => ['## 本文'],
              'APPENDICES' => ['## 付録'],
              'POSTFACE' => ['# ## あとがき']
            }
          end

          # デフォルトのフッターコメント
          def default_footer_comments
            <<~FOOTER.chomp
              ## 【Tips】
              ##
              ## ・付録やまえがきやあとがきがなければ、空にする。
              ##   例：
              ##
              ##     PREFACE:
              ##
              ##     CHAPTERS:
              ##       - 01-install.re
              ##
              ##     APPENDICES:
              ##
              ##     POSTFACE:
              ##
              ##
              ## ・第I部、第II部、…のように「部」を使うには、次のようにする。
              ##   （部タイトルの最後に半角の「:」をつけることに注意）
              ##
              ##     CHAPTERS:
              ##       - 初級編:
              ##           - 01-install.re
              ##           - 02-tutorial.re
              ##       - 中級編:
              ##           - 03-syntax.re
              ##           - 04-customize.re
              ##       - 上級編:
              ##           - 05-faq.re
              ##           - 06-bestpractice.re
              ##
            FOOTER
          end
        end
      end
    end
  end
end
