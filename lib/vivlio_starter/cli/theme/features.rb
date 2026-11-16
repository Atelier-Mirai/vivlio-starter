# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/features.rb
# ================================================================
# 責務:
#   組み込みの機能（theme.yml の features:）の一覧（theme-contract-spec.md §3.4）。
#
# 組み込みの機能は、CSS だけでは作れず vs のコード（Ruby）が要るもの。テーマは使うものを
# features: に書く。機能は自分のオプションの宣言を持ち（OPTIONS）、テーマはそれを options: に
# 並べずに使える。機能を足すのは vs の本体の変更で、テーマの側からは足せない。
# ================================================================

require_relative 'option'
require_relative 'features/frontispiece'
require_relative 'features/ornament'

module VivlioStarter
  module CLI
    module Theme
      # 組み込みの機能
      module Features
        # 名前 → 機能のモジュール（2.0 で用意するのはこの二つ）
        REGISTRY = { 'frontispiece' => Frontispiece, 'ornament' => Ornament }.freeze

        module_function

        # @return [Array<String>]
        def names = REGISTRY.keys

        # @param name [String]
        # @return [Module, nil]
        def [](name) = REGISTRY[name.to_s]

        # 今の設定で、その機能が有効か。テーマが使い、かつ features: を持つ enum のオプションの
        # 今の値が絞っていない（theme-contract-spec.md §3.4 の決め 2）
        # @param name [Symbol, String] :frontispiece・:ornament
        # @param config [Data, nil] Common::CONFIG 相当
        def active?(name, config = Common::CONFIG)
          theme = Theme.declared(config)
          return false unless theme

          theme.active_features(config).include?(name.to_s)
        end
      end
    end
  end
end
