# frozen_string_literal: true

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
        module CatalogUpdater
          module_function

          CATALOG_FILE = CatalogLoader::CATALOG_FILE

          # 章を catalog.yml に追加
          # @param basename [String] 追加する章の basename（拡張子なし）
          def add_chapter(basename)
            catalog = load_or_create_catalog
            section = section_for_basename(basename)

            # セクションが存在しない場合は作成
            catalog[section] ||= []

            # 既に存在する場合は何もしない
            return if catalog[section].include?(basename)

            # 適切な位置に挿入
            insert_basename_to_section(catalog, section, basename)

            save_catalog(catalog)
            Common.log_info("catalog.yml に #{basename} を追加しました（#{section}）")
          end

          # 章を catalog.yml から削除
          # @param basename [String] 削除する章の basename（拡張子なし）
          def remove_chapter(basename)
            return unless File.exist?(CATALOG_FILE)

            catalog = CatalogLoader.load_catalog
            removed = false

            CatalogLoader::SECTION_KEYS.each do |section|
              items = catalog[section]
              next unless items.is_a?(Array)

              # フラット化して検索・削除
              if remove_from_items(items, basename)
                removed = true
              end
            end

            if removed
              save_catalog(catalog)
              Common.log_info("catalog.yml から #{basename} を削除しました")
            end
          end

          # 章の basename を変更
          # @param old_basename [String] 旧 basename
          # @param new_basename [String] 新 basename
          def rename_chapter(old_basename, new_basename)
            return unless File.exist?(CATALOG_FILE)

            catalog = CatalogLoader.load_catalog
            old_section = nil
            new_section = section_for_basename(new_basename)

            # 旧 basename を探して削除
            CatalogLoader::SECTION_KEYS.each do |section|
              items = catalog[section]
              next unless items.is_a?(Array)

              if remove_from_items(items, old_basename)
                old_section = section
                break
              end
            end

            return unless old_section

            # セクションが変わる場合（例: 11 → 91）
            if old_section == new_section
              # 同じセクション内でリネーム
              insert_basename_to_section(catalog, old_section, new_basename)
              Common.log_info("catalog.yml: #{old_basename} → #{new_basename}")
            else
              # 新しいセクションに追加
              catalog[new_section] ||= []
              insert_basename_to_section(catalog, new_section, new_basename)
              Common.log_info("catalog.yml: #{old_basename} → #{new_basename}（#{old_section} → #{new_section}）")
            end

            save_catalog(catalog)
          end

          # basename から適切なセクションを決定
          # @param basename [String]
          # @return [String] セクションキー
          def section_for_basename(basename)
            num = CatalogLoader.extract_chapter_number(basename)
            return 'CHAPTERS' unless num

            CatalogLoader.section_for_chapter_number(num)
          end



          # catalog.yml を読み込み、存在しない場合は空のカタログを作成
          def load_or_create_catalog
            if File.exist?(CATALOG_FILE)
              CatalogLoader.load_catalog
            else
              {
                'PREFACE' => [],
                'CHAPTERS' => [],
                'APPENDICES' => [],
                'POSTFACE' => []
              }
            end
          end

          # セクションの適切な位置に basename を挿入
          def insert_basename_to_section(catalog, section, basename)
            items = catalog[section] ||= []

            # ショートハンドが含まれている場合はフラット化
            flatten_if_needed!(items)

            # 章番号でソートして挿入
            num = CatalogLoader.extract_chapter_number(basename) || 0
            insert_index = items.find_index do |item|
              item_num = CatalogLoader.extract_chapter_number(item.to_s) || 0
              item_num > num
            end

            if insert_index
              items.insert(insert_index, basename)
            else
              items << basename
            end
          end

          # 配列内にショートハンド（数字範囲）があればフラット化
          def flatten_if_needed!(items)
            return if items.empty?

            expanded = []
            items.each do |item|
              if item.is_a?(String) && CatalogLoader.shorthand?(item)
                # ショートハンドを展開
                expanded.concat(CatalogLoader.expand_shorthand(item))
              elsif item.is_a?(Hash)
                # 部タイトル付きの場合、配下を再帰的に処理
                item.each do |_title, sub_items|
                  flatten_if_needed!(sub_items) if sub_items.is_a?(Array)
                end
                expanded << item
              else
                expanded << item
              end
            end

            items.replace(expanded)
          end

          # 配列から basename を削除（部タイトル配下も再帰的に検索）
          def remove_from_items(items, basename)
            removed = false

            items.reject! do |item|
              if item.is_a?(String)
                if item == basename || item == "#{basename}.md"
                  removed = true
                  true
                else
                  false
                end
              elsif item.is_a?(Hash)
                # 部タイトル配下を検索
                item.each_value do |sub_items|
                  if sub_items.is_a?(Array) && remove_from_items(sub_items, basename)
                    removed = true
                  end
                end
                false
              else
                false
              end
            end

            removed
          end

          # catalog.yml を保存（コメントを保持）
          def save_catalog(catalog)
            FileUtils.mkdir_p(File.dirname(CATALOG_FILE))

            # 元のファイルからコメント構造を抽出
            comment_structure = extract_comment_structure

            # コメント付きで YAML を生成
            output = generate_yaml_preserving_comments(catalog, comment_structure)

            File.write(CATALOG_FILE, output, encoding: 'utf-8')
          end

          # 元のファイルからコメント構造を抽出
          # @return [Hash] :header, :section_comments, :footer を含むハッシュ
          def extract_comment_structure
            default_structure = {
              header: default_header_comments,
              section_comments: default_section_comments,
              footer: default_footer_comments
            }

            return default_structure unless File.exist?(CATALOG_FILE)

            lines = File.readlines(CATALOG_FILE, encoding: 'utf-8', chomp: true)
            return default_structure if lines.empty?

            yaml_section_pattern = /^(PREFACE|CHAPTERS|APPENDICES|POSTFACE):/

            # 各セクションの開始位置を特定
            section_positions = {}
            lines.each_with_index do |line, idx|
              next unless (m = line.match(yaml_section_pattern))

              section_positions[m[1]] = idx
            end

            return default_structure if section_positions.empty?

            # 最初のセクションより前がヘッダー
            first_section_idx = section_positions.values.min
            header_lines = lines[0...first_section_idx]

            # 最後のセクションより後のコメント行がフッター
            last_section_key = section_positions.max_by { |_k, v| v }[0]
            last_section_idx = section_positions[last_section_key]

            # 最後のセクションの終了位置を探す（次のコメントブロックまで）
            footer_start_idx = nil
            (last_section_idx + 1...lines.length).each do |idx|
              line = lines[idx]
              # YAML の配列項目または空行はスキップ
              next if line.match?(/^\s*-\s/) || line.strip.empty?

              # コメント行に到達したらフッター開始
              if line.start_with?('#')
                footer_start_idx = idx
                break
              end
            end

            footer_lines = footer_start_idx ? lines[footer_start_idx..] : []

            # ヘッダーから各セクションの直前コメントを抽出
            section_comments = {}
            pending_comments = []

            header_lines.each do |line|
              if line.start_with?('#') || line.strip.empty?
                pending_comments << line
              else
                pending_comments.clear
              end
            end

            # 各セクション直前のコメントを抽出（空行で区切られるまで）
            sorted_sections = section_positions.sort_by { |_k, v| v }

            sorted_sections.each_with_index do |(section_key, section_idx), i|
              if i == 0
                # 最初のセクション: ヘッダーの末尾から空行までを抽出
                comments = extract_comments_before_index(header_lines, header_lines.length)
                section_comments[section_key] = comments
              else
                # 2番目以降のセクション: 前のセクションの終わりから現在のセクションまで
                prev_section_idx = sorted_sections[i - 1][1]
                between_lines = lines[(prev_section_idx + 1)...section_idx]
                comments = extract_comments_before_index(between_lines, between_lines.length)
                section_comments[section_key] = comments
              end
            end

            # ヘッダーからセクションコメントを除去
            first_section_key = sorted_sections.first[0]
            first_section_comments = section_comments[first_section_key] || []
            header_without_section_comments = header_lines.dup
            first_section_comments.each do |comment|
              # 末尾から削除
              idx = header_without_section_comments.rindex(comment)
              header_without_section_comments.delete_at(idx) if idx
            end
            # 末尾の空行を除去
            header_without_section_comments.pop while header_without_section_comments.last&.strip&.empty?

            {
              header: header_without_section_comments.join("\n"),
              section_comments: section_comments,
              footer: footer_lines.join("\n")
            }
          end

          # 配列の末尾から、空行で区切られた直前のコメント行のみを抽出（非破壊的）
          # 空行があった場合、その前のコメントは含めない
          def extract_comments_before_index(lines, _end_idx)
            return [] if lines.empty?

            comments = []
            found_empty = false

            lines.reverse_each do |line|
              if line.strip.empty?
                # 空行に到達 → これより前は含めない
                found_empty = true
                break
              elsif line.start_with?('#')
                comments.unshift(line)
              else
                # コメントでも空行でもない → 終了
                break
              end
            end

            # 空行が見つからず全てがコメントだった場合、最後のコメントブロックのみ返す
            comments
          end

          # コメントを保持しながら YAML を生成
          def generate_yaml_preserving_comments(catalog, comment_structure)
            lines = []

            # ヘッダーコメント
            header = comment_structure[:header]
            unless header.empty?
              lines << header
              lines << '' # ヘッダー後に空行
            end

            section_comments = comment_structure[:section_comments]

            CatalogLoader::SECTION_KEYS.each do |section|
              # セクションコメント
              comments = section_comments[section] || default_section_comments[section] || []
              comments.each { |c| lines << c }

              # セクションキーと値
              items = catalog[section] || []
              lines << "#{section}:"

              items.each do |item|
                if item.is_a?(String)
                  lines << "  - #{item}"
                elsif item.is_a?(Hash)
                  # 部タイトル付きの場合
                  item.each do |title, sub_items|
                    lines << "  - #{title}:"
                    sub_items.each { |sub| lines << "      - #{sub}" } if sub_items.is_a?(Array)
                  end
                end
              end

              lines << '' # セクション間に空行
            end

            # フッターコメント
            footer = comment_structure[:footer]
            lines << footer unless footer.empty?

            lines.join("\n")
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
              'APPENDICES' => ['# ## 付録'],
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
