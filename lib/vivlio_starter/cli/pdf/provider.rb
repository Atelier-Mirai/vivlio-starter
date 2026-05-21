# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module Pdf
    # プロバイダのインスタンスを返す（シングルトン）
    # @return [Object] StandardProvider または EnhancedProvider のインスタンス
    def self.provider = @provider ||= load_provider

    # プラグインの有無や環境変数を確認し、適切なプロバイダをロードする
    def self.load_provider
      # --- Phase: Standard mode enforcement ---
      if ENV['VIVLIO_PDF_PLUGIN'] == 'disable'
        require_relative 'standard_provider'
        return StandardProvider.new
      end

      # --- Phase: Enhanced mode attempt ---
      begin
        require 'vivlio_starter/cli/pdf/enhanced_provider'
        VivlioStarter::Pdf::EnhancedProvider.new
      rescue LoadError
        # --- Phase: Standard mode fallback ---
        require_relative 'standard_provider'
        StandardProvider.new
      end
    end
  end
end
