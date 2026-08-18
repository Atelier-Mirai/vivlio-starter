# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/scaffold_base.rb
# ================================================================
# 責務:
#   `vs upgrade` の 3-way マージに要る「共通祖先」（＝展開時／前回追従時の雛形）の
#   調達と、`git merge-file` によるマージ本体（upgrade-three-way-merge-spec.md）。
#
# なぜ別に持つのか（§1）:
#   `config/scaffold.lock` はハッシュしか持たないため「変わったか」は分かっても
#   「どこが変わったか」は復元できない。祖先の**中身**は別途調達する必要がある。
#
# 調達元は 2 つ（§2）:
#   A. インストール済みの旧版 gem の `lib/project_scaffold/`
#      （RubyGems は gem update で旧版を消さないので、たいてい残っている）
#   B. `.cache/vs/scaffold-base/`（`vs new` / `vs upgrade` の完了時に複製）
#   どちらか一方が欠けても動く。両方欠ければ従来どおり 2-way の競合として尋ねる。
#
# 採るのは「ハッシュが一致した中身」だけ:
#   候補の中身を lock の記録と突き合わせ、**一致したものだけ**を祖先とする。
#   版の取り違え・古い保存基準・gem cleanup 後に残った別版といった事故を、
#   経路ごとの場合分けではなく内容そのもので弾ける。祖先を間違えたマージは
#   「衝突なしに合流した」という顔で誤った中身を書くため、ここは緩めない。
#
# 保存する基準は lock と歩調を合わせる:
#   `sync!` が複製するのは「lock が現在の雛形と一致すると記録したファイル」だけ。
#   競合をスキップしたファイルの基準まで新版で上書きすると、次回のマージで
#   祖先＝新版となり、**雛形側の変更を黙って捨てる**合流が起きる。
# ================================================================

require 'fileutils'
require 'open3'

require_relative 'common'
require_relative 'scaffold_lock'

module VivlioStarter
  module CLI
    module ScaffoldBase
      extend self

      # 保存基準の置き場所（`.cache/vs/scaffold-base/`）。
      # キャッシュなので `vs clean --cache` で消えるが、経路 A と 2-way が控えている。
      BASE_RELATIVE = File.join(Common::CACHE_DIR, 'scaffold-base')

      # 3-way マージの材料になり得る拡張子。**著者が手で編集する設定・スタイルだけ**を
      # 対象にする。SVG は文字列としてはテキストだが、雛形の 3,714 個はすべて twemoji の
      # 生成物で、著者が編集して競合することはない（保存量が 1MB → 数十 MB に跳ねる）。
      MERGEABLE_EXTENSIONS = %w[.css .js .json .md .txt .yaml .yml].freeze

      # 拡張子を持たない設定ファイル
      MERGEABLE_BASENAMES = %w[Gemfile .gitignore].freeze

      # マージ対象の上限。設定ファイルとしては十分に大きく、事故的な巨大ファイルは弾く
      MAX_MERGEABLE_BYTES = 1_048_576

      # 3-way マージの材料になり得る雛形ファイルか。
      # 著者データ領域（contents/ 等）はそもそも競合に分類されないため対象外。
      def mergeable?(relative)
        return false if ScaffoldLock.author_data?(relative)

        basename = File.basename(relative)
        MERGEABLE_BASENAMES.include?(basename) ||
          MERGEABLE_EXTENSIONS.include?(File.extname(basename).downcase)
      end

      # 祖先の探索先を優先順に返す。プロジェクト内の保存基準を先に見るのは
      # 単に近いからで、正しさは中身のハッシュ照合が担保する（順序に依存しない）。
      # @return [Array<String>] 存在するディレクトリのみ
      def ancestor_roots(project_root = '.')
        [base_dir(project_root), *installed_scaffold_dirs].select { Dir.exist?(it) }
      end

      def base_dir(project_root = '.') = File.join(project_root, BASE_RELATIVE)

      # インストール済み gem の探索先。テストでは疑似 gem ディレクトリへ差し替える（DI）
      attr_writer :gem_paths

      def gem_paths = @gem_paths || Gem.path

      # インストール済み vivlio-starter の雛形ディレクトリ（新しい版から順に）。
      # Bundler 実行下でもバンドル外の版を見たいので Gem.path を直接 glob する
      # （`Gem::Specification.find_by_name` はバンドル内に限定されるため使えない）。
      def installed_scaffold_dirs
        gem_paths
           .flat_map { Dir.glob(File.join(it, 'gems', 'vivlio-starter-*', 'lib', 'project_scaffold')) }
           .select { Dir.exist?(it) }
           .sort
           .reverse
      rescue StandardError
        []
      end

      # lock が記録したハッシュと中身が一致する祖先ファイルのパスを返す。
      # @param expected_digest [String, nil] lock に記録された "sha256:…"
      # @return [String, nil] 見つからなければ nil（呼び出し側は 2-way へ落とす）
      def ancestor_path(relative, expected_digest, roots)
        return nil if expected_digest.nil? || !mergeable?(relative)

        roots.each do |root|
          path = File.join(root, relative)
          next unless File.file?(path)
          next unless ScaffoldLock.file_digest(path) == expected_digest

          return path
        end
        nil
      end

      # `git merge-file` による 3-way マージ。**衝突なく合流できたときだけ**中身を返す。
      # 衝突・git 不在・その他の異常はすべて nil で、呼び出し側は 2-way の競合へ落とす
      # （衝突マーカーが著者のファイルへ紛れ込むことは無い）。
      #
      # 自前の diff3 は書かない——マージは境界条件が多く、枯れた実装に任せるほうが安い。
      # git は Xcode Command Line Tools に同梱で、`vs doctor` が CLT の有無を既に見ている。
      # @return [String, nil] 合流後の中身（バイト列）
      def merge(base_path, mine_path, theirs_path)
        merged, _err, status = Open3.capture3(
          'git', 'merge-file', '-p', '-q', mine_path, base_path, theirs_path
        )
        status.success? ? merged : nil
      rescue StandardError
        nil
      end

      # 次回の祖先として雛形を保管する。複製するのは lock が「現在の雛形と一致」と
      # 記録したファイルだけ——記録が進まなかったファイル（競合をスキップした等）の
      # 基準を新版で上書きすると、次回のマージが雛形側の変更を黙って捨てる。
      # @param lock_files [Hash{String => String}] 書き込み後の lock の files 節
      def sync!(project_root, scaffold_source:, lock_files:)
        destination_root = base_dir(project_root)

        ScaffoldLock.scaffold_files(scaffold_source).each do |relative|
          next unless mergeable?(relative)

          source = File.join(scaffold_source, relative)
          next if File.size(source) > MAX_MERGEABLE_BYTES
          next unless lock_files[relative] == ScaffoldLock.file_digest(source)

          destination = File.join(destination_root, relative)
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(source, destination)
        end
      rescue StandardError => e
        # 基準の保管は「次回が楽になる」だけの処理。失敗しても upgrade 自体は成功させる
        Common.log_debug("[upgrade] 雛形の基準を保管できませんでした: #{e.message}")
      end
    end
  end
end
