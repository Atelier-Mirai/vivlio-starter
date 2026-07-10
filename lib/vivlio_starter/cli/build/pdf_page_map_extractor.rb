# frozen_string_literal: true

# ================================================================
# Class: PdfPageMapExtractor
# ================================================================
# 責務:
#   Step 7 が生成した `_sections.pdf` から「アンカー ID → 通しページ番号」の
#   マップを取り出す。backlink dedup（Step 8）の判定材料になる。
#
# なぜ PDF から読めるのか:
#   vivliostyle build は、id を持つ全要素の named destination を PDF 文書カタログの
#   `/Dests` 辞書に書き出す。名前には元 URL とアンカー ID がそのまま埋まっており
#   （例: `viv-id-http://…/00-preface.html#gls-src-00-preface-pdf-2`）、
#   値の destination 配列から実ページを解決できる。
#
#   従来はこの情報を得るために vivliostyle preview をヘッドレス起動し、Playwright で
#   全ページのレンダリング完了を待って DOM を走査していた（409 ページで約 73 秒）。
#   PDF を pdf-reader で読めば同じ情報が 0.5 秒で、しかも「実際に組まれた PDF」から
#   決定的に得られる（preview レンダと build レンダの改ページ差にも影響されない）。
#
# 出力:
#   BacklinkDeduplicator をそのまま使えるよう、PageMapping / MappingEntry /
#   IndexMappingEntry を本クラスが提供する。spine_index は 0 固定でよい
#   （Deduplicator は (spine_index, page_index) を同一ページ判定のキーにしか使わず、
#   vivliostyle は spine 文書ごとに改ページするため通しページ番号 1 本で等価）。
# ================================================================

require 'pdf/reader'
require 'time'

module VivlioStarter
  module CLI
    module Build
      # 生成済み PDF の named destinations からページマッピングを抽出する
      class PdfPageMapExtractor
        # 抽出結果を保持する Data オブジェクト
        PageMapping = Data.define(:mappings, :index_mappings, :total_pages, :extracted_at)

        # 用語集リンク（gls-src-*）のマッピングエントリ
        MappingEntry = Data.define(:anchor_id, :href, :page_index, :spine_index)

        # 索引語（idx-*）のマッピングエントリ
        IndexMappingEntry = Data.define(:anchor_id, :page_index, :spine_index)

        # vivliostyle が付ける named destination の接頭辞（アンカー ID は最初の `#` 以降）
        GLOSSARY_PREFIX = 'gls-src-'
        INDEX_PREFIX = 'idx-'

        # @param pdf_path [String] `_sections.pdf` のパス
        def initialize(pdf_path)
          @pdf_path = pdf_path
        end

        # @return [PageMapping]
        # @raise [RuntimeError] PDF が無い / named destination が 1 件も取れない場合
        def extract!
          raise "本文 PDF が見つかりません: #{pdf_path}" unless File.exist?(pdf_path)

          reader = ::PDF::Reader.new(pdf_path)
          anchor_to_page = build_anchor_page_map(reader)

          if anchor_to_page.empty?
            raise '本文 PDF に named destinations（/Dests）が見つかりません。' \
                  'vivliostyle の出力仕様が変わった可能性があります'
          end

          Common.log_success("[backlink-dedup] ページマッピングを取得しました（#{anchor_to_page.size} 件）")
          build_page_mapping(anchor_to_page, reader.page_count)
        end

        # vivliostyle の `:XXXX`（UTF-16 コードユニットの 4 桁 hex）エスケープを復号する。
        # 元名前中の `:` や `#` はすべてエスケープされるため、区切りの取り違えは起きない。
        # 想定外の入力では復号せず元文字列を返し、呼び出し側の `#` 判定で自然に捨てられる。
        #
        # @param name [Symbol, String] PDF name
        # @return [String]
        def self.decode_destination_name(name)
          source = name.to_s
          units = []
          i = 0
          while i < source.length
            if source[i] == ':' && source[i + 1, 4]&.match?(/\A\h{4}\z/)
              units << source[i + 1, 4].hex
              i += 5
            else
              units << source[i].ord
              i += 1
            end
          end
          units.pack('U*')
        rescue StandardError
          name.to_s
        end

        private

        attr_reader :pdf_path

        # `/Dests` 辞書を走査し「アンカー ID → 通しページ番号（1..N）」を作る。
        # @return [Hash{String => Integer}]
        def build_anchor_page_map(reader)
          objects = reader.objects
          root = objects.deref(objects.trailer[:Root])
          page_numbers = number_pages(objects, root[:Pages])

          dests = objects.deref(root[:Dests])
          return {} unless dests.respond_to?(:each_pair)

          dests.each_pair.with_object({}) do |(name, dest), map|
            anchor_id = self.class.decode_destination_name(name).split('#', 2)[1]
            next if anchor_id.nil? || anchor_id.empty?

            page = resolve_page_number(objects, dest, page_numbers)
            map[anchor_id] = page if page
          end
        end

        # ページツリーを走査し、ページオブジェクト ID → 通しページ番号を得る
        def number_pages(objects, pages_ref)
          numbers = {}
          walk = lambda do |ref|
            node = objects.deref(ref)
            case node[:Type]
            when :Pages then Array(objects.deref(node[:Kids])).each { walk.call(it) }
            when :Page  then numbers[ref.id] = numbers.size + 1
            end
          end
          walk.call(pages_ref)
          numbers
        end

        # destination（明示配列、または `/D` を持つ辞書）からページ番号を解決する
        def resolve_page_number(objects, dest, page_numbers)
          value = objects.deref(dest)
          value = objects.deref(value[:D]) if value.is_a?(Hash)
          page_ref = Array(value).first
          page_ref.respond_to?(:id) ? page_numbers[page_ref.id] : nil
        end

        # Deduplicator が消費する形（用語集 / 索引の 2 系統）へ振り分ける
        def build_page_mapping(anchor_to_page, total_pages)
          mappings = []
          index_mappings = []

          anchor_to_page.each do |anchor_id, page|
            if anchor_id.start_with?(GLOSSARY_PREFIX)
              mappings << MappingEntry.new(anchor_id:, href: '', page_index: page, spine_index: 0)
            elsif anchor_id.start_with?(INDEX_PREFIX)
              index_mappings << IndexMappingEntry.new(anchor_id:, page_index: page, spine_index: 0)
            end
          end

          PageMapping.new(mappings:, index_mappings:, total_pages:, extracted_at: Time.now.iso8601)
        end
      end
    end
  end
end
