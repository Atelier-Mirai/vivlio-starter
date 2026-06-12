# frozen_string_literal: true

require 'yaml'

module VivlioStarter
  module CLI
    module Guards
      # 必須 YAML が存在し、かつ妥当な YAML として解析できるかを検証する。
      # 存在のみを見る CatalogFileCheck より厳格（破損も検出する）。
      # doctor は diagnose の結果（欠落/破損/正常）を復元判断の根拠として共有する
      # （docs/specs/doctor-restore-and-plugin-tools-spec.md §4）。
      class ConfigValidityCheck < BaseCheck
        # @param paths [Array<String>] 検証対象（既定: Common::REQUIRED_YAML_FILES）
        def initialize(paths: Common::REQUIRED_YAML_FILES)
          @paths = paths
          super()
        end

        # @return [Array<Violation>]
        def validate = @paths.filter_map { violation_for(it) }

        # 1 ファイルの状態を判定する。Check（Guard 層）と doctor（復元層）が
        # 同じ判定を使うための共有入口（doctor 専用に YAML 検証を再実装しない）。
        # @return [Array(Symbol, String|nil)] [:ok | :missing | :corrupt, 詳細メッセージ]
        def self.diagnose(path)
          return [:missing, nil] unless File.file?(path)

          case YAML.safe_load(File.read(path, encoding: 'utf-8'), aliases: true)
          in Hash | Array then [:ok, nil]
          else [:corrupt, '内容が空、または YAML の構造になっていません']
          end
        rescue StandardError => e
          [:corrupt, e.message]
        end

        private

        def violation_for(path)
          case self.class.diagnose(path)
          in [:ok, _] then nil
          in [:missing, _] then error("設定ファイルが見つかりません: #{path}")
          in [:corrupt, detail] then error("設定ファイルが不正です: #{path}（YAML 解析に失敗）", detail:)
          end
        end
      end
    end
  end
end
