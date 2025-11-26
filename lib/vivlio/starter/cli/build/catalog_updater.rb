# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # CatalogUpdater: catalog.yml の更新処理
        # ------------------------------------------------
        # vs create / delete / rename / renumber コマンドから呼び出され、
        # catalog.yml を自動的に更新する。
        # ------------------------------------------------
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
            if old_section != new_section
              # 新しいセクションに追加
              catalog[new_section] ||= []
              insert_basename_to_section(catalog, new_section, new_basename)
              Common.log_info("catalog.yml: #{old_basename} → #{new_basename}（#{old_section} → #{new_section}）")
            else
              # 同じセクション内でリネーム
              insert_basename_to_section(catalog, old_section, new_basename)
              Common.log_info("catalog.yml: #{old_basename} → #{new_basename}")
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

          private

          module_function

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

          # catalog.yml を保存
          def save_catalog(catalog)
            FileUtils.mkdir_p(File.dirname(CATALOG_FILE))
            File.write(CATALOG_FILE, catalog.to_yaml, encoding: 'utf-8')
          end
        end
      end
    end
  end
end
