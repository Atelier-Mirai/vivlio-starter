# frozen_string_literal: true

require 'fileutils'
require 'open-uri'
require 'yaml'

module Vivlio
  module Starter
    module CLI
      module Lint
        # 辞書ファイルのロードとキャッシュを管理する
        class DictManager
          BUNDLED_DIR   = File.expand_path('../../../../../config/spellcheck_dictionaries', __dir__)
          CACHE_DIR     = File.expand_path('../../../../../.cache/spellcheck-dictionaries', __dir__)
          DICT_BASE_URL = 'https://raw.githubusercontent.com/streetsidesoftware/' \
                          'cspell-dicts/main/dictionaries'

          GLOSSARY_PATH = 'config/index_glossary_terms.yml'

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
            extra_words(config).each do |w|
              word = w.to_s
              words[word.downcase] = word
              next unless word.include?('-')

              words[word.gsub('-', '').downcase] ||= word
            end
            words
          end

          private

          # BUNDLED_DIR 内の .txt ファイルを動的に列挙して辞書名の配列を返す
          # @return [Array<String>] ファイル名（.txt 拡張子なし）のソート済み配列
          def bundled_dict_names
            Dir.glob(File.join(BUNDLED_DIR, '*.txt')).map { File.basename(_1, '.txt') }.sort
          end

          # book.yml の extra_dictionaries から辞書名の配列を取り出す
          # @param config [Object, nil] Common::CONFIG.spellcheck
          # @return [Array<String>]
          def extra_dicts(config)
            Array(config&.extra_dictionaries).map(&:to_s).reject(&:empty?)
          end

          # book.yml の extra_words から単語の配列を取り出す
          # @param config [Object, nil] Common::CONFIG.spellcheck
          # @return [Array<String>]
          def extra_words(config)
            Array(config&.extra_words).map(&:to_s).reject(&:empty?)
          end

          # 辞書ファイルの実パスを解決する（bundled → cached → download の順）
          # @param name [String] 辞書名
          # @return [String, nil] 解決されたパス、またはダウンロード失敗時に nil
          def resolve_path(name)
            bundled = File.join(BUNDLED_DIR, "#{name}.txt")
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
            line = line.gsub(/[^a-zA-Z0-9\-]/, '').strip
            line.empty? ? nil : line
          end

          # config/index_glossary_terms.yml から英字を含む term を word_map に登録する
          # @param words [Hash] 登録先の word_map（破壊的操作）
          def load_glossary_terms(words)
            return unless File.exist?(GLOSSARY_PATH)

            data  = YAML.safe_load(File.read(GLOSSARY_PATH, encoding: 'UTF-8'), symbolize_names: true) || {}
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
              Common.log_action("[spellcheck] 辞書をダウンロードしました: #{name} (#{subdir})")
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
end
