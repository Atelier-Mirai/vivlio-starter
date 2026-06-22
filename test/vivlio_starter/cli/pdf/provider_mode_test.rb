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

      # プラグインがロード可能な環境では Enhanced モードへ自動的に切り替わることを検証する。
      # （`gem install vivlio-starter-pdf` 済みなら provider.rb が system gem を注入して有効化する）
      def test_enhanced_mode_when_plugin_loadable
        skip 'vivlio-starter-pdf が利用できない環境のためスキップ' unless plugin_loadable?

        with_plugin_env(nil) do
          assert_equal(:enhanced, VivlioStarter::Pdf.detect_mode)
          assert_instance_of(VivlioStarter::Pdf::EnhancedProvider, VivlioStarter::Pdf.build_provider)
        end
      end

      # プラグインがロードできない環境では Standard モードへフォールバックすることを検証する。
      def test_standard_mode_when_plugin_unavailable
        skip 'この環境では vivlio-starter-pdf がロード可能なためスキップ' if plugin_loadable?

        with_plugin_env(nil) do
          assert_equal(:standard, VivlioStarter::Pdf.detect_mode)
          assert_instance_of(VivlioStarter::Pdf::StandardProvider, VivlioStarter::Pdf.build_provider)
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
