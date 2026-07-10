# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/print_geometry.rb
# ================================================================
# 責務:
#   閲覧用（トリムサイズ）PDF を、入稿用（塗り足し＋トンボ代付き）のページ
#   ジオメトリへ変換する。「pdf ＋トンボ＝ print_pdf」単一系列の中核。
#
# なぜ qpdf の差分更新なのか:
#   PDF のリンクは「クリック領域（アノテーション）」と「名前 → 実ページの対応表
#   （文書カタログの /Dests 辞書）」の 2 部品でできている。vivliostyle のリンクは
#   named destination 参照なので、対応表が消えると全リンクが無反応になる。
#   CombinePDF は保存時に /Dests を再構築しないため全損する。HexaPDF は保持するが
#   AGPL で本体に入れられない。qpdf は構造保存型で、既存オブジェクトを差分更新できる
#   （Apache-2.0・外部コマンドなのでライセンス感染もない）。詳細は QpdfJson を参照。
#
# 2 段構成（expand! → 3b は finalize_boxes!）:
#   qpdf --overlay は重ねる側を「宛先ページの TrimBox（無ければ CropBox）に収まるよう
#   拡大縮小してセンタリング」する（仕様 §3.8 で実測）。TrimBox を書いた後にトンボ・
#   ノンブルを重ねると約 0.85 倍に縮小されて仕上がり線の内側へ入り込むため、
#   ボックスの確定は overlay がすべて済んだ後に行う:
#     expand!         … 内容シフト＋MediaBox 拡張（TrimBox/BleedBox は書かない）
#     （トンボ・ノンブルの overlay — CropMarksOverlay / NombreStamper）
#     finalize_boxes! … TrimBox / BleedBox を確定
#
# expand! の変換内容（ページごと）:
#   - 内容を (dx, dy) 平行移動（共有ストリーム "q 1 0 0 1 dx dy cm" / "Q" で挟む）
#   - MediaBox を原点 0 の拡大版に再定義
#   - トリムサイズの残骸である CropBox / ArtBox は削除（ずれたまま残ると入稿事故）
#   - アノテーションの Rect / QuadPoints / 直接 destination を (dx, dy) シフト
#   - /Dests 辞書の XYZ / FitH / FitV / FitR 系座標を、参照先ページの (dx, dy) でシフト
#
# (dx, dy) の求め方:
#   Chrome 出力の MediaBox 原点には ±0.3pt のジッタがある（例 [0, 0.03, …]）。
#   元の可視領域 [ox, oy] を新ページの [m, m] に一致させたいので、
#   dx = m − ox, dy = m − oy とする（m = 塗り足し ＋ トンボ代）。
#   内容・アノテーション・destination はすべて同じ (dx, dy) で動かす。
# ================================================================

require_relative '../units'
require_relative 'qpdf_json'

