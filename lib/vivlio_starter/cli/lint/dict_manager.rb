# frozen_string_literal: true

require 'fileutils'
require 'open-uri'
require 'yaml'

module VivlioStarter
  module CLI
    module Lint
      # 辞書ファイルのロードとキャッシュを管理する
      class DictManager
        # 辞書の探索先。プロジェクト直下の config/（vs new が配置し、ユーザーが追加・編集できる）を
        # 優先し、無ければ gem 同梱の scaffold コピーへフォールバックする。
        # ※ gem は lib/ 配下しかパッケージしない（gemspec の files が {bin,lib}/**/*）ため、
        #   リポジトリ直下の config/ を指していた旧実装ではインストール済み gem で辞書が 0 件になり、
        #   技術用語が軒並み誤検知されていた（CWD 相対の config/ なら開発リポジトリでもユーザー
        #   プロジェクトでも実在し、.textlintrc.yml の参照方法とも一貫する）。
        PROJECT_DICT_DIR  = 'config/spellcheck_dictionaries'
        PACKAGED_DICT_DIR = File.expand_path('../../../project_scaffold/config/spellcheck_dictionaries', __dir__)

        CACHE_DIR     = '.cache/spellcheck-dictionaries'
        DICT_BASE_URL = 'https://raw.githubusercontent.com/streetsidesoftware/' \
                        'cspell-dicts/main/dictionaries'

        GLOSSARY_PATH = 'config/index_glossary_terms.yml'

        # スペルチェックの除外リスト（このプロジェクト固有の許可語）のパス。
        # プロジェクト直下の config/ に置く（隠しフォルダでなく見つけやすい。別の本でも
        # 使いたければこのファイルをコピーすればよい）。`vs lint --register` の追記先。
        #
        # 名前は textlint 側の `textlint_allowlist.yml` と対にしてある——接頭辞が
        # どのツールか、後半が何をするファイルかを表す（`textlint_rewrite.yml` が
        # 「直す」、`*_allowlist.yml` が「指摘しない」）。
        #
        # 定数でなくメソッドにして呼び出し時の CWD を読む（テストで chdir しても追従する）。
        def user_dict_path
          File.join('config', 'spellcheck_allowlist.yml')
        end

        # 実際に使う辞書ディレクトリ（プロジェクト優先・gem 同梱フォールバック）
        def bundled_dir
          Dir.exist?(PROJECT_DICT_DIR) ? PROJECT_DICT_DIR : PACKAGED_DICT_DIR
        end

        # 辞書をマージして word_map を返す
        # @param config [Object, nil] Common::CONFIG.spellcheck の値
        # @return [Hash] { downcase_word => display_word }
        def build_word_map(config)
          words = {}
          (bundled_dict_names + extra_dicts(config)).uniq.each do |name|
            path = resolve_path(name)
            load_into_word_map(path, words) if path
          end
          load_glossary_terms(words)
          load_into_word_map(user_dict_path, words) if File.exist?(user_dict_path)
          words
        end

        # 未知語をユーザー辞書（user_dict_path）へ登録する。
        # 既存語＋新規語を大文字小文字無視で一意化し、辞書順に並べ替えてファイルを書き直す
        # （編集過程の重複や未整列も毎回整える）。実際に追加した語の配列を返す。
        def register_user_words(new_words)
          candidates = Array(new_words).map { it.to_s.strip }.reject(&:empty?).uniq
          return [] if candidates.empty?

          existing = read_user_words
          existing_down = existing.map(&:downcase)
          added = candidates.reject { |w| existing_down.include?(w.downcase) }
          return [] if added.empty?

          merged = (existing + added).uniq { it.downcase }.sort_by(&:downcase)
          write_user_words(merged)
          added
        end

        private

        # 除外リストに登録済みの語。`textlint_allowlist.yml` と同じ YAML の並び。
        # 壊れた YAML でスペルチェック全体を止めない——空として扱い、次の
        # --register で書き直せば直る。
        def read_user_words
          return [] unless File.exist?(user_dict_path)

          Array(YAML.safe_load_file(user_dict_path)).filter_map { normalize(it.to_s) }
        rescue StandardError => e
          Common.log_warn("#{user_dict_path} の読み込みに失敗しました: #{e.message}")
          []
        end

        # ヘッダ＋辞書順の語で除外リストを書き直す
        def write_user_words(words)
          FileUtils.mkdir_p(File.dirname(user_dict_path))
          File.write(user_dict_path, user_dict_header + words.map { %(- "#{it}"\n) }.join)
        end

        def user_dict_header
          <<~HEADER
            # =============================================================
            #  📝 スペルチェック除外リスト - Vivlio Starter
            # -------------------------------------------------------------
            #  • スペルチェックで「綴り誤り」と指摘したくない語を並べます
            #  • 1 行 1 語。辞書順・重複なしで自動的に整えられます
            #  • `vs lint --register` を実行すると、未知だった語がここへ追加されます
            #  • 別の本でも使いたい場合は、このファイルをコピーしてください
            # =============================================================

          HEADER
        end

        # BUNDLED_DIR 内の .txt ファイルを動的に列挙して辞書名の配列を返す
        # @return [Array<String>] ファイル名（.txt 拡張子なし）のソート済み配列
        def bundled_dict_names
          Dir.glob(File.join(bundled_dir, '*.txt')).map { File.basename(it, '.txt') }.sort
        end

        # book.yml の extra_dictionaries から辞書名の配列を取り出す
        # @param config [Object, nil] Common::CONFIG.spellcheck
        # @return [Array<String>]
        def extra_dicts(config)
          Array(config&.extra_dictionaries).map(&:to_s).reject(&:empty?)
        end

        # 辞書ファイルの実パスを解決する（bundled → cached → download の順）
        # @param name [String] 辞書名
        # @return [String, nil] 解決されたパス、またはダウンロード失敗時に nil
        def resolve_path(name)
          bundled = File.join(bundled_dir, "#{name}.txt")
          return bundled if File.exist?(bundled)

          cached = File.join(CACHE_DIR, "#{name}.txt")
          return cached if File.exist?(cached)

          fetch_and_cache(name)
        end

        # 辞書ファイルを1行ずつ読み込み、正規化した上で words に登録する
        # ハイフン複合語はハイフンあり・なしの両形式で登録する
        # @param path [String] 辞書ファイルのパス
        # @param words [Hash] 登録先の word_map（破壊的操作）
        def load_into_word_map(path, words)
          File.foreach(path) do |line|
            word = normalize(line)
            next unless word

            words[word.downcase] = word
            next unless word.include?('-')

            no_hyphen = word.gsub('-', '').downcase
            words[no_hyphen] ||= word
          end
        rescue Errno::ENOENT, Errno::EACCES => e
          Common.log_warn("[spellcheck] 辞書ファイルを読み込めませんでした: #{path} (#{e.message})")
        end

        # 辞書ファイルの1行を正規化して単語文字列を返す
        # コメント行・空行・Hunspellフラグ・記号をすべて除去する
        # @param line [String] 辞書ファイルの1行
        # @return [String, nil] 正規化後の単語。除外対象なら nil
        def normalize(line)
          line = line.strip
          return nil if line.empty? || line.start_with?('#')

          line = line.split('#').first.strip
          line = line.split('/').first.strip
          line = line.gsub(/[^a-zA-Z0-9-]/, '').strip
          line.empty? ? nil : line
        end

        # config/index_glossary_terms.yml から英字を含む term を word_map に登録する
        # @param words [Hash] 登録先の word_map（破壊的操作）
        def load_glossary_terms(words)
          return unless File.exist?(GLOSSARY_PATH)

          data = YAML.safe_load(File.read(GLOSSARY_PATH, encoding: 'UTF-8'), symbolize_names: true) || {}
          Array(data[:terms]).each do |entry|
            term = entry[:term].to_s.strip
            next if term.empty? || !term.match?(/[a-zA-Z]/)

            words[term.downcase] = term
            next unless term.include?('-')

            words[term.gsub('-', '').downcase] ||= term
          end
        rescue StandardError => e
          Common.log_warn("[spellcheck] 索引用語の読み込みに失敗しました: #{e.message}")
        end

        # cspell-dicts から辞書をダウンロードして CACHE_DIR に保存する
        # dict/ サブディレクトリを先に試み、なければ src/ を試みる
        # @param name [String] 辞書名
        # @return [String, nil] キャッシュファイルのパス、またはダウンロード失敗時に nil
        def fetch_and_cache(name)
          FileUtils.mkdir_p(CACHE_DIR)
          path = File.join(CACHE_DIR, "#{name}.txt")
          %w[dict src].each do |subdir|
            url = "#{DICT_BASE_URL}/#{name}/#{subdir}/#{name}.txt"
            URI.open(url) { |f| File.write(path, f.read) } # rubocop:disable Security/Open
            return path
          rescue OpenURI::HTTPError
            next
          end
          Common.log_warn("[spellcheck] 辞書のダウンロードに失敗しました: #{name}")
          nil
        rescue StandardError => e
          Common.log_warn("[spellcheck] 辞書取得中にエラーが発生しました: #{name} (#{e.message})")
          nil
        end
      end
    end
  end
end
