# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/replace_rotate_tables.rb
# ================================================================
# 責務:
#   回転した表を、PDF のページの画像へ差し替える
# ================================================================

require 'fileutils'
require_relative '../../epub/workspace'
require_relative '../../rotate_table_images'
require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 回転した表を、PDF のページの画像へ差し替える
      module Transforms::Kindle::ReplaceRotateTables
        module_function

        # ================================================================
        # 回転テーブル → 画像（Kindle 専用・kindle-rotate-table-image-spec.md）
        # ================================================================

        # `.rotate-table` の中身を、PDF で組まれた当該ページの画像へ差し替える。
        #
        # KFX は `transform` も `position: absolute` も解さないため、CSS による 90 度回転は
        # 宣言ごと無視されて素の表に戻る。列が詰まって折り返し、横長の表は見切れる。
        # PDF のページを切り出せば **PDF と寸分違わぬ見た目**が手に入る。
        #
        # 画像を用意するのは PDF 枝（`extract rotate table images`）で、ここでは待って使うだけ。
        # 枝が並列に走るため待たないと「まだ無い」を「PDF が無い」と誤認する。
        #
        # クリーン EPUB は対象外。あちらは回転が効いており、画像化すると拡大時に劣化する。
        def call(html_files, _ctx)
          RotateTableImages.wait_until_ready!
          targets = html_files.select { |path| File.read(path, encoding: 'utf-8').include?('rotate-table') }
          return html_files if targets.empty?

          replaced = targets.count { |path| replace_rotate_tables_in_file!(path) }
          Common.log_info("[EPUB] 回転テーブルを画像へ差し替えました（#{replaced} ファイル）") if replaced.positive?
          html_files
        end

        # 1 ファイル分の `.rotate-table` を画像へ差し替える。
        # 画像が無いラッパは素の表のまま残す（RotateTableImages が理由を 🟡 で案内済み）。
        def replace_rotate_tables_in_file!(path)
          doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
          wrappers = doc.css('div.rotate-table')
          return false if wrappers.empty?

          changed = wrappers.count { |wrapper| swap_rotate_table_with_image!(wrapper, path) }
          return false if changed.zero?

          PostProcessCommands::HtmlParser.save_html_document(path, doc)
          true
        end

        # ラッパ 1 つを `<img>` へ置き換える。差し替えたら true。
        def swap_rotate_table_with_image!(wrapper, html_path)
          anchor_id = wrapper['id'].to_s
          return false unless RotateTableImages.available?(anchor_id)

          staged = stage_rotate_table_image(anchor_id, File.dirname(html_path))
          return false unless staged

          alt = rotate_table_alt_text(wrapper)
          wrapper.children.unlink
          wrapper.add_child(%(<img src="#{staged}" alt="#{escape_html_attribute(alt)}" class="vs-rotate-table-image"/>))
          true
        end

        # 画像の alt に入れる表のプレーンテキスト（読み上げ・検索のフォールバック）。
        # 数式画像が alt に TeX を入れているのと同じ扱い。
        #
        # `wrapper.text` をそのまま使うとセルの境目が消えて「スキルレベルリモート勤務」と
        # 繋がってしまうため、セル・キャプション単位で拾って空白で継ぐ。
        def rotate_table_alt_text(wrapper)
          cells = wrapper.css('caption, th, td, p').map { it.text.gsub(/\s+/, ' ').strip }.reject(&:empty?)
          text = cells.empty? ? wrapper.text : cells.join(' ')
          text.gsub(/\s+/, ' ').strip
        end

        # 生成済み画像を消費者 dir の images/_epub_assets/ へ写し、HTML からの相対パスを返す。
        # 著者 dir を汚さないのは他の生成画像と同じ方針（P4 §5.3）。
        def stage_rotate_table_image(anchor_id, base_dir)
          source = RotateTableImages.image_path(anchor_id)
          rel = File.join('images', Epub::Workspace::EPUB_ASSETS_REL_SUBDIR, "#{anchor_id}.png")
          destination = File.join(base_dir, rel)
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(source, destination)
          rel
        rescue StandardError => e
          Common.log_warn("[EPUB] 回転テーブル画像を配置できませんでした（#{anchor_id}）: #{e.message}")
          nil
        end

        # alt 属性へ埋める文字列のエスケープ（属性値として壊れないことだけを担保する）。
        def escape_html_attribute(text)
          text.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
        end
      end
    end
  end
end
