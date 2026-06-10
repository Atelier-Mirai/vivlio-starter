# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module Pdf
    # 拡張プラグイン（vivlio-starter-pdf）の gem 名
    PLUGIN_GEM_NAME = 'vivlio-starter-pdf'
    # 拡張プロバイダの require パス（feature 名）
    ENHANCED_PROVIDER_FEATURE = 'vivlio_starter/cli/pdf/enhanced_provider'

    class << self
      # プロバイダのインスタンスを返す（シングルトン）
      # @return [StandardProvider, EnhancedProvider]
      def provider = @provider ||= build_provider

      # 判定したモードに応じてプロバイダを生成する。
      # @return [StandardProvider, EnhancedProvider]
      def build_provider
        case detect_mode
        in :enhanced
          announce_mode(:enhanced)
          EnhancedProvider.new
        in :disabled | :standard => mode
          announce_mode(mode)
          require_relative 'standard_provider'
          StandardProvider.new
        end
      end

      # 動作モードを判定する。
      # - VIVLIO_PDF_PLUGIN=disable が指定されていれば常に :disabled
      # - 拡張プロバイダをロードできれば :enhanced
      # - それ以外は :standard
      # @return [:disabled, :enhanced, :standard]
      def detect_mode
        return :disabled if ENV['VIVLIO_PDF_PLUGIN'] == 'disable'

        load_enhanced_provider? ? :enhanced : :standard
      end

      private

      # 拡張プロバイダ（プラグイン）をロードできるか試みる。
      #
      # Bundler 実行下では Gemfile 未記載の gem が $LOAD_PATH から除外されるため、
      # 単純な require は失敗する。その場合はシステムにインストール済みの
      # プラグイン（と依存 gem）の require パスを動的に追加して一度だけ再試行する。
      # これにより「gem install vivlio-starter-pdf 済みなら、書籍プロジェクトの
      # Gemfile を編集しなくても自動的に enhanced モード」を実現する。
      #
      # @return [Boolean] ロードに成功したら true
      def load_enhanced_provider?
        injected = false
        begin
          require ENHANCED_PROVIDER_FEATURE
          true
        rescue LoadError
          if !injected && inject_installed_plugin_load_paths
            injected = true
            retry
          end
          false
        end
      end

      # システムにインストール済みのプラグインとその依存 gem の require パスを
      # $LOAD_PATH へ追加する。Bundler によるバンドル外 gem の除外を回避するため、
      # gemspec をディスクから直接読み取る（Gem::Specification.find_by_name は
      # Bundler 実行下ではバンドル内に限定されるため使用しない）。
      #
      # @return [Boolean] プラグインがインストールされていれば true
      def inject_installed_plugin_load_paths
        specs = installed_plugin_spec_closure
        return false if specs.empty?

        specs.each do |spec|
          # すでにロード済み（＝バンドルに含まれる）gem はバージョン競合回避のため触らない
          next if Gem.loaded_specs.key?(spec.name)

          spec.full_require_paths.each do |path|
            $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
          end
        end
        true
      rescue StandardError
        false
      end

      # プラグイン本体とその実行時依存 gem の Gem::Specification を
      # 再帰的に収集する（インストール済みのもののみ）。
      # @return [Array<Gem::Specification>]
      def installed_plugin_spec_closure
        collected = {}
        collect_installed_specs(PLUGIN_GEM_NAME, Gem::Requirement.default, collected)
        collected.values
      end

      # 指定 gem を満たすインストール済み spec を解決し、依存を辿って収集する。
      def collect_installed_specs(name, requirement, collected)
        spec = find_installed_spec(name, requirement)
        return if spec.nil? || collected.key?(spec.name)

        collected[spec.name] = spec
        spec.runtime_dependencies.each do |dependency|
          collect_installed_specs(dependency.name, dependency.requirement, collected)
        end
      end

      # gemspec をディスクから直接読み取り、要求を満たす最新の
      # インストール済み spec を返す（Bundler のバンドル制限を受けない）。
      # @return [Gem::Specification, nil]
      def find_installed_spec(name, requirement)
        Gem.path
           .flat_map { |home| Dir.glob(File.join(home, 'specifications', "#{name}-*.gemspec")) }
           .filter_map { |file| safe_load_gemspec(file) }
           .select { |spec| spec.name == name && requirement.satisfied_by?(spec.version) }
           .max_by(&:version)
      end

      # gemspec ファイルを安全に読み込む。失敗時は nil。
      def safe_load_gemspec(file)
        Gem::Specification.load(file)
      rescue StandardError
        nil
      end

      # 選択されたモードを通知する（プロバイダ初期化時に一度だけ）。
      def announce_mode(mode)
        return unless defined?(VivlioStarter::CLI::Common)

        case mode
        in :enhanced
          VivlioStarter::CLI::Common.log_info("[pdf] Enhanced モードを有効化しました（#{PLUGIN_GEM_NAME} を検出）")
        in :disabled
          VivlioStarter::CLI::Common.log_info('[pdf] VIVLIO_PDF_PLUGIN=disable のため Standard モードで実行します')
        in :standard
          VivlioStarter::CLI::Common.log_info("[pdf] Standard モードで実行します（#{PLUGIN_GEM_NAME} 未検出）")
        end
      end
    end
  end
end
