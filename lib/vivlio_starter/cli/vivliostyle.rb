# frozen_string_literal: true

module VivlioStarter
  module CLI
    # ==============================================================================
    # Module: VivliostyleCommands
    # ------------------------------------------------------------------------------
    # book.yml のページ設定を Vivliostyle CLI 向けの値へ変換するヘルパー群。
    # ==============================================================================
    module VivliostyleCommands
      module_function

      # book.yml のページ設定から Vivliostyle CLI 用サイズ文字列を解決する
      # @param config [Data] Common::CONFIG（テストでは Common.wrap_config で包んだ設定）
      # @return [String] 'A5', 'B5', 'A4', または '148mm 210mm' 形式
      def resolve_vivliostyle_size(config)
        page_cfg = config.page
        return 'A5' unless page_cfg

        # プリセットから解決された size キーがあればそのまま使う
        # （版面キーはプリセット由来で存在保証がないため [] で参照する）
        size_name = page_cfg[:size].to_s.strip.upcase
        return size_name unless size_name.empty?

        # size キーがない場合は width × height から組み立てる
        w, h = Common.resolve_page_size(page_cfg.to_h)
        "#{w} #{h}"
      end
    end
  end
end
