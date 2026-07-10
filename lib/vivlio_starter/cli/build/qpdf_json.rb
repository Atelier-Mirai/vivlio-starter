# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/qpdf_json.rb
# ================================================================
# 責務:
#   qpdf の JSON v2 表現で PDF の構造を読み、任意のオブジェクトを差分更新する。
#
#   qpdf は構造保存型なので、この経路なら文書カタログの named destinations（`/Dests`）や
#   リンクアノテーションを保ったまま、ページ辞書・内容ストリームだけを書き換えられる
#   （CombinePDF は保存時に `/Dests` を再構築せず全損させる）。
#   Apache-2.0 の外部コマンド呼び出しであり、本体のライセンスには影響しない。
#
# 値の表現:
#   読み出した値をそのまま書き戻せる（参照は "N G R"、名前は "/Name"、文字列は "u:…"）。
#   pdf-reader で読んで書き戻すと名前の再エスケープや日本語の往復で壊れる余地があるため、
#   更新対象の値は必ず本モジュール経由で取得すること。
# ================================================================

require 'fileutils'
require 'json'
require 'open3'
require 'tempfile'

module VivlioStarter
  module CLI
    module Build
      module QpdfJson
        module_function

        # PDF の構造を読む（ストリーム本体は読まないので大きな PDF でも軽い）。
        #
        # @param pdf_path [String]
        # @return [Array(Hash, Hash, Array<Hash>), nil] [header, objects, pages]。失敗時 nil
        def read(pdf_path)
          unless File.exist?(pdf_path)
            Common.log_warn("[qpdf] PDF が見つかりません: #{pdf_path}")
            return nil
          end

          out, status = Open3.capture2('qpdf', pdf_path, '--json=2', '--json-key=qpdf',
                                       '--json-key=pages', '--json-stream-data=none')
          unless status.success?
            Common.log_warn("[qpdf] PDF 構造を読み取れませんでした: #{pdf_path}")
            return nil
          end

          document = JSON.parse(out)
          header, objects = document['qpdf']
          [header, objects, document['pages']]
        rescue StandardError => e
          Common.log_warn("[qpdf] PDF 構造の取得に失敗: #{e.message}")
          nil
        end

        # 差分更新を適用し、元ファイルを置き換える。
        #
        # @param pdf_path [String] 更新対象（成功時に上書きされる）
        # @param header [Hash] read で得たヘッダ（maxobjectid 等）
        # @param updates [Hash] "obj:N G R" => {"value"|"stream" => …} のマップ
        # @return [Boolean]
        def apply!(pdf_path, header, updates)
          Tempfile.create(['vs-qpdf-update', '.json']) do |json|
            json.write(JSON.generate({ 'version' => 2, 'qpdf' => [header, updates] }))
            json.flush

            updated = "#{pdf_path}.qpdf.tmp.pdf"
            success = system('qpdf', pdf_path, updated, "--update-from-json=#{json.path}",
                             out: File::NULL, err: File::NULL)

            if success && File.exist?(updated)
              FileUtils.mv(updated, pdf_path)
              true
            else
              FileUtils.rm_f(updated)
              Common.log_warn('[qpdf] --update-from-json の適用に失敗しました')
              false
            end
          end
        end
      end
    end
  end
end
