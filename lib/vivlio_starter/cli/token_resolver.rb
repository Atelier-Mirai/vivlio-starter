# frozen_string_literal: true

require 'yaml'

require_relative 'common'
require_relative 'build/catalog_loader'

module VivlioStarter
  module CLI
    # CLI の章指定トークンを一元的に解釈するモジュール。
    # ユーザーの曖昧な入力を厳格な Entry オブジェクトに変換し、
    # 各コマンドが同じ正規化・照合ルールを共有できるようにする。
    module TokenResolver
      # 章情報を保持する不変データ構造。
      # Resolver が返す全ての章情報はこの型で統一される。
      Entry = Data.define(:number, :slug, :kind, :label, :path, :exists, :in_catalog, :valid) do
        # ファイル名のベース部分を動的に生成する。
        # number と slug から導出されるため、属性間の不整合が発生しない。
        # システムファイル（number=nil）の場合は slug のみを返す。
        def basename
          if number
            slug ? "#{number}-#{slug}" : number
          else
            slug
          end
        end

        # valid フラグの述語メソッド。
        def valid? = valid

        # in_catalog フラグの述語メソッド。
        def in_catalog? = in_catalog

        # exists フラグの述語メソッド。
        def exists? = exists
      end

      # 入力の正規化、カタログの読み込み、両者の照合を一括管理する。
      # CLIコマンド側は Resolver を呼ぶだけで、複雑なトークン解析から解放される。
      class Resolver
        AUTO_NUMBER_MAX = 98

        # 章番号の範囲から kind を決定するためのマッピング。
        # 00: preface, 01-89: chapter, 90-98: appendix, 99: postface
        KIND_RANGES = { preface: 0..0, chapter: 1..89, appendix: 90..98, postface: 99..99 }.freeze

        # システム予約ファイルの kind マッピング。
        # カタログに載らない特殊ファイルを仮想 Entry として解決するために使用。
        SYSTEM_FILE_KINDS = {
          '_titlepage' => :titlepage,
          '_legalpage' => :legalpage,
          '_colophon' => :colophon,
          '_indexpage' => :indexpage,
          '_glossarypage' => :glossarypage,
          '_toc' => :toc
        }.freeze

        # .cache/vs/ に生成されるシステムページ（contents/ ではなくキャッシュに配置）
        CACHED_SYSTEM_FILES = %w[_titlepage _legalpage _colophon].freeze

        # @param catalog_path [String] catalog.yml のパス
        # @param contents_dir [String] 章ファイルが格納されるディレクトリ
        def initialize(catalog_path: 'config/catalog.yml', contents_dir: 'contents')
          @catalog_path = catalog_path
          @contents_dir = contents_dir
        end

        # メイン入口：引数があればそれを解決し、無ければカタログ全件を返す。
        # @param tokens [Array<String>] CLI から受け取ったトークン配列
        # @return [Array<Entry>] 解決された Entry オブジェクトの配列
        def resolve(tokens = [])
          catalog = load_catalog_entries
          reset_number_tracking(catalog)

          # 非 UTF-8 端末からの引数は不正バイト列を含み得る（ファズテスト FZ-03 で検出）。
          # 後段の正規表現が ArgumentError で落ちないよう不正バイトを除去する。
          # NUL は妥当な UTF-8 だが File 系 API が ArgumentError を出すため併せて除去する
          # （該当トークンは単に invalid Entry / 不一致として扱われる）
          tokens = tokens.map { it.to_s.dup.force_encoding(Encoding::UTF_8).scrub('').delete("\0") }

          if tokens.empty?
            # 引数なし：catalog.yml にある全章を対象とする (build 等)
            catalog
          else
            # 引数あり：入力を正規化してカタログと突き合わせる
            normalize(tokens).map { match_entry(it, catalog) }
          end
        end

        # ファイルパスから Entry を取得する便利メソッド。
        # @param file_path [String] Markdown/HTML ファイルのパス
        # @return [Entry] 解決された Entry オブジェクト
        def resolve_file(file_path)
          basename = File.basename(file_path).sub(/\.(md|html)\z/i, '')
          resolve([basename]).first
        end

        private

        attr_reader :catalog_path, :contents_dir

        # --- Phase 1: Normalization (入力の正規化) ---
        # カンマ区切りの分割、パス/拡張子の除去、範囲指定の展開を行う。
        # 入力の多様なバリエーションを統一フォーマットに変換する。
        def normalize(tokens)
          prefix = %r{\A#{Regexp.escape(contents_dir)}/}
          Array(tokens).compact.flat_map { it.to_s.split(',') }.map(&:strip).flat_map do |raw|
            # contents/ プレフィクスと拡張子を除去
            n = raw.sub(prefix, '').then { File.basename(it, '.*') }
            case n
            in /\A(\d+)\z/
              # 数字のみ: ゼロ埋め
              format('%02d', ::Regexp.last_match(1).to_i)
            in /\A(\d+)-(\d+)\z/
              # 範囲指定: 展開（降順にも対応）
              s = ::Regexp.last_match(1).to_i
              e = ::Regexp.last_match(2).to_i
              (s <= e ? s..e : e..s).map { format('%02d', it) }
            in /\A(\d+)([-_].+)\z/
              # 番号+スラグ: 番号部分をゼロ埋め
              "#{format('%02d', ::Regexp.last_match(1).to_i)}#{::Regexp.last_match(2)}"
            else
              # その他: そのまま（invalid として後で処理される可能性あり）
              n
            end
          end.reject(&:empty?).uniq
        end

        # --- Phase 2: Catalog Loading (カタログ読み込み) ---
        # YAML パース・セクション/ショートハンド展開は Build::CatalogLoader に一本化した
        # （仕様: docs/specs/catalog-parser-unification-spec.md）。ここでは
        # CatalogEntry（basename/label/section）→ Entry への変換のみを行う。
        # instantiate_entry は常に Entry を返すため compact は不要。
        def load_catalog_entries
          Build::CatalogLoader
            .load_labeled_entries(catalog_path:, contents_dir:)
            .map { instantiate_entry(it.basename, it.label, section_to_kind(it.section), in_catalog: true) }
            .uniq(&:number)
        end

        # セクション名を kind シンボルに変換する。
        def section_to_kind(section) = section.to_s.downcase.to_sym

        # --- Phase 3: Matching (照合) ---
        # 正規化されたトークンをカタログと突き合わせ、Entry を生成する。
        def match_entry(token, catalog)
          # 1. システムファイルのチェック
          if (system_kind = SYSTEM_FILE_KINDS[token])
            return instantiate_system_entry(token, system_kind)
          end

          # 1b. 中扉（_part{N}）の動的パターンマッチ
          # catalog.yml の部タイトルから自動生成されるシステムページ
          return instantiate_system_entry(token, :part_title) if token.match?(/\A_part\d+\z/)

          # 2. slug のみ指定された場合は catalog / contents から探索
          return match_slug_entry(token, catalog) unless token.match?(/\A\d+/)

          # 2. トークンの形式を解析（番号のみ or 番号+スラッグ）
          if token =~ /\A(\d+)[-_](.+)\z/
            # 番号+スラッグ形式: 完全一致を要求
            token_num = format('%02d', ::Regexp.last_match(1).to_i)
            token_slug = ::Regexp.last_match(2)
            found = catalog.find { it.number == token_num && it.slug == token_slug }
            return found if found

            # カタログにない場合、新規エントリとして生成
          else
            # 番号のみ形式: 番号でマッチ
            token_num = format('%02d', token.to_i)
            found = catalog.find { it.number == token_num }
            return found if found

            # カタログにない場合、ファイルシステムからスラッグを補完する。
            # 優先順位: スラッグ付き (NN-slug.md) > 数字のみ (NN.md)
            # 例: "2" → contents/02-history.md が存在すれば "02-history" として解決。
            fs_matches = Dir.glob(File.join(contents_dir, "#{token_num}-*.md"))
            if fs_matches.any?
              fs_basename = File.basename(fs_matches.first, '.md')
              return instantiate_entry(fs_basename, 'UNCATALOGED', :chapter, in_catalog: false)
            end

            # スラッグ付きファイルが無い場合、数字のみファイル (NN.md) を探索
            # 例: "2" → contents/02.md が存在すれば slug=nil の Entry として解決。
            numeric_file = File.join(contents_dir, "#{token_num}.md")
            if File.exist?(numeric_file)
              return instantiate_entry(token_num, 'UNCATALOGED', :chapter, in_catalog: false)
            end

            # どちらも見つからない場合、番号のみの新規エントリとして生成
          end
          instantiate_entry(token, 'NEW', :chapter, in_catalog: false)
        end

        def match_slug_entry(token, catalog)
          slug = normalize_slug_token(token)
          return instantiate_invalid_entry(token) unless slug

          if (found = catalog.find { |entry| entry.slug&.downcase == slug })
            return found
          end

          matches = Dir.glob(File.join(contents_dir, '*.md')).filter_map do |path|
            base = File.basename(path, '.md')
            number, entry_slug = base.split('-', 2)
            next unless number && entry_slug
            next unless entry_slug.downcase == slug

            base
          end

          case matches.uniq.size
          when 0
            instantiate_new_entry_from_slug(slug)
          when 1
            instantiate_entry(matches.first, 'UNCATALOGED', :chapter, in_catalog: false)
          else
            instantiate_invalid_entry(token)
          end
        end

        # --- Phase 4: Entry オブジェクトの実体化（正常系）---
        # basename から Entry を生成する。形式が不正なら invalid_entry を返す。
        # 数字のみファイル（NN）にも対応し、slug=nil の Entry を生成する。
        # @param basename [String] 章ファイルのベース名（例: "01-life" または "02"）
        # @param label [String] カタログのセクション名（例: "CHAPTERS"）
        # @param fallback_kind [Symbol] kind 判定に失敗した際のフォールバック値
        # @param in_catalog [Boolean] カタログに登録済みかどうか
        # @return [Entry] 生成された Entry オブジェクト
        def instantiate_entry(basename, label, fallback_kind, in_catalog:)
          # 形式チェック: 数字で始まり、オプションで -slug または _slug が続く
          return instantiate_invalid_entry(basename) unless basename =~ /\A(\d+)(?:[-_](.+))?\z/

          num = ::Regexp.last_match(1)
          slug = ::Regexp.last_match(2)
          number = format('%02d', num.to_i)
          # slug がある場合は number-slug、ない場合は number のみ
          actual_basename = slug ? "#{number}-#{slug}" : number
          path = File.join(contents_dir, "#{actual_basename}.md")
          kind = KIND_RANGES.find { |_, r| r.cover?(number.to_i) }&.first || fallback_kind

          Entry.new(
            number:,
            slug: slug&.strip,
            kind:,
            label:,
            path:,
            exists: File.exist?(path),
            in_catalog:,
            valid: true
          )
        end

        # --- Phase 5: Invalid Entry (不正形式エントリ生成) ---
        # 数字で始まらないなど、形式が不正な入力に対する Entry を生成する。
        # valid: false を設定し、呼び出し側でのエラーハンドリングを容易にする。
        def instantiate_invalid_entry(token)
          Entry.new(
            number: '??',
            slug: token,
            kind: :unknown,
            label: 'INVALID',
            path: '',
            exists: false,
            in_catalog: false,
            valid: false
          )
        end

        # --- Phase 6: System Entry (システムファイルエントリ生成) ---
        # _titlepage 等のシステム予約ファイルに対する Entry を生成する。
        # カタログに載らないが valid として扱う。
        # number を nil に設定することで、basename がファイル名そのもの（例: _toc）になる。
        # _titlepage/_legalpage/_colophon は .cache/vs/ に配置される
        def instantiate_system_entry(token, kind)
          cached = CACHED_SYSTEM_FILES.include?(token) || token.match?(/\A_part\d+\z/)
          dir = cached ? Common::CACHE_DIR : contents_dir
          path = File.join(dir, "#{token}.md")
          Entry.new(
            number: nil,
            slug: token,
            kind:,
            label: kind.to_s.upcase,
            path:,
            exists: File.exist?(path),
            in_catalog: false,
            valid: true
          )
        end

        def normalize_slug_token(token)
          slug = token.to_s.strip
          slug = File.basename(slug)
          slug = slug.sub(/\.(md|markdown)\z/i, '')
          slug = slug.downcase.tr(' ', '-')
          slug = slug.gsub(/[^a-z0-9._-]+/, '-')
          slug = slug.gsub(/-+/, '-')
          slug = slug.gsub(/\A-+|-+\z/, '')
          slug.empty? ? nil : slug
        rescue StandardError
          nil
        end

        def instantiate_new_entry_from_slug(slug)
          number = allocate_number
          basename = "#{number}-#{slug}"
          instantiate_entry(basename, 'NEW', :chapter, in_catalog: false)
        end

        def reset_number_tracking(catalog)
          @catalog_numbers = catalog.filter_map(&:number)
          @used_number_set = nil
          @allocated_numbers = []
        end

        def used_number_set
          return @used_number_set if @used_number_set

          numbers = Set.new(@catalog_numbers)
          Dir.glob(File.join(contents_dir, '*.md')).each do |path|
            if (num = File.basename(path, '.md')[/\A(\d{2})/, 1])
              numbers << num
            end
          end

          @used_number_set = numbers
        end

        def allocate_number
          (1..AUTO_NUMBER_MAX).each do |candidate|
            number = format('%02d', candidate)
            next if used_number_set.include?(number)

            used_number_set << number
            @allocated_numbers << number
            return number
          end

          raise StandardError, format('01-%02d までの章番号がすべて使用済みです', AUTO_NUMBER_MAX)
        end
      end
    end
  end
end
