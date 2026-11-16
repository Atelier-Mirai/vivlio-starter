# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/manifest.rb
# ================================================================
# 責務:
#   テーマの宣言（themes/<名前>/theme.yml）を読み、検査する（theme-contract-spec.md §3.1）。
#
# 誤りの扱い:
#   - 読めない・必須のキーが無い・値の形が違う・styles: のファイルが無い → Theme::Error（🔴）。
#     テーマが壊れたまま組むと、見た目の欠けた本ができるため。
#   - 知らないキー → warnings に積んで読み飛ばす（🟡）。後の版のテーマを前の版の vs で
#     開いた場合に止めないため。知らせるのは Guards::TraitCombinationCheck（build と preflight）。
#
# ここで中身を読まないキー:
#   features:・options:・kindle_tokens: は形（配列・表）だけを見て、そのまま持つ。
#   使い方を決めるのは S6-7（オプションと機能）と S6-10（kindle_tokens:）である。
# ================================================================

require 'yaml'

module VivlioStarter
  module CLI
    module Theme
      # theme.yml を読んだ結果。dir は本のルートからの相対（`themes/standard`）、path は絶対パス。
      # supports は書かれたキーだけを持つ（書いていない軸は、Theme::Resolved が土台か既定から補う）。
      # css_files はテーマのディレクトリの直下にある CSS の名前（出力先の CSS を探すのに使う）
      Manifest = Data.define(:name, :title, :version, :contract, :requires_vs, :license, :extends,
                             :supports, :features, :tokens, :kindle_tokens, :options, :styles,
                             :dir, :path, :css_files, :warnings) do
        # 出力先の CSS（theme-contract-spec.md §3.1 の表）。読む順は
        # css-layer-restructure-spec.md §5 の「target 層の中の順」の 4・5 の中の順
        # @param kind [String] 入口の名前（Css::EntryWriter::IMPORTS のキー）
        # @param target [Symbol, nil] :epub・:kindle（PDF は target 層を読まないので nil）
        # @return [Array<String>] 本のルートからの相対パス
        def target_files(kind, target)
          names = case target
                  when :epub then %W[epub.css epub-#{kind}.css]
                  when :kindle then %W[epub.css epub-#{kind}.css kindle.css kindle-#{kind}.css]
                  else []
                  end
          names.select { css_files.include?(it) }.map { File.join(dir, it) }
        end
      end

      # theme.yml の読み込みと検査
      class Manifest
        FILE = 'theme.yml'

        # theme.yml に書けるキー（theme-contract-spec.md §3.1 の例の順）
        KNOWN_KEYS = %w[name title version contract requires_vs license extends supports
                        features tokens kindle_tokens options styles].freeze

        # テーマの名前。ディレクトリの名前に使うので、パスの区切りや `..` を含めない
        NAME_PATTERN = /\A[a-z0-9][a-z0-9-]*\z/

        # supports: の軸と、書ける値（v2-architecture-spec.md §2.1・Build::Targets）
        SUPPORT_VALUES = {
          'writing_mode' => %w[horizontal vertical],
          'layout' => %w[reflowable fixed],
          'targets' => %w[pdf print_pdf epub kindle]
        }.freeze

        # tokens: の名前（`--book-` を除いた部分）
        TOKEN_NAME = /\A[a-z][a-z0-9-]*\z/

        # 値に書けない字。宣言の区切りと規則の括弧で、書き出した :root { … } が壊れる
        TOKEN_FORBIDDEN = /[;{}]/

        class << self
          # @param dir [String] 本のルートからの相対（`themes/standard`）
          # @param root [String] 本のルート
          # @return [Manifest]
          # @raise [Theme::Error]
          def load(dir, root:)
            path = File.expand_path(dir, root)
            label = File.join(dir, FILE)
            raw = read_yaml(File.join(path, FILE), label)

            # --- Phase: 名前と版（必須） ---
            name = raw['name']
            unless name.is_a?(String) && name == File.basename(dir)
              raise Error.new("#{label} の name: が、ディレクトリの名前と違います: #{name.inspect}",
                              detail: "name: #{File.basename(dir)} と書いてください")
            end
            contract = raw['contract']
            unless contract.is_a?(Integer)
              raise Error.new("#{label} に契約の版（contract:）が書かれていません",
                              detail: "この vs の契約の版は #{Contract::CURRENT} です（contract: #{Contract::CURRENT}）")
            end

            # --- Phase: 残りのキーの形 ---
            Manifest.new(
              name:, contract:,
              title: optional_string(raw, 'title', label),
              version: optional_string(raw, 'version', label),
              requires_vs: optional_string(raw, 'requires_vs', label),
              license: optional_string(raw, 'license', label),
              extends: extends_name(raw, label),
              supports: supports(raw, label),
              features: typed(raw, 'features', Array, [], label),
              tokens: tokens(raw, label),
              kindle_tokens: typed(raw, 'kindle_tokens', Hash, {}, label),
              options: typed(raw, 'options', Hash, {}, label),
              styles: styles(raw, path, label),
              dir:, path:,
              css_files: Dir.children(path).select { it.end_with?('.css') && File.file?(File.join(path, it)) }.sort,
              warnings: (raw.keys.map(&:to_s) - KNOWN_KEYS).map { "#{label} の知らないキー #{it}: を読み飛ばしました" }
            )
          end

          private

          def read_yaml(file, label)
            raise Error.new("#{label} がありません") unless File.file?(file)

            raw = YAML.safe_load_file(file)
            raise Error.new("#{label} の中身が、キーと値の表になっていません") unless raw.is_a?(Hash)

            raw
          rescue Psych::Exception => e
            raise Error.new("#{label} を読めません", detail: e.message)
          end

          def optional_string(raw, key, label)
            value = raw[key]
            return value.to_s if value.nil? || value.is_a?(String) || value.is_a?(Numeric)

            raise Error.new("#{label} の #{key}: は文字列で書いてください")
          end

          def typed(raw, key, klass, empty, label)
            value = raw[key]
            return empty if value.nil?
            return value if value.is_a?(klass)

            raise Error.new("#{label} の #{key}: は#{klass == Array ? '並び（- で始まる行）' : 'キーと値の表'}で書いてください")
          end

          def extends_name(raw, label)
            value = raw['extends']
            return nil if value.nil? || value == ''
            return value if value.is_a?(String) && value.match?(NAME_PATTERN)

            raise Error.new("#{label} の extends: に、テーマの名前でない値が書かれています: #{value.inspect}",
                            detail: '土台にするテーマの名前を 1 つ書いてください（例: extends: standard）')
          end

          # 書かれた軸だけを返す（キーは Symbol、値は Symbol の並び）
          def supports(raw, label)
            typed(raw, 'supports', Hash, {}, label).to_h do |axis, values|
              known = SUPPORT_VALUES[axis.to_s]
              raise Error.new("#{label} の supports: に、知らない軸 #{axis}: が書かれています",
                              detail: "書ける軸: #{SUPPORT_VALUES.keys.join('・')}") unless known

              list = Array(values).map(&:to_s)
              unknown = list - known
              unless unknown.empty? && !list.empty?
                raise Error.new("#{label} の supports.#{axis} に、知らない値か空の並びが書かれています: #{values.inspect}",
                                detail: "書ける値: #{known.join('・')}")
              end

              [axis.to_sym, list.map(&:to_sym)]
            end
          end

          def tokens(raw, label)
            typed(raw, 'tokens', Hash, {}, label).to_h do |key, value|
              name = key.to_s
              unless name.match?(TOKEN_NAME)
                raise Error.new("#{label} の tokens: の名前 #{name} は、--book- を除いた名前で書いてください",
                                detail: '例: color-accent: "#555"（--book-color-accent に入ります）')
              end
              unless (value.is_a?(String) || value.is_a?(Numeric)) && !value.to_s.match?(TOKEN_FORBIDDEN)
                raise Error.new("#{label} の tokens.#{name} の値を CSS に書き出せません: #{value.inspect}",
                                detail: '値は 1 つの文字列か数で書き、; { } を含めないでください')
              end

              [name, value.to_s]
            end
          end

          # styles: のファイルは、テーマのディレクトリの中の CSS に限る（外のファイルを theme 層へ入れない）
          def styles(raw, path, label)
            typed(raw, 'styles', Array, [], label).map do |file|
              name = file.to_s
              inside = name.end_with?('.css') && !name.start_with?('/') && !name.split('/').include?('..')
              raise Error.new("#{label} の styles: に、テーマの中の CSS でないものが書かれています: #{name}") unless inside
              raise Error.new("#{label} の styles: のファイルがありません: #{name}") unless File.file?(File.join(path, name))

              name
            end
          end
        end
      end
    end
  end
end
