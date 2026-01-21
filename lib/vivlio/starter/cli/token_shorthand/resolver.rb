# frozen_string_literal: true

require_relative '../common'
require_relative 'catalog_loader'
require_relative 'data'
require_relative 'errors'

module Vivlio
  module Starter
    module CLI
      module TokenShorthand
        # TokenShorthand のトークン解決（catalog 照合 + ポリシー判定）
        class Resolver
          DEFAULT_OPTIONS = {
            allow_new: false,
            allow_slug_only: false,
            allow_missing_slug: false,
            allow_cache: false,
            allow_auxiliary: false,
            allow_metrics_cache: false
          }.freeze

          AUXILIARY_FILES = %w[
            _toc.md
            _titlepage.md
            _legalpage.md
            _colophon.md
            _titlepage_legalpage.pdf
            _colophon.pdf
            _indexpage.html
            entries.js
          ].freeze

          CONTENTS_AUXILIARY_BASENAMES = %w[
            _titlepage
            _legalpage
            _colophon
          ].freeze

          METRICS_CACHE_DIR = '.cache/metrics'

          # CLI ごとに Resolver.new を繰り返さないためのファクトリメソッド。
          def self.resolve(tokens:, catalog_entries: nil, **options)
            new(tokens:, catalog_entries:, **options).resolve
          end

          # CLI 側で「補助ファイルを含むか」の判定に使うヘルパ。
          def self.special_token_hint?(token, cache_dir: Common.cache_dir)
            normalized = token.to_s.strip.sub(%r{\A\./}, '')
            return false if normalized.empty?

            return true if AUXILIARY_FILES.include?(normalized)

            normalized.start_with?('_') || normalized.start_with?('.cache') ||
              (!!cache_dir && normalized.start_with?(cache_dir.to_s))
          end

          # Resolver 初期化時に catalog やポリシーを束ね、後続処理の参照コストを下げる。
          def initialize(tokens:, catalog_entries: nil, **options)
            @tokens = Array(tokens)
            @catalog_entries = catalog_entries || CatalogLoader.new.entries
            @options = DEFAULT_OPTIONS.merge(options)
            @contents_dir = options.fetch(:contents_dir, Common::CONTENTS_DIR)
            @cache_dir = options.fetch(:cache_dir, Common.cache_dir)
            @metrics_cache_dir = options.fetch(:metrics_cache_dir, METRICS_CACHE_DIR)
          end

          # @return [Array<TokenShorthand::Data::Entry>]
          # 入力トークンをポリシー別のエントリ列に変換し、CLI が直接扱える形に揃える。
          def resolve
            normalized = normalize_tokens(tokens)
            entries = normalized.flat_map { resolve_token(it) }
            entries.concat(resolve_auxiliary_entries) if allow_auxiliary?
            entries.concat(resolve_cache_entries) if allow_cache?
            entries.concat(resolve_metrics_cache_entries) if allow_metrics_cache?
            dedupe_entries(entries)
          end

          private

          attr_reader :tokens, :catalog_entries, :options, :contents_dir, :cache_dir, :metrics_cache_dir

          # 新規章作成を CLI から許可するかを判定する。
          def allow_new? = options[:allow_new]
          # slug のみ指定を許容するかを判定する。
          def allow_slug_only? = options[:allow_slug_only]
          # 番号のみ指定を許容し slug 不要とするかを判定する。
          def allow_missing_slug? = options[:allow_missing_slug]
          # cache ディレクトリをエントリとして許容するかを判定する。
          def allow_cache? = options[:allow_cache]
          # auxiliary ファイル群を解決対象に含めるかを判定する。
          def allow_auxiliary? = options[:allow_auxiliary]
          # metrics キャッシュを解決対象に含めるかを判定する。
          def allow_metrics_cache? = options[:allow_metrics_cache]

          # CLI入力を正規化し、特殊トークンと章トークンを同一ストリームに揃える。
          def normalize_tokens(raw_tokens)
            # --- Phase: トークン整形 ---
            tokens = Array(raw_tokens).compact.flat_map { it.to_s.split(',') }
            tokens.flat_map do |token|
              t = token.to_s.strip
              next [] if t.empty?

              if special_token?(t)
                [normalize_special_token(t)]
              else
                # --- Phase: 章トークンの正規化 ---
                normalized = normalize_chapter_token(t)
                expand_range_token(normalized)
              end
            end.reject { it.nil? || it.empty? }.uniq
          end

          # キャッシュ/補助ファイルなど章以外のパス指定かどうかを判定する。
          def special_token?(token)
            # 先頭の ./ を剥がし、ファイルシステムパスを正規化する。
            normalized = normalize_special_token(token)
            return true if AUXILIARY_FILES.include?(normalized)

            normalized.start_with?('_', '.cache') || normalized.start_with?(cache_dir.to_s)
          end

          # 先頭の ./ を剥がし、ファイルシステムパスを正規化する。
          def normalize_special_token(token)
            token.to_s.strip.sub(%r{\A\./}, '')
          end

          # contents/ プレフィクスや拡張子を除去し、章番号/slug を抽出しやすくする。
          def normalize_chapter_token(token)
            str = token.to_s.strip
            return str if str.empty?

            # --- Phase: パス要素の剥離 ---
            str = strip_contents_prefix(str)
            str = str.split('/', 2).first
            str = File.basename(str)
            # Markdown/HTML/PDF/YAML の既知拡張子を落として basename を揃える。
            str = strip_known_extension(str)

            # --- Phase: 形状ごとの判定 ---
            return format('%02d', str.to_i) if digits_only?(str)

            if (range = str.match(/\A(\d+)-(\d+)\z/))
              return "#{format('%02d', range[1].to_i)}-#{format('%02d', range[2].to_i)}"
            end

            if (leading = str.match(/\A(\d+)([-_].+)\z/))
              return "#{format('%02d', leading[1].to_i)}#{leading[2]}"
            end

            str
          end

          # contents ディレクトリを指している場合にパス前置きを削除する。
          def strip_contents_prefix(token)
            prefix = %r{\A#{Regexp.escape(contents_dir)}/}
            token.sub(prefix, '')
          end

          # Markdown/HTML/PDF/YAML の既知拡張子を落として basename を揃える。
          def strip_known_extension(token)
            token.sub(/\.(md|html|pdf|yml)\z/i, '')
          end

          # 01-05 のようなレンジ指定を個別番号の配列へ展開する。
          def expand_range_token(token)
            match = token&.match(/\A(\d{2})-(\d{2})\z/)
            return [token] unless match

            start_num = match[1].to_i
            end_num = match[2].to_i
            range = start_num <= end_num ? (start_num..end_num) : (end_num..start_num)
            range.map { |num| format('%02d', num) }
          end

          # 純粋に数字のみで構成されているかを判定し、ゼロ埋め可否を決める。
          def digits_only?(value)
            value.match?(/\A\d+\z/)
          end

          # 単一路線で特殊ファイル or 章トークンを解決して Entry を返す。
          def resolve_token(token)
            return [resolve_special_token(token)] if special_token?(token)

            number, slug = parse_chapter_token(token)
            if number
              resolve_by_number(token, number, slug)
            else
              resolve_slug_only(token)
            end
          end

          # 補助/キャッシュファイルを Entry に変換し、CLI で扱える形に揃える。
          def resolve_special_token(token)
            # --- Phase: パス整形と種別判定 ---
            normalized = normalize_special_token(token)
            path = resolve_special_path(normalized)
            kind = resolve_special_kind(path)

            unless special_allowed?(kind)
              raise Errors::UnsupportedSpecialFile, "特殊ファイルは対象外です: #{token}"
            end

            # --- Phase: Data::Entry 化 ---
            basename = File.basename(path, File.extname(path))
            number, slug = parse_chapter_token(basename)
            Data::Entry.new(
              number:,
              slug:,
              kind:,
              basename:,
              path:,
              ext: File.extname(path),
              exists: File.exist?(path),
              catalog_entry: nil,
              special?: true
            )
          end

          # 特殊ファイルが metrics/cache/auxiliary のどれかを判定する。
          def resolve_special_kind(path)
            return :metrics_cache if path.start_with?(metrics_cache_dir)
            return :cache if path.start_with?(cache_dir.to_s)

            :auxiliary
          end

          # 補助トークンが contents ディレクトリ配下のソースを指す場合に実パスへ変換する。
          def resolve_special_path(path)
            basename = File.basename(path, File.extname(path))
            ext = File.extname(path)

            if contents_auxiliary_basename?(basename) && (ext.empty? || ext.casecmp('.md').zero?)
              File.join(contents_dir, "#{basename}.md")
            else
              path
            end
          end

          def contents_auxiliary_basename?(basename)
            CONTENTS_AUXILIARY_BASENAMES.include?(basename)
          end

          # 常設の補助ファイルを列挙し、必要なら Entry に変換する。
          def resolve_auxiliary_entries
            AUXILIARY_FILES.filter_map { build_special_entry(it) }
          end

          # キャッシュディレクトリ配下のファイルを走査し、許可時のみ解決する。
          def resolve_cache_entries
            list_special_files(cache_dir)
              .map { build_special_entry(it, explicit_path: true) }
              .compact
          end

          # metrics キャッシュのファイルを走査し、許可時のみ解決する。
          def resolve_metrics_cache_entries
            list_special_files(metrics_cache_dir)
              .map { build_special_entry(it, explicit_path: true) }
              .compact
          end

          # 指定ディレクトリ配下の実ファイルのみを列挙し、Entry 化の素材にする。
          def list_special_files(dir)
            return [] if dir.nil? || dir.to_s.empty?

            Dir.glob(File.join(dir.to_s, '**', '*')).select { File.file?(it) }
          end

          # 特殊ファイルから Data::Entry を生成し、章と同じ API で扱えるようにする。
          def build_special_entry(token, explicit_path: false)
            # --- Phase: パス正規化 ---
            normalized = explicit_path ? token.to_s : normalize_special_token(token)
            path = explicit_path ? normalized : resolve_special_path(normalized)
            return nil if path.empty?

            kind = resolve_special_kind(path)
            return nil unless special_allowed?(kind)

            # --- Phase: Data::Entry 化 ---
            basename = File.basename(path, File.extname(path))
            number, slug = parse_chapter_token(basename)
            Data::Entry.new(
              number:,
              slug:,
              kind:,
              basename:,
              path:,
              ext: File.extname(path),
              exists: File.exist?(path),
              catalog_entry: nil,
              special?: true
            )
          end

          # ポリシーフラグを照らし合わせ、特殊ファイルの種類ごとに許否を決める。
          def special_allowed?(kind)
            case kind
            when :metrics_cache
              allow_metrics_cache?
            when :cache
              allow_cache?
            when :auxiliary
              allow_auxiliary?
            else
              false
            end
          end

          # `01-slug` 形式を number/slug ペアへ分解する。純 slug 時は nil を返す。
          def parse_chapter_token(token)
            match = token.to_s.match(/\A(?<number>\d+)(?:[-_](?<slug>.+))?\z/)
            return [nil, nil] unless match

            number = format('%02d', match[:number].to_i)
            slug = match[:slug]&.strip
            [number, slug]
          end

          # 章番号を起点に catalog と照合し、slug の有無で分岐させる。
          def resolve_by_number(token, number, slug)
            if slug
              entry = catalog_entry_by_number_and_slug(number, slug)
              return [build_entry(entry)] if entry
              return [build_new_entry(number, slug)] if allow_new?

              raise Errors::UnknownChapterToken, "catalog.yml に存在しません: #{token}"
            end

            entry = catalog_entry_by_number(number)
            return [build_entry(entry)] if entry

            return [build_new_entry(number, nil)] if allow_new? && allow_missing_slug?

            if allow_new?
              raise Errors::MissingChapterSlug, "スラッグが必要です: #{token}"
            end

            raise Errors::UnknownChapterToken, "catalog.yml に存在しません: #{token}"
          end

          # slug のみで指定された章を逆引きし、曖昧性があれば番号指定を促す。
          def resolve_slug_only(token)
            unless allow_slug_only?
              raise Errors::MissingChapterNumber, "章番号が必要です: #{token}"
            end

            matches = catalog_entries.select { it.slug == token }
            if matches.empty?
              raise Errors::UnknownChapterToken, "catalog.yml に存在しません: #{token}"
            end

            if matches.size > 1
              raise Errors::MissingChapterNumber, "slug が重複しています: #{token}"
            end

            [build_entry(matches.first)]
          end

          # 既存 catalog entry を CLI 用の Data::Entry に写像する。
          def build_entry(catalog_entry)
            Data::Entry.new(
              number: catalog_entry.number,
              slug: catalog_entry.slug,
              kind: catalog_entry.kind,
              basename: catalog_entry.basename,
              path: catalog_entry.path,
              ext: catalog_entry.ext,
              exists: catalog_entry.exists,
              catalog_entry:,
              special?: false
            )
          end

          # catalog に無い章を新規作成する際の仮想 Entry を組み立てる。
          def build_new_entry(number, slug)
            basename = [number, slug].compact.join('-')
            path = File.join(contents_dir, "#{basename}.md")
            kind = derive_kind(number)
            warn_slug_conflict(slug, number) if slug

            Data::Entry.new(
              number:,
              slug:,
              kind:,
              basename:,
              path:,
              ext: '.md',
              exists: File.exist?(path),
              catalog_entry: nil,
              special?: false
            )
          end

          # 章番号の範囲に応じて preface/chapter/appendix/postface を推定する。
          def derive_kind(number)
            return :chapter unless number

            num = number.to_i
            case num
            when CatalogLoader::PREFACE_RANGE
              :preface
            when CatalogLoader::MAIN_RANGE
              :chapter
            when CatalogLoader::APPX_RANGE
              :appendix
            when CatalogLoader::POSTFACE_RANGE
              :postface
            else
              :chapter
            end
          end

          # 同一 slug がすでに catalog に存在する場合に警告を出し、上書きを防ぐ。
          def warn_slug_conflict(slug, number)
            return if slug.nil? || slug.empty?

            conflict = catalog_entries.find { it.slug == slug && it.number != number }
            return unless conflict

            Common.log_warn("既存章と slug が重複しています: #{slug} (#{conflict.basename})")
          end

          # 章番号のみで catalog からエントリを取得する。
          def catalog_entry_by_number(number)
            catalog_entries.find { it.number == number }
          end

          # 章番号+slug の完全一致で catalog からエントリを取得する。
          def catalog_entry_by_number_and_slug(number, slug)
            catalog_entries.find { it.number == number && it.slug == slug }
          end

          # 同一パス/ベース名を1度だけ返し、CLI が重複実行しないようにする。
          def dedupe_entries(entries)
            seen = {}
            entries.each_with_object([]) do |entry, result|
              key = entry.path || entry.basename
              next if key.nil? || seen[key]

              seen[key] = true
              result << entry
            end
          end
        end
      end
    end
  end
end