module VivlioStarter
  module CLI
    module Build
      class PrintGeometry
        # 座標の丸め桁。PDF の実用精度（1/10000 pt）で十分。
        PRECISION = 4

        # 座標シフトの対象になる destination 種別 → シフトする要素の添字と軸。
        # 添字は destination 配列（[page, /Kind, …]）先頭からの位置。
        # /Fit・/FitB は座標を持たないため対象外。
        DEST_SHIFT_AXES = {
          '/XYZ' => { 2 => :x, 3 => :y },
          '/FitH' => { 2 => :y },
          '/FitBH' => { 2 => :y },
          '/FitV' => { 2 => :x },
          '/FitBV' => { 2 => :x },
          '/FitR' => { 2 => :x, 3 => :y, 4 => :x, 5 => :y }
        }.freeze

        # @param pdf_path [String] 変換対象（成功時に上書きされる）
        # @param bleed_mm [Numeric] 塗り足し幅（mm）
        # @param crop_offset_mm [Numeric] トンボ代（mm・塗り足しの外側）
        # @return [Boolean] 変換に成功したか
        def self.expand!(pdf_path, bleed_mm:, crop_offset_mm:)
          new(pdf_path, bleed_mm:, crop_offset_mm:).expand!
        end

        # @return [Boolean] ボックスの書き込みに成功したか
        def self.finalize_boxes!(pdf_path, bleed_mm:, crop_offset_mm:)
          new(pdf_path, bleed_mm:, crop_offset_mm:).finalize_boxes!
        end

        def initialize(pdf_path, bleed_mm:, crop_offset_mm:)
          @pdf_path = pdf_path
          @bleed_pt  = bleed_mm.to_f * Units::PT_PER_MM
          @margin_pt = (bleed_mm.to_f + crop_offset_mm.to_f) * Units::PT_PER_MM
        end

        # 手順 3a: 内容シフトと MediaBox 拡張（TrimBox / BleedBox はまだ書かない）。
        # 変換できない PDF（回転ページ・変換済み）を検出した場合は何も書き換えずに
        # false を返す。呼び出し側は従来のレンダリング経路へ退避する。
        def expand!
          # --- Phase: 構造の取得 ---
          header, objects, pages = QpdfJson.read(pdf_path)
          return false unless pages

          # --- Phase: 変換可否の判定 ---
          return false unless convertible?(pages, objects)

          # --- Phase: 更新差分の構築 ---
          updates = build_updates(pages, objects, header['maxobjectid'].to_i)

          # --- Phase: qpdf による差分適用 ---
          QpdfJson.apply!(pdf_path, header, updates)
        end

        # 手順 3b: TrimBox / BleedBox の確定。トンボ・ノンブルの overlay がすべて
        # 済んだ後に呼ぶこと（先に書くと qpdf --overlay が重ねる側を TrimBox に
        # 合わせて縮小配置してしまう。§3.8）。
        # expand! 後の MediaBox は原点 0 に正規化済みなので、仕上がり線は
        # ページ寸法から Trim = [m, m, W−m, H−m] の定型で決まる。
        def finalize_boxes!
          header, objects, pages = QpdfJson.read(pdf_path)
          return false unless pages

          m = margin_pt
          b = bleed_pt
          updates = pages.to_h do |page|
            key = "obj:#{page['object']}"
            value = objects[key]['value'].dup
            _, _, width, height = value['/MediaBox'].map(&:to_f)
            value['/TrimBox']  = round_all([m, m, width - m, height - m])
            value['/BleedBox'] = round_all([m - b, m - b, width - m + b, height - m + b])
            [key, { 'value' => value }]
          end

          QpdfJson.apply!(pdf_path, header, updates)
        end

        private

        attr_reader :pdf_path, :bleed_pt, :margin_pt

        # 導出可能なページ構成かを検証する。
        # 回転ページ（Chrome 出力は常に /Rotate 0）と、すでに塗り足し済みのページを弾く。
        def convertible?(pages, objects)
          return false if pages.nil? || pages.empty?

          pages.each do |page|
            value = objects["obj:#{page['object']}"]&.fetch('value', nil)
            return false unless value

            if value['/Rotate'].to_i != 0
              Common.log_warn('[print geometry] /Rotate が 0 でないページがあるため導出を中止します')
              return false
            end

            trim = value['/TrimBox']
            next if trim.nil? || trim == value['/MediaBox']

            Common.log_warn('[print geometry] すでに TrimBox を持つページがあるため導出を中止します（二重適用防止）')
            return false
          end

          true
        end

        # ページ・アノテーション・/Dests・共有ストリームの更新差分を組み立てる。
        # @return [Hash] qpdf 更新 JSON の "obj:N G R" => {...} マップ
        def build_updates(pages, objects, max_object_id)
          updates = {}
          deltas = {}         # ページ参照 "N 0 R" → [dx, dy]
          shift_refs = {}     # [dx, dy] → 平行移動ストリームの参照文字列
          next_id = max_object_id

          # 内容を閉じる "Q" は全ページ共通。平行移動 "cm" は Chrome の原点ジッタ分だけ
          # 種類が増えるが、実際には 1〜数種に収まるので (dx, dy) ごとに 1 本共有する。
          restore_ref = "#{next_id += 1} 0 R"
          updates["obj:#{restore_ref}"] = content_stream("\nQ")

          # --- Phase: ページごとのボックス・内容・アノテーション ---
          pages.each do |page|
            page_ref = page['object']
            value = objects["obj:#{page_ref}"]['value'].dup
            dx, dy = deltas[page_ref] = transform_boxes!(value)

            shift_ref = shift_refs[[dx, dy]] ||= begin
              ref = "#{next_id += 1} 0 R"
              updates["obj:#{ref}"] = content_stream("q 1 0 0 1 #{dx} #{dy} cm\n")
              ref
            end

            value['/Contents'] = [shift_ref, *page['contents'], restore_ref]
            updates["obj:#{page_ref}"] = { 'value' => value }

            shift_annotations!(value, objects, updates, dx, dy)
          end

          # --- Phase: named destinations（1 オブジェクト丸ごと更新） ---
          shift_dests!(objects, updates, deltas)

          updates
        end

        # ページの MediaBox を原点 0 の拡大版へ差し替え、内容の平行移動量を返す。
        # TrimBox / BleedBox はここでは書かない（overlay 後の finalize_boxes! が担当）。
        # @return [Array(Float, Float)] (dx, dy)
        def transform_boxes!(value)
          ox, oy, x1, y1 = value['/MediaBox'].map(&:to_f)
          width  = x1 - ox
          height = y1 - oy
          m = margin_pt

          value['/MediaBox'] = round_all([0, 0, width + (2 * m), height + (2 * m)])
          # トリムサイズのまま残ると仕上がり位置を誤らせる・overlay の縮小配置を誘発する
          # ため削除する（閲覧用に Chrome が書く CropBox、Prawn 由来の ArtBox 等が該当。
          # TrimBox は convertible? が「無い or MediaBox と同値」を保証済み）。
          %w[/CropBox /ArtBox /TrimBox /BleedBox].each { value.delete(it) }

          [(m - ox).round(PRECISION), (m - oy).round(PRECISION)]
        end

        # ページのアノテーション（リンクのクリック領域）の座標をシフトする。
        # /Annots は「参照の配列」「参照された配列」「直接埋め込み辞書」のいずれもあり得る。
        def shift_annotations!(page_value, objects, updates, dx, dy)
          annots = page_value['/Annots']
          annots = objects["obj:#{annots}"]['value'] if annots.is_a?(String)

          Array(annots).each do |annot|
            case annot
            in String => ref # 間接参照 → アノテーション自体を更新（同一参照の二重シフトを防ぐ）
              key = "obj:#{ref}"
              next if updates.key?(key)

              updates[key] = { 'value' => shift_annotation(objects[key]['value'].dup, dx, dy) }
            in Hash # 直接埋め込み → ページ側の値を破壊的に更新
              shift_annotation(annot, dx, dy)
            else nil
            end
          end
        end

        # 1 つのアノテーション辞書の座標をシフトする（引数を書き換えて返す）。
        def shift_annotation(annot, dx, dy)
          annot['/Rect'] = shift_alternating(annot['/Rect'], dx, dy) if annot['/Rect']
          annot['/QuadPoints'] = shift_alternating(annot['/QuadPoints'], dx, dy) if annot['/QuadPoints']
          # 名前参照（vivliostyle の通常経路）は /Dests 側で処理するので触らない。
          # インライン destination 配列を持つアノテーションのみここでシフトする。
          annot['/Dest'] = shift_destination(annot['/Dest'], dx, dy) if annot['/Dest'].is_a?(Array)
          annot
        end

        # 文書カタログの /Dests 辞書（vivliostyle が全アンカーを書き出す対応表）を
        # 参照先ページごとの (dx, dy) でシフトする。
        def shift_dests!(objects, updates, deltas)
          catalog_key, catalog = objects.find { |_, obj| obj['value'].is_a?(Hash) && obj['value']['/Type'] == '/Catalog' }
          return unless catalog

          dests = catalog['value']['/Dests']
          return if dests.nil?

          # /Dests は間接参照（vivliostyle）でも直接辞書でもあり得る
          if dests.is_a?(String)
            key = "obj:#{dests}"
            updates[key] = { 'value' => shifted_dests(objects[key]['value'], deltas) }
          else
            value = catalog['value'].dup
            value['/Dests'] = shifted_dests(dests, deltas)
            updates[catalog_key] = { 'value' => value }
          end
        end

        # 名前 → destination 配列のマップ全体をシフトした新しいマップを返す。
        def shifted_dests(dests, deltas)
          dests.to_h do |name, dest|
            # dest が間接参照の場合は座標を持たないためそのまま（vivliostyle は直接配列）
            next [name, dest] unless dest.is_a?(Array)

            dx, dy = deltas[dest.first] || [0, 0]
            [name, shift_destination(dest, dx, dy)]
          end
        end

        # destination 配列 [page, /Kind, 座標…] の座標要素だけをシフトする。
        # zoom などの null はそのまま残す（null をシフトすると destination が壊れる）。
        def shift_destination(dest, dx, dy)
          axes = DEST_SHIFT_AXES[dest[1]]
          return dest unless axes

          shifted = dest.dup
          axes.each do |index, axis|
            original = dest[index]
            next unless original.is_a?(Numeric)

            shifted[index] = (original + (axis == :x ? dx : dy)).round(PRECISION)
          end
          shifted
        end

        # [x, y, x, y, …] 形式の座標列（Rect / QuadPoints）を交互にシフトする。
        def shift_alternating(numbers, dx, dy)
          numbers.each_with_index.map { |n, i| (n.to_f + (i.even? ? dx : dy)).round(PRECISION) }
        end

        # 新規に追加する内容ストリーム（辞書なし・素の bytes）
        # qpdf の更新 JSON はストリーム本体を base64 で受け取る
        # （base64 gem は Ruby 3.4 で default gem から外れたため pack で符号化する）
        def content_stream(data)
          { 'stream' => { 'dict' => {}, 'data' => [data].pack('m0') } }
        end

        def round_all(numbers) = numbers.map { it.round(PRECISION) }
      end
    end
  end
end
