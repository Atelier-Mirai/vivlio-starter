# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/pdf/provider'
require 'vivlio_starter/cli/pdf/standard_provider'

module VivlioStarter
  module Pdf
    # プラグイン（vivlio-starter-pdf）の有無・環境変数によって PDF プロバイダの
    # 動作モードが正しく切り替わることを検証する統合テスト。
    #
    # detect_mode / build_provider は副作用なし（メモ化しない）で都度判定するため、
    # グローバルなスタブを用いず、各ケース内で ENV を局所的に設定・復元して検証する。
    class ProviderModeTest < Minitest::Test
      # VIVLIO_PDF_PLUGIN=disable のとき、プラグインの有無に関わらず
      # 常に Standard モードへ強制されることを検証する。
      def test_disable_env_forces_standard_mode
        with_plugin_env('disable') do
          assert_equal(:disabled, VivlioStarter::Pdf.detect_mode)
          assert_instance_of(VivlioStarter::Pdf::StandardProvider, VivlioStarter::Pdf.build_provider)
        end
      end

      # プラグイン（vivlio-starter-pdf）の有無に応じて detect_mode が
      # enhanced / standard を正しく選ぶことを検証する。どちらの環境でも必ず実行できるよう、
      # 実際の利用可否を判定して期待値を切り替える（skip を作らない）。
      # - 導入機（`gem install vivlio-starter-pdf` 済み）: provider.rb が system gem を注入し enhanced
      # - 未導入機（CI 等）: standard へフォールバック
      def test_auto_detects_provider_by_plugin_availability
        with_plugin_env(nil) do
          if plugin_loadable?
            assert_equal(:enhanced, VivlioStarter::Pdf.detect_mode)
            assert_instance_of(VivlioStarter::Pdf::EnhancedProvider, VivlioStarter::Pdf.build_provider)
          else
            assert_equal(:standard, VivlioStarter::Pdf.detect_mode)
            assert_instance_of(VivlioStarter::Pdf::StandardProvider, VivlioStarter::Pdf.build_provider)
          end
        end
      end

      private

      # VIVLIO_PDF_PLUGIN を一時的に設定し、ブロック実行後に元へ復元する。
      # value が nil の場合は環境変数を削除する。
      def with_plugin_env(value)
        original = ENV.fetch('VIVLIO_PDF_PLUGIN', :__unset__)
        if value.nil?
          ENV.delete('VIVLIO_PDF_PLUGIN')
        else
          ENV['VIVLIO_PDF_PLUGIN'] = value
        end
        yield
      ensure
        if original == :__unset__
          ENV.delete('VIVLIO_PDF_PLUGIN')
        else
          ENV['VIVLIO_PDF_PLUGIN'] = original
        end
      end

      # 拡張プロバイダ（プラグイン）がこの環境で利用可能かを確認する。
      # production の detect_mode は Gemfile 未記載でも system インストール済み gem を
      # 注入してロードするため、素の require だけでなく「インストール済みか」も確認して
      # 判定を production と一致させる（bundle サンドボックス下での偽陰性を防ぐ）。
      def plugin_loadable?
        require 'vivlio_starter/cli/pdf/enhanced_provider'
        true
      rescue LoadError
        Gem.path.any? do |home|
          Dir.glob(File.join(home, 'specifications', "#{VivlioStarter::Pdf::PLUGIN_GEM_NAME}-*.gemspec")).any?
        end
      end
    end
  end
end
