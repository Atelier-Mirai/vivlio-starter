# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/chapter_config.rb
# ================================================================
# 責務:
#   章番号レンジで中間 HTML を絞り込む。
#
# かつては book.yml の chapters 指定を解釈する場所でもあったが、章構成の管理が
# config/catalog.yml へ移った（2025-11-26）ため、番号指定のパーサは撤去した。
# ================================================================

module VivlioStarter
  module CLI
    module Build
      # 章 HTML の絞り込みモジュール
      module ChapterConfig
        module_function

        # ディレクトリ内の *.html から、章番号レンジと keep_numbers でフィルタ
        # 注: アンダースコア始まりのファイルは \A(\d+)- パターンにマッチしないため自動的に除外される
        def htmls_for_range(base_dir, range, keep_numbers = nil)
          Dir.glob(File.join(base_dir, '*.html')).select do |path|
            bn = File.basename(path, '.html')
            n = bn[/\A(\d+)-/, 1]&.to_i
            n && range.include?(n) && (keep_numbers.nil? || keep_numbers.include?(n))
          end.sort
        end
      end
    end
  end
end
