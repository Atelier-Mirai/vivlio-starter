# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/contract.rb
# ================================================================
# 責務:
#   テーマが前提にする契約の版（contract:）と vs の版（requires_vs:）を、この vs と突き合わせる
#   （theme-contract-spec.md §8）。
#
# 版を上げるのは、保証したもの（契約 HTML・公開する変数）を変える・消すときだけで、足すだけの
# 変更では上げない。版を上げた後の vs は一つ前の版のテーマも読む（SUPPORTED に残す）。
# ================================================================

require 'rubygems'
require_relative '../../version'

module VivlioStarter
  module CLI
    module Theme
      # 契約の版の検査
      module Contract
        CURRENT = 1
        SUPPORTED = [1].freeze

        module_function

        # 合わなければ Theme::Error を上げる
        # @param manifest [Manifest]
        # @param vs_version [String] この vs の版（テストでは差し替える）
        # @raise [Theme::Error]
        def check!(manifest, vs_version: VivlioStarter::VERSION)
          check_contract!(manifest)
          check_requires_vs!(manifest, vs_version)
        end

        def check_contract!(manifest)
          return if SUPPORTED.include?(manifest.contract)

          newer = manifest.contract > SUPPORTED.max
          raise Error.new(
            "テーマ #{manifest.name} の契約の版（contract: #{manifest.contract}）に、この vs は対応していません",
            detail: ["この vs が読める契約の版: #{SUPPORTED.join('・')}",
                     newer ? 'vs upgrade で vs を新しくしてください' : "契約の版 #{CURRENT} に対応した版のテーマに入れ替えてください"]
          )
        end

        def check_requires_vs!(manifest, vs_version)
          return if manifest.requires_vs.nil?

          requirement = Gem::Requirement.new(*manifest.requires_vs.split(','))
          return if requirement.satisfied_by?(Gem::Version.new(vs_version))

          raise Error.new("テーマ #{manifest.name} は vs #{manifest.requires_vs} を前提にしています（この vs は #{vs_version}）",
                          detail: 'vs upgrade で vs を新しくしてください')
        rescue Gem::Requirement::BadRequirementError
          raise Error.new("#{File.join(manifest.dir, Manifest::FILE)} の requires_vs: を読めません: #{manifest.requires_vs}",
                          detail: '書き方の例: requires_vs: ">= 2.1"')
        end
      end
    end
  end
end
