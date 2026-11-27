# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/scaffold_types.rb
# ================================================================
# 責務:
#   本の種類ごとの雛形（v2-architecture-spec.md §2.6）。共通の雛形 lib/project_scaffold/ に、
#   種類の差分 lib/project_scaffold_types/<種類>/ を重ねたものが、その種類の雛形である。
#
#   - 技術書（既定）の差分は、共通の雛形そのもの（直下の本書）。差分の置き場は持たない。
#   - ほかの種類の差分は、著者のデータの見本（contents/・images/）と config/book.yml・catalog.yml と、
#     その種類の判型の表紙の下敷き（covers/templates/）。正典はリポジトリの scaffolds/<種類>/ で、
#     scripts/copy_to_scaffold.rb が写す。
#   - 差分を持つ種類の本には、共通の雛形の著者のデータの見本（技術書の原稿・画像・コード・データ）を写さない。
#   - テーマは、その種類の既定のテーマだけを写す（ほかの同梱のテーマは vs theme:add で入れる）。
#
# book.type を読む:
#   雛形は種類ごとにあるので、どの雛形かは種類で決まる（book_type_usage_test.rb の許可）。
#   vs upgrade が book.yml に足す新しいキーは、その本の種類の雛形にあるキーだけにする（v2-migration-plan.md §5.1）。
# ================================================================

require 'date'
require 'yaml'

require_relative 'book_profile'
require_relative 'theme'

module VivlioStarter
  module CLI
    module ScaffoldTypes
      extend self

      # 種類の差分の置き場（共通の雛形と同じ階層。lib/project_scaffold_types/<種類>/）
      TYPES_DIR = 'project_scaffold_types'

      # 差分を持つ種類の本には写さない、共通の雛形の著者のデータの見本
      SAMPLE_DIRS = %w[contents images codes data].freeze

      BOOK_RELATIVE = File.join('config', 'book.yml')

      # 種類の差分の置き場。差分を持たない種類（技術書）は nil
      # @param type [Symbol, String]
      # @param scaffold_source [String] 共通の雛形
      # @return [String, nil]
      def overlay_root(type, scaffold_source:)
        root = File.join(File.dirname(scaffold_source), TYPES_DIR, type.to_s)
        File.directory?(root) ? root : nil
      end

      # vs new で作れる種類（既定の種類と、差分の置き場のある種類）
      # @return [Array<Symbol>]
      def available(scaffold_source:)
        BookProfile.types.select { it == BookProfile::DEFAULT_TYPE || overlay_root(it, scaffold_source:) }
      end

      # 種類の雛形のファイル。キーは本のルートからの相対パス、値は写す元の絶対パス。
      # 共通の雛形を先に並べ、種類の差分で上書きする
      # @param type [Symbol]
      # @return [Hash{String => String}]
      def files(type, scaffold_source:)
        overlay = overlay_root(type, scaffold_source:)
        theme = BookProfile.default_for({ book: { type: type.to_s } }, %i[theme name]) || Theme::DEFAULT_NAME
        base = tree(scaffold_source).reject do |relative, _|
          (overlay && SAMPLE_DIRS.include?(relative.split('/').first)) || other_theme?(relative, theme)
        end
        overlay ? base.merge(tree(overlay)) : base
      end

      # 本の種類の雛形の book.yml（vs upgrade が新しいキーを足すときの手本・lock の book_keys）
      # @param type [Symbol, nil] 省略時は作業ディレクトリの本の book.yml から読む
      # @return [String] 絶対パス
      def book_yml(scaffold_source:, type: nil)
        overlay = overlay_root(type || current_type, scaffold_source:)
        path = overlay && File.join(overlay, BOOK_RELATIVE)
        path && File.file?(path) ? path : File.join(scaffold_source, BOOK_RELATIVE)
      end

      private

      # 作業ディレクトリの本の種類。設定の読み込み（Common::CONFIG）に頼らず book.yml を直に読む
      # （vs upgrade は廃止キーの残った book.yml でも動く。UpgradeCommands#used_theme_names と同じ）
      def current_type
        raw = YAML.safe_load_file(BOOK_RELATIVE, permitted_classes: [Date, Time], aliases: true)
        book = raw.is_a?(Hash) && raw['book'].is_a?(Hash) ? raw['book'].transform_keys(&:to_sym) : {}
        BookProfile.type_of({ book: })
      rescue StandardError
        BookProfile::DEFAULT_TYPE
      end

      # ファイルと、空のディレクトリ（stylesheets/fonts/google など。vs new が作っておく）
      def tree(root)
        Dir.glob('**/*', File::FNM_DOTMATCH, base: root).filter_map do |relative|
          path = File.join(root, relative)
          next if File.basename(relative) == '.DS_Store'
          next if File.directory?(path) && !Dir.empty?(path)

          [relative, path]
        end.to_h
      end

      # 種類の既定のテーマでない同梱のテーマのファイルか
      def other_theme?(relative, theme)
        parts = relative.split('/')
        parts.first == Theme::DIR && parts.size > 2 && parts[1] != theme
      end
    end
  end
end
