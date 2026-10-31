# frozen_string_literal: true

require_relative 'catalog_loader'

# ================================================================
# File: lib/vivlio_starter/cli/build/catalog_updater.rb
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

module VivlioStarter
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
        #
        # 分冊（VOLUMES）の目次では、巻を選んでその巻の区分に足す。volume を省くと、番号が一つ前の
        # 原稿を載せた巻に足す。巻の境目の番号は前の巻に入り、一つ前が無ければ最初の巻に足す（改善案 #126）
        # @param basename [String] 追加する章の basename（拡張子なし）
        # @param volume [Volumes::Volume, nil] 足す巻（VOLUMES の目次のときだけ使う）
        def add_chapter(basename, volume: nil)
          unless File.exist?(CATALOG_FILE)
            create_initial_catalog_with(basename)
            Common.log_info("catalog.yml を作成し #{basename} を追加しました")
            return
          end

          lines = read_catalog_lines
          section = section_for_basename(basename)

          range = nil
          chosen = !volume.nil?
          if Volumes.enabled?
            volume ||= volume_for_new_entry(basename, section)
            range = volume && volume_line_ranges(lines)[volume.index]
          end

          # 既にアクティブ（非コメント）として存在する場合はスキップ。巻を指定されたときは、その巻に
          # 載っているかだけを見る（二つ以上の巻に載る章を、巻ごとに足すため）
          return if active_entry_exists?(lines, basename, within: (range if chosen))

          insert_idx, indent = find_text_insertion_point(lines, section, basename, range:)
          lines.insert(insert_idx, "#{indent}- #{basename}")
          write_catalog_lines(lines)
          where = volume ? "#{volume.name}の#{section}" : section
          Common.log_info("catalog.yml に #{basename} を追加しました（#{where}）")
        end

        # 章を catalog.yml から削除（分冊の目次では、載っているすべての巻から外す）
        # @param basename [String] 削除する章の basename（拡張子なし）
        def remove_chapter(basename)
          return unless File.exist?(CATALOG_FILE)

          lines = read_catalog_lines
          indexes = active_entry_lines(lines, basename)
          return if indexes.empty?

          indexes.reverse_each { lines.delete_at(it) }
          write_catalog_lines(lines)
          Common.log_info("catalog.yml から #{basename} を削除しました")
        end

        # 章の basename を変更
        #
        # 番号の範囲に合った区分に書かれていた章は、新しい番号の区分へ移す（`vs rename 05-x 92-x` で付録へ）。
        # 範囲の外の番号で書かれていた章（PREFACE の `20-vol2-intro`）は、著者が区分を選んで書いたものなので、
        # 区分を動かさずに名前だけ書き換える（catalog-section-kind-spec.md §4.4）
        # @param old_basename [String] 旧 basename
        # @param new_basename [String] 新 basename
        def rename_chapter(old_basename, new_basename)
          return unless File.exist?(CATALOG_FILE)

          old_section = section_for_basename(old_basename)
          new_section = section_for_basename(new_basename)
          written_section = CatalogLoader.load_labeled_entries.find { it.basename == old_basename }&.section

          if old_section == new_section || (written_section && written_section != old_section)
            # 同一セクション内: 行内の basename を置換（分冊の目次では、載っているすべての巻で）
            lines = read_catalog_lines
            indexes = active_entry_lines(lines, old_basename)
            unless indexes.empty?
              indexes.each { lines[it] = renamed_entry_line(lines[it], old_basename, new_basename) }
              write_catalog_lines(lines)
              Common.log_info("catalog.yml: #{old_basename} → #{new_basename}")
            end
          else
            # セクション変更: 削除 → 追加（分冊の目次では、載っていたそれぞれの巻の中で移す。
            # 共通の付録を本文の章にしても、どの巻からも消えない）
            volumes = Volumes.enabled? ? Volumes.list.select { Volumes.basenames_of(it).include?(old_basename) } : []
            remove_chapter(old_basename)
            if volumes.empty?
              add_chapter(new_basename)
            else
              volumes.each { add_chapter(new_basename, volume: it) }
            end
            Common.log_info("catalog.yml: #{old_basename} → #{new_basename}（#{old_section} → #{new_section}）")
          end
        end

        # 章の basename をまとめて変更する（vs renumber）。1 章ずつ書き換えると、番号だけの項目が
        # 連鎖して動く（`--step 2` の 12→13・13→15 で、`- 12` が 13 を経て 15 になる）ので、
        # 書き換える前の行を対応表と一度に照らす。改番は区分の内側でしか番号を振らないので、区分は動かさない
        # @param renames [Hash{String => String}] 旧 basename => 新 basename
        def rename_chapters(renames)
          return rename_chapter(*renames.first) if renames.size == 1
          return unless File.exist?(CATALOG_FILE)

          lines = read_catalog_lines
          changed = lines.each_index.filter_map do |index|
            old_basename = renames.keys.find { entry_line?(lines[index], it) } or next
            lines[index] = renamed_entry_line(lines[index], old_basename, renames[old_basename])
          end
          return if changed.empty?

          write_catalog_lines(lines)
          Common.log_info("catalog.yml の #{changed.size} 行を新しい章名に書き換えました")
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
          File.write(CATALOG_FILE, "#{lines.join("\n")}\n", encoding: 'utf-8')
        end

        # ================================================================
        # Private: 行検索
        # ================================================================

        # 項目の行（`- 22-extensions`・`- 22-extensions.md`・`- 22`）。行末の注釈は除く
        ENTRY_LINE = /\A\s*-\s+(?<item>[^\s#]+)\s*(?:#.*)?\z/

        # その章を指す項目の行か。名前のほか、番号だけの項目（`- 22`）もその番号の原稿を指す
        # （contents/22.md のように番号だけの原稿もあるので、番号の項目も章の名前の一つ）
        def entry_line?(line, basename)
          item = line[ENTRY_LINE, :item] or return false
          return true if [basename, "#{basename}.md"].include?(item)

          number = CatalogLoader.extract_chapter_number(basename)
          item.match?(/\A\d+\z/) && !number.nil? && item.to_i == number
        end

        # 項目の行を新しい章名に書き換える。番号だけの項目は番号だけを書き換え、書き方を保つ
        def renamed_entry_line(line, old_basename, new_basename)
          item = line[ENTRY_LINE, :item]
          return line.sub(old_basename, new_basename) unless item&.match?(/\A\d+\z/)

          new_number = new_basename[/\A\d+/] or return line.sub(item, new_basename)
          line.sub(/(-\s+)#{item}/) { "#{Regexp.last_match(1)}#{new_number}" }
        end

        # アクティブ（非コメント）エントリ行のインデックスをすべて返す（分冊の目次では、共通の付録が二つ以上の巻に載る）
        # @return [Array<Integer>]
        def active_entry_lines(lines, basename)
          lines.each_index.select { entry_line?(lines[it], basename) }
        end

        # アクティブエントリとして存在するかチェック
        # @param within [Range, nil] 探す行の範囲（分冊の目次では巻の行。nil ならファイル全体）
        def active_entry_exists?(lines, basename, within: nil)
          (within || lines.each_index).any? { entry_line?(lines[it], basename) }
        end

        # ================================================================
        # Private: 分冊（VOLUMES）
        # ================================================================

        # 巻ごとの行の範囲（VOLUMES の項目の並び順＝ Volumes.list の順）
        # @return [Array<Range>]
        def volume_line_ranges(lines)
          header = lines.index { it.strip == "#{Volumes::KEY}:" && !it.start_with?(' ') }
          return [] unless header

          block_end = ((header + 1)...lines.length).find { lines[it].match?(/\A[^\s#]/) } || lines.length
          starts = ((header + 1)...block_end).select { lines[it].match?(/\A\s*-\s+\w+:/) }
          item_indent = starts.map { lines[it][/\A\s*/].size }.min
          starts = starts.select { lines[it][/\A\s*/].size == item_indent }
          starts.each_with_index.map do |start, index|
            (start..((starts[index + 1] || block_end) - 1))
          end
        end

        # 新しい原稿を足す巻: 同じ区分で、番号が一つ前の原稿を載せた巻。無ければ最後の巻
        # @return [Volumes::Volume, nil]
        def volume_for_new_entry(basename, section)
          num = CatalogLoader.extract_chapter_number(basename) || 0
          volumes = Volumes.list
          lower = volumes.flat_map do |volume|
            CatalogLoader.flatten_section(volume.sections[section]).filter_map do
              n = CatalogLoader.extract_chapter_number(it)
              [n, volume] if n && n < num
            end
          end
          lower.max_by(&:first)&.last || volumes.first
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
        # @param range [Range, nil] 探す行の範囲（分冊の目次では巻の行。nil ならファイル全体）
        # @return [Array(Integer, Integer)] [開始行, 終了行]
        def find_section_boundaries(lines, section, range: nil)
          range ||= (0...lines.length)
          start_idx = range.find { lines[it].strip == "#{section}:" }
          return [nil, nil] unless start_idx

          # 次のセクションヘッダー（分冊の目次では、巻の終わり）を探す
          next_section_idx = ((start_idx + 1)..range.max).find do |idx|
            CatalogLoader::SECTION_KEYS.any? { lines[idx].strip == "#{it}:" }
          end

          end_idx = (next_section_idx || (range.max + 1)) - 1

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

          ((section_start + 1)..section_end).each do |idx|
            line = lines[idx]
            next if line.match?(/^\s+#/) # コメント行はスキップ

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

        # テキスト内の挿入位置とインデントを計算。
        # 字下げは区分の見出しから数える（分冊の目次では、巻の中の区分が一段深い）
        # @param range [Range, nil] 巻の行の範囲（分冊の目次のとき）
        # @return [Array(Integer, String)] [挿入行インデックス, インデント文字列]
        def find_text_insertion_point(lines, section, basename, range: nil)
          num = CatalogLoader.extract_chapter_number(basename) || 0
          section_start, section_end = find_section_boundaries(lines, section, range:)

          # セクションが見つからない場合、末尾（分冊の目次では巻の終わり）にセクションヘッダーを追加
          unless section_start
            return append_section_header(lines, section) unless range

            base = lines[range.min][/\A\s*/].size + 2
            lines.insert(range.max + 1, "#{' ' * base}#{section}:")
            return [range.max + 2, ' ' * (base + 2)]
          end

          base = ' ' * lines[section_start][/\A\s*/].size

          # 部タイトル構造を検出
          parts = detect_part_ranges(lines, section_start, section_end)

          if parts.any?
            target = determine_target_part(lines, parts, num)
            if target
              return find_sorted_insert_in_range(
                lines, target[:content_start], target[:end], num, "#{base}      "
              )
            end
          end

          # フラットなセクション
          find_sorted_insert_in_range(lines, section_start + 1, section_end, num, "#{base}  ")
        end

        # ファイル末尾に区分の見出しを足す
        def append_section_header(lines, section)
          lines << ''
          lines << "#{section}:"
          [lines.length, '  ']
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
          File.write(CATALOG_FILE, "#{output.join("\n")}\n", encoding: 'utf-8')
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
