# frozen_string_literal: true

require_relative 'common'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: entries メタデータ抽出ヘルパ
    # ================================================================
    # 提供機能:
    #   - build_entry: HTML から entries 用の { path:, title: } を組み立てる
    #   - extract_html_title: HTML の <title> を抽出する
    #
    # 利用者:
    #   - Build::VivliostyleConfigWriter（workspace の用途別 entries 生成）
    #   - Build::EpubBuilder（EPUB 用 entries 生成）
    #
    # かつての `vs entries`（ルート entries.js の手動生成コマンド）は
    # P4 のワークスペース分離で実体を失ったため撤去した
    # （docs/specs/vivlioverso-manual-flow-removal-spec.md）。
    # ================================================================
    module EntriesCommands
      module_function

      # HTML ファイルから entries 用エントリを組み立てる。
      # タイトルは <title> タグ優先、無ければファイル名の番号を除いた部分。
      # @param html_file [String]
      # @return [Hash] { path: String, title: String }
      def build_entry(html_file)
        base_name = File.basename(html_file, '.html')
        title = base_name
        html_title = extract_html_title(html_file)

        if html_title && !html_title.empty?
          title = html_title
        elsif html_title.to_s.empty? && (base_name =~ /^\d+-(.+)$/)
          title = ::Regexp.last_match(1)
        end

        # パスを相対パス形式に正規化（./を接頭辞として付与）
        normalized_path = html_file.start_with?('./') ? html_file : "./#{html_file}"
        { path: normalized_path, title: title }
      end

      def extract_html_title(path)
        return unless File.exist?(path)

        content = File.read(path)
        ::Regexp.last_match(1).strip if content =~ %r{<title>(.+?)</title>}
      rescue StandardError => e
        # タイトル抽出失敗時はフォールバック名が使われるため、原因をデバッグログに残す
        Common.log_debug("[entries] #{path} のタイトル抽出に失敗: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
