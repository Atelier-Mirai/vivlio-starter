# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/scaffold_lock.rb
# ================================================================
# 責務:
#   雛形マニフェスト `config/scaffold.lock` の生成・読み書きと、
#   著者データ領域（upgrade が絶対に触れない範囲）の判定を提供する。
#
# 背景（project-upgrade-command-spec.md §2.1）:
#   lock は「展開時点の雛形原本ハッシュ」を記録する。これにより
#   雛形の旧版 / 新版 / プロジェクト現物 の三者比較が可能になり、
#   「雛形が変わった」と「著者が変えた」を区別できる。
#
# 利用者:
#   - NewCommands#expand_scaffold（vs new）: 展開末尾で生成
#   - UpgradeCommands（vs upgrade）: 分類・適用後の更新
#   - ScaffoldUpdates（vs build・vs preflight の知らせ）: 分類
# ================================================================

require 'date'
require 'digest'
require 'yaml'

module VivlioStarter
  module CLI
    module ScaffoldLock
      extend self

      LOCK_RELATIVE = File.join('config', 'scaffold.lock')

      # 雛形の中の book.yml
      BOOK_RELATIVE = File.join('config', 'book.yml')

      # 著者データ領域（§1.3）: ハッシュ判定以前に一律で upgrade 対象外。
      # ディレクトリは最上位名で判定する。
      AUTHOR_DATA_DIRS = %w[contents images covers codes data].freeze

      # 著者データ領域の中にある同梱素材。著者が編集する前提のファイルではないので雛形が管理し、
      # 新しく足した表紙のデザイン（covers/bundled/floral.svg など）も vs upgrade で既存の本へ届ける。
      # 著者が手を入れていれば、他の雛形ファイルと同じく三者比較で確認を求める。
      # 扉絵・装飾画像の stylesheets/images/bundled/ とテーマ色の stylesheets/theme.css は
      # 著者データ領域の外にあるので、ここに書かなくても届く。
      SCAFFOLD_MANAGED_DIRS = %w[covers/bundled/ covers/templates/].freeze

      # 著者データ領域のうち個別ファイル指定分。
      # 辞書系 4 点は index:apply / vs lint --register が書き込む「著者の辞書」
      # であり、雛形サンプルで上書きすると著者データを破壊するため一律保護する。
      AUTHOR_DATA_FILES = [
        File.join('config', 'book.yml'),
        File.join('config', 'catalog.yml'),
        File.join('config', 'talk.yml'),
        File.join('config', 'index_glossary_terms.yml'),
        File.join('config', 'index_glossary_rejected.yml'),
        File.join('config', 'spellcheck_allowlist.yml'),
        File.join('config', 'textlint_allowlist.yml')
      ].freeze

      # 展開・比較の対象にしない雛形内ファイル
      IGNORED_BASENAMES = %w[.DS_Store].freeze

      # 著者データ領域（一律 upgrade 対象外）かどうか
      # @param relative [String] プロジェクトルートからの相対パス
      def author_data?(relative)
        return false if relative.start_with?(*SCAFFOLD_MANAGED_DIRS)

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

      # 雛形が管理するファイル（著者データ以外）を三者比較で分類する。
      # vs upgrade の計画と vs build の知らせが同じ判定を見るよう、ここに置く
      # （project-upgrade-command-spec.md §1.2）。
      # @param relative [String] プロジェクトルートからの相対パス
      # @param scaffold_digest [String] 今の雛形のハッシュ
      # @param lock_files [Hash{String => String}] lock の files 節
      # @return [Symbol] :add / :update / :conflict / :latest
      def classify(relative, scaffold_digest, lock_files)
        return :add unless File.exist?(relative)

        current_digest = file_digest(relative)
        lock_digest = lock_files[relative]

        if lock_digest.nil?
          # lock なし（旧プロジェクト or 追跡外ファイル）: 一致なら最新、不一致は安全側で競合
          current_digest == scaffold_digest ? :latest : :conflict
        elsif scaffold_digest == lock_digest  then :latest
        elsif current_digest == lock_digest   then :update
        # 双方が別経路で同じ内容に到達した（著者が手で新版を当てた等）。lock だけが
        # 取り残されている状態で、diff は空になる。ここを競合にすると、y/n の
        # どちらを選んでも結果が変わらない問いを著者に投げることになる
        elsif current_digest == scaffold_digest then :latest
        else                                        :conflict
        end
      end

      # book.yml のキー（親も含む）をドットでつないで返す。
      # 日付を引用符なしで書いた book.yml も読めるよう、Date・Time を許す。
      # @param text [String] book.yml の中身
      # @return [Array<String>] 例: ["theme", "theme.lead_size"]
      def book_keys(text)
        key_paths(YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true))
      end

      # 雛形の book.yml のキー（並べ替え済み）。lock の book_keys 節に書く
      def scaffold_book_keys(scaffold_source)
        book_keys(File.read(File.join(scaffold_source, BOOK_RELATIVE), encoding: 'utf-8')).sort
      end

      # lock を読み込む。存在しない・壊れている場合は nil（呼び出し側で lock なしフォールバック）
      # @param project_root [String]
      # @return [Hash{Symbol => Object}, nil]
      #   { version: String|nil, files: Hash, book_keys: Array|nil, declined: Hash }
      #   book_keys が nil なら、キーの一覧を記録する前の版の lock
      def read(project_root = '.')
        path = File.join(project_root, LOCK_RELATIVE)
        return nil unless File.file?(path)

        data = YAML.safe_load(File.read(path, encoding: 'utf-8'))
        return nil unless data.is_a?(Hash) && data['files'].is_a?(Hash)

        { version: data['scaffold_version'], files: data['files'],
          book_keys: data['book_keys'], declined: data['declined'] || {} }
      rescue StandardError
        nil
      end

      # lock を書き出す（自動生成ファイルである旨のヘッダ付き）
      # @param files [Hash{String => String}] relative → "sha256:…"
      # @param book_keys [Array<String>, nil] 雛形の book.yml のキー
      # @param declined [Hash{String => String}] vs upgrade で断ったファイル → そのときの雛形のハッシュ
      def write(project_root, version:, files:, book_keys: nil, declined: {})
        data = { 'scaffold_version' => version }
        data['book_keys'] = book_keys if book_keys
        data['declined'] = declined.sort.to_h if declined.any?
        data['files'] = files.sort.to_h

        content = +"# vs new / vs upgrade が管理する自動生成ファイル。手動編集しない。\n"
        content << YAML.dump(data)
        File.write(File.join(project_root, LOCK_RELATIVE), content, encoding: 'utf-8')
      end

      # `vs new` の展開末尾から呼ぶ生成処理。
      # 既存の lock があれば既存エントリを優先して残す（重ね展開が起きても、
      # 著者の手元ファイルの「展開時点ハッシュ」という意味を壊さないため）。
      def generate!(project_root, scaffold_source:, version:)
        files = digest_scaffold(scaffold_source)
        existing = read(project_root)
        files = files.merge(existing[:files]) if existing
        write(project_root, version:, files:,
                            book_keys: existing&.dig(:book_keys) || scaffold_book_keys(scaffold_source),
                            declined: existing&.dig(:declined) || {})
      end

      private

      def key_paths(node, prefix = nil)
        return [] unless node.is_a?(Hash)

        node.flat_map do |key, value|
          path = [prefix, key].compact.join('.')
          [path, *key_paths(value, path)]
        end
      end
    end
  end
end
