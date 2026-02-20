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

          BUNDLED_DICTS = %w[
            aws               bash-words        basic
            cobol             coding-compound-terms computing-acronyms
            cpp               csharp            css
            django            docker            dotnet
            english-words-10  english-words-20  fonts
            fortran           git               go
            html              java-additional-terms java-terms
            javascript        kotlin            latex
            networkingTerms   node              npm
            objective-c       php               placeholder-words
            python-common     ruby              rust
            scala             smalltalk         software-tools
            softwareTerms     sql-common-terms  sql
            swift             tsql              webServices
          ].freeze

          GLOSSARY_PATH = 'config/index_glossary_terms.yml'

          # 辞書をマージして word_map を返す
          # @param config [Object, nil] Common::CONFIG.spellcheck の値
          # @return [Hash] { downcase_word => display_word }
          def build_word_map(config)
            words = {}
            (BUNDLED_DICTS + extra_dicts(config)).each do |name|
              path = resolve_path(name)
              load_into_word_map(path, words) if path
            end
            load_glossary_terms(words)
            extra_words(config).each { |w| words[w.to_s.downcase] = w.to_s }
            words
          end

          private

          def extra_dicts(config)
            Array(config&.extra_dictionaries).map(&:to_s).reject(&:empty?)
          end

          def extra_words(config)
            Array(config&.extra_words).map(&:to_s).reject(&:empty?)
          end

          def resolve_path(name)
            bundled = File.join(BUNDLED_DIR, "#{name}.txt")
            return bundled if File.exist?(bundled)

            cached = File.join(CACHE_DIR, "#{name}.txt")
            return cached if File.exist?(cached)

            fetch_and_cache(name)
          end

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

          def normalize(line)
            line = line.strip
            return nil if line.empty? || line.start_with?('#')

            line = line.split('#').first.strip
            line = line.split('/').first.strip
            line = line.gsub(/[^a-zA-Z0-9\-]/, '').strip
            line.empty? ? nil : line
          end

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
