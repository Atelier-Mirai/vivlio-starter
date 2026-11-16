# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/option.rb
# ================================================================
# 責務:
#   テーマのオプション（theme.yml の options:・組み込みの機能の宣言）1 件の宣言を読み、検査する
#   （theme-contract-spec.md §3.3）。
#
# 書き方:
#   options: の中で type: を持つ表が 1 件のオプション。type: を持たない表は入れ子の節で、
#   中のキーが book.yml の theme: の下の同じ入れ子になる（markers: { h3: {…}, h4: {…} } →
#   theme.markers.h3・theme.markers.h4）。
#
# 渡し方（vs のコードはオプションの名前を読まない。§3.3・§3.4 の決め）:
#   token:      公開する変数（--book-<token>）へ値を書き出す（PreProcessCommands::BookSettingsCss）
#   body_class: enum の値に応じて body にクラスを付ける（PostProcessCommands::BodyClassInjector）
#   features:   enum の値ごとに、使う組み込みの機能を絞る（Theme::Resolved#active_features）
# ================================================================

module VivlioStarter
  module CLI
    module Theme
      # オプション 1 件の宣言。path は theme: の下のキーの並び（%i[markers h3]）
      Option = Data.define(:path, :type, :default, :default_from, :token, :body_class, :values,
                           :min, :max, :unit, :features) do
        def initialize(path:, type:, default: nil, default_from: nil, token: nil, body_class: nil, values: nil,
                       min: nil, max: nil, unit: nil, features: nil)
          super
        end

        # 著者に見せる名前（theme.markers.h3）
        def label = "theme.#{path.join('.')}"

        # 葉のキーの名前（book.yml の行に書く名前）
        def key = path.last.to_s

        # ConfigKeys の形の宣言。default_from: のオプションは既定値を持たない（書かなければ、
        # 従う先の値を、値を使う側が補う。ConfigKeys の preface_color・appendix_color と同じ）
        def spec = ConfigKeys::Spec[default: default_from ? nil : default]

        # body に付けるクラスの表。種類の名前（文字列）→ クラス（文字列）か、値 → クラスの表。
        # 種類の名前でないキーだけの表は、全部の種類に当てる値 → クラスの表（§3.3）
        # @param kind [String] ページの種類（'chapter'・'appendix' など）
        # @param value [String] オプションの今の値
        # @return [String, nil]
        def body_class_for(kind, value)
          return nil unless body_class

          table = per_kind_body_class? ? body_class[kind.to_s] : body_class
          case table
          in String then table
          in Hash then table[value.to_s]
          else nil
          end
        end

        # body_class: に書かれたクラスの全部（契約 HTML の :theme_option の分類）
        def body_classes
          return [] unless body_class

          tables = per_kind_body_class? ? body_class.values : [body_class]
          tables.flat_map { it.is_a?(Hash) ? it.values : [it] }.uniq
        end

        # body_class: のキーが値でなくページの種類か
        def per_kind_body_class? = body_class.is_a?(Hash) && !body_class.keys.intersect?(values.to_a)
      end

      # オプションの宣言の読み込みと検査
      module OptionParser
        # 書ける type:（§3.3 の表）
        TYPES = %w[color length number ratio string enum image].freeze

        # オプションに書けるキー
        KEYS = %w[type default default_from token body_class values min max unit features].freeze

        # token: の名前（--book- を除いた部分。Manifest::TOKEN_NAME と同じ形）
        TOKEN_NAME = /\A[a-z][a-z0-9-]*\z/

        # キーの名前（book.yml に書く名前）
        KEY_NAME = /\A[a-z][a-z0-9_]*\z/

        module_function

        # options: の表を、オプションの並び（書いた順）にする
        # @param raw [Hash] options: の中身
        # @param label [String] 誤りに示す場所（themes/standard/theme.yml）
        # @param feature_names [Array<String>] features: に書ける機能の名前
        # @return [Array<Option>]
        # @raise [Theme::Error]
        def parse(raw, label:, feature_names: [], prefix: [])
          raw.flat_map do |name, body|
            key = name.to_s
            path = prefix + [key.to_sym]
            unless key.match?(KEY_NAME)
              raise Error.new("#{label} の options: のキー #{key} は、半角の英小文字・数字・下線で書いてください")
            end
            unless body.is_a?(Hash) && !body.empty?
              raise Error.new("#{label} の options.#{path.join('.')} は、type: を持つ表で書いてください")
            end

            if body.key?('type')
              [option(path, body, label:, feature_names:)]
            else
              parse(body, label:, feature_names:, prefix: path)
            end
          end
        end

        # 1 件のオプション
        def option(path, body, label:, feature_names:)
          where = "#{label} の options.#{path.join('.')}"
          unknown = body.keys.map(&:to_s) - KEYS
          raise Error.new("#{where} に知らないキーがあります: #{unknown.join('・')}", detail: "書けるキー: #{KEYS.join('・')}") unless unknown.empty?

          type = body['type'].to_s
          raise Error.new("#{where} の type: #{type} は書けません", detail: "書ける type: #{TYPES.join('・')}") unless TYPES.include?(type)

          values = enum_values(body, type, where)
          Option.new(
            path:, type:, values:,
            default: default_value(body, type, values, where),
            default_from: body['default_from']&.to_s,
            token: token_name(body, where),
            body_class: body_class(body, type, where),
            min: number_bound(body, 'min', type, where), max: number_bound(body, 'max', type, where),
            unit: unit(body, type, where),
            features: features(body, type, values, feature_names, where)
          )
        end

        def enum_values(body, type, where)
          return nil unless type == 'enum'

          values = Array(body['values']).map(&:to_s)
          raise Error.new("#{where} は enum なので、values: に選べる値を並べてください") if values.empty?

          values
        end

        def default_value(body, type, values, where)
          if body.key?('default') && body.key?('default_from')
            raise Error.new("#{where} に default: と default_from: の両方が書かれています",
                            detail: 'どちらか一方だけを書いてください')
          end
          value = body['default']
          if type == 'enum' && body.key?('default') && !values.include?(value.to_s)
            raise Error.new("#{where} の default: #{value} が values: にありません", detail: "values: #{values.join('・')}")
          end

          value
        end

        def token_name(body, where)
          token = body['token']
          return nil if token.nil?
          return token if token.is_a?(String) && token.match?(TOKEN_NAME)

          raise Error.new("#{where} の token: は、--book- を除いた変数の名前で書いてください",
                          detail: '例: token: color-accent（--book-color-accent に入ります）')
        end

        def body_class(body, type, where)
          table = body['body_class']
          return nil if table.nil?
          raise Error.new("#{where} の body_class: は enum のオプションにだけ書けます") unless type == 'enum'
          return table.transform_keys(&:to_s) if table.is_a?(Hash)

          raise Error.new("#{where} の body_class: は、値 → クラスの表か、ページの種類 → 表で書いてください")
        end

        def number_bound(body, key, type, where)
          value = body[key]
          return nil if value.nil?
          raise Error.new("#{where} の #{key}: は number・ratio のオプションにだけ書けます") unless %w[number ratio].include?(type)
          return value if value.is_a?(Numeric)

          raise Error.new("#{where} の #{key}: は数で書いてください")
        end

        def unit(body, type, where)
          value = body['unit']
          return nil if value.nil?
          raise Error.new("#{where} の unit: は number のオプションにだけ書けます") unless type == 'number'

          value.to_s
        end

        # enum の値 → 使う機能の名前の並び
        def features(body, type, values, feature_names, where)
          table = body['features']
          return nil if table.nil?
          raise Error.new("#{where} の features: は enum のオプションにだけ書けます") unless type == 'enum'
          raise Error.new("#{where} の features: は、値 → 機能の名前の並びの表で書いてください") unless table.is_a?(Hash)

          table.to_h do |value, names|
            raise Error.new("#{where} の features: の #{value} が values: にありません") unless values.include?(value.to_s)

            list = Array(names).map(&:to_s)
            unknown = list - feature_names
            raise Error.new("#{where} の features.#{value} に、知らない機能があります: #{unknown.join('・')}",
                            detail: "書ける機能: #{feature_names.join('・')}") unless unknown.empty?

            [value.to_s, list]
          end
        end
      end
    end
  end
end
