# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/scaffold_lock.rb
# ================================================================
# 責務:
#   雛形マニフェスト `config/scaffold.lock` の生成・読み書きと、
#   著者データ領域（upgrade が絶対に触れない範囲）の判定を提供する。
#
# 背景（docs/specs/project-upgrade-command-spec.md §2.1）:
#   lock は「展開時点の雛形原本ハッシュ」を記録する。これにより
#   雛形の旧版 / 新版 / プロジェクト現物 の三者比較が可能になり、
#   「雛形が変わった」と「著者が変えた」を区別できる。
#
# 利用者:
#   - NewCommands#expand_scaffold（vs new）: 展開末尾で生成
#   - UpgradeCommands（vs upgrade）: 分類・適用後の更新
# ================================================================

require 'digest'
require 'yaml'

module VivlioStarter
  module CLI
    module ScaffoldLock
      extend self

      LOCK_RELATIVE = File.join('config', 'scaffold.lock')

      # 著者データ領域（§1.3）: ハッシュ判定以前に一律で upgrade 対象外。
      # ディレクトリは最上位名で判定する。
      AUTHOR_DATA_DIRS = %w[contents images covers codes data].freeze

      # 著者データ領域のうち個別ファイル指定分。
      # 辞書系 4 点は index:apply / vs lint --register が書き込む「著者の辞書」
      # であり、雛形サンプルで上書きすると著者データを破壊するため一律保護する。
      AUTHOR_DATA_FILES = [
        File.join('config', 'book.yml'),
        File.join('config', 'catalog.yml'),
        File.join('config', 'characters.yml'),
        File.join('config', 'index_glossary_terms.yml'),
        File.join('config', 'index_glossary_rejected.yml'),
        File.join('config', 'user_words.txt'),
        File.join('config', 'textlint_allowlist.yml')
      ].freeze

      # 展開・比較の対象にしない雛形内ファイル
      IGNORED_BASENAMES = %w[.DS_Store].freeze

      # 著者データ領域（一律 upgrade 対象外）かどうか
      # @param relative [String] プロジェクトルートからの相対パス
      def author_data?(relative)
        top = relative.split('/').first
        AUTHOR_DATA_DIRS.include?(top) || AUTHOR_DATA_FILES.include?(relative)
      end

      # lock に記録するハッシュ表記（アルゴリズムを明示する prefix 付き）
      # @return [String] 例: "sha256:ab12…"
      def file_digest(path) = "sha256:#{Digest::SHA256.file(path).hexdigest}"

      # 雛形ディレクトリ内の全ファイルの相対パスを列挙する（lock 対象外の残骸は除外）
      # @param scaffold_source [String] 雛形ルートの絶対パス
      # @return [Array<String>]
      def scaffold_files(scaffold_source)
        Dir.glob('**/*', File::FNM_DOTMATCH, base: scaffold_source)
           .reject { IGNORED_BASENAMES.include?(File.basename(it)) }
           .select { File.file?(File.join(scaffold_source, it)) }
           .sort
      end

      # 雛形全ファイルのハッシュ表を作る（lock の files 節）。
      # book.yml もプレースホルダー書き換え「前」の雛形原本ハッシュで記録する
      # （比較対象は常に雛形原本。§2.1）。
      # @return [Hash{String => String}] relative → "sha256:…"
      def digest_scaffold(scaffold_source)
        scaffold_files(scaffold_source).to_h do |relative|
          [relative, file_digest(File.join(scaffold_source, relative))]
        end
      end

      # lock を読み込む。存在しない・壊れている場合は nil（呼び出し側で lock なしフォールバック）
      # @param project_root [String]
      # @return [Hash{Symbol => Object}, nil] { version: String|nil, files: Hash }
      def read(project_root = '.')
        path = File.join(project_root, LOCK_RELATIVE)
        return nil unless File.file?(path)

        data = YAML.safe_load(File.read(path, encoding: 'utf-8'))
        return nil unless data.is_a?(Hash) && data['files'].is_a?(Hash)

        { version: data['scaffold_version'], files: data['files'] }
      rescue StandardError
        nil
      end

      # lock を書き出す（自動生成ファイルである旨のヘッダ付き）
      # @param files [Hash{String => String}] relative → "sha256:…"
      def write(project_root, version:, files:)
        content = +"# vs new / vs upgrade が管理する自動生成ファイル。手動編集しない。\n"
        content << YAML.dump({ 'scaffold_version' => version, 'files' => files.sort.to_h })
        File.write(File.join(project_root, LOCK_RELATIVE), content, encoding: 'utf-8')
      end

      # `vs new` の展開末尾から呼ぶ生成処理。
      # 既存の lock があれば既存エントリを優先して残す（--add-missing で重ね展開した場合、
      # 著者の手元ファイルの「展開時点ハッシュ」という意味を壊さないため）。
      def generate!(project_root, scaffold_source:, version:)
        files = digest_scaffold(scaffold_source)
        if (existing = read(project_root))
          files = files.merge(existing[:files])
        end
        write(project_root, version:, files:)
      end
    end
  end
end
