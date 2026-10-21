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

        # 範囲の指定（`11-13`）
        RANGE_TOKEN = /\A(\d+)-(\d+)\z/

        # 章番号の範囲から kind を決定するためのマッピング。
        # 00: preface, 01-89: chapter, 90-98: appendix, 99: postface
        # 使うのは catalog.yml に載っていない原稿だけ。載っている原稿は SECTION_KINDS で決まる。
        KIND_RANGES = { preface: 0..0, chapter: 1..89, appendix: 90..98, postface: 99..99 }.freeze

        # catalog.yml の区分から kind を決めるためのマッピング。区分は番号より優先する
        # （catalog-section-kind-spec.md §2.1）。巻ごとの前書き（`20-vol2-intro` を PREFACE に書く）のように、
        # 番号の範囲の外の原稿を前書き・後書きとして組めるようにするため。
        SECTION_KINDS = { 'PREFACE' => :preface, 'CHAPTERS' => :chapter,
                          'APPENDICES' => :appendix, 'POSTFACE' => :postface }.freeze

        # システム予約ファイルの kind マッピング。
        # カタログに載らない特殊ファイルを仮想 Entry として解決するために使用。
        SYSTEM_FILE_KINDS = {
          '_titlepage' => :titlepage,
          '_legalpage' => :legalpage,
          '_colophon' => :colophon,
          '_indexpage' => :indexpage,
          '_glossarypage' => :glossarypage,
          '_toc' => :toc,
          '_whole_toc' => :whole_toc # 分冊の全巻目次（multivolume-spec.md §9）
        }.freeze

        # .cache/vs/ に生成されるシステムページ（contents/ ではなくキャッシュに配置）
        CACHED_SYSTEM_FILES = %w[_titlepage _legalpage _colophon _whole_toc].freeze

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
            resolve_pieces(split_tokens(tokens), catalog)
          end
        end

        # CLI の指定を 1 つずつの指定に分ける（カンマで分け、contents/ と拡張子を外す）。
        # 範囲は広げない。指定ごとに結果を見たい ChapterTargetCheck が使う。
        # @param tokens [Array<String>] CLI から受け取ったトークン配列
        # @return [Array<String>]
        def split_tokens(tokens)
          prefix = %r{\A#{Regexp.escape(contents_dir)}/}
          # 除くのは章のファイルの拡張子だけにする。点から後ろを何でも拡張子とみなすと、
          # `01-vol.53_09_482` を `01-vol` と読み、存在しない原稿を開いてビルドが異常終了していた
          Array(tokens).compact.flat_map { it.to_s.split(',') }.map(&:strip)
                       .map { File.basename(it.sub(prefix, '')).sub(/\.(?:md|markdown|html|pdf)\z/i, '') }
                       .reject(&:empty?)
        end

        # 範囲の指定（`11-13`、降順の `13-11` も）か
        def self.range_token?(token) = token.match?(RANGE_TOKEN)

        # ファイルパスから Entry を取得する便利メソッド。
        # @param file_path [String] Markdown/HTML ファイルのパス
        # @return [Entry] 解決された Entry オブジェクト
        def resolve_file(file_path)
          basename = File.basename(file_path).sub(/\.(md|html)\z/i, '')
          resolve([basename]).first
        end

        # catalog.yml に載っていない原稿の kind。番号の範囲で決め、範囲の外は本文の章とみなす
        # @param number [String, Integer]
        # @return [Symbol]
        def self.kind_for_number(number) = KIND_RANGES.find { |_, range| range.cover?(number.to_i) }&.first || :chapter

        private

        attr_reader :catalog_path, :contents_dir

        # --- Phase 1: Normalization (入力の正規化) ---
        # 指定ごとに、ゼロ埋め・範囲の展開をしてカタログと突き合わせる。
        #
        # **範囲は「その番号の間にある章」と読む**（改善案 #113）。章の番号は飛び飛びに
        # 振るもの（00・11〜14・21…）なので、`00-11` の 01〜10 は著者が名指しした章ではない。
        # catalog.yml にも contents/ にも無い番号は落とし、誤りにしない。範囲の中の
        # 未登録の草稿を含めるかはコマンドが決める（build・preflight は in_catalog? で絞る）。
        # 単独の指定は落とさない。打ち間違いを黙って捨てないよう、ChapterTargetCheck が止める。
        def resolve_pieces(pieces, catalog)
          seen = Set.new
          pieces.flat_map do |piece|
            names = expand_piece(piece).reject { seen.include?(it) }
            seen.merge(names)
            entries = names.map { match_entry(it, catalog) }
            self.class.range_token?(piece) ? entries.reject { absent_in_range?(it) } : entries
          end
        end

        # 範囲の欠けた番号か。番号の重なりで解決できなかったもの（valid: false）は残し、
        # DuplicateNumberCheck に止めさせる
        def absent_in_range?(entry) = entry.valid? && !entry.in_catalog? && !entry.exists?

        def expand_piece(piece)
          case piece
          in /\A(\d+)\z/
            # 数字のみ: ゼロ埋め
            [format('%02d', ::Regexp.last_match(1).to_i)]
          in RANGE_TOKEN
            # 範囲指定: 展開（降順は昇順に並べ替える）
            s = ::Regexp.last_match(1).to_i
            e = ::Regexp.last_match(2).to_i
            (s <= e ? s..e : e..s).map { format('%02d', it) }
          in /\A(\d+)([-_].+)\z/
            # 番号+スラグ: 番号部分をゼロ埋め
            ["#{format('%02d', ::Regexp.last_match(1).to_i)}#{::Regexp.last_match(2)}"]
          else
            # その他: そのまま（invalid として後で処理される可能性あり）
            [piece]
          end
        end

        # --- Phase 2: Catalog Loading (カタログ読み込み) ---
        # YAML パース・セクションと番号だけの項目の展開は Build::CatalogLoader に一本化した
        # （仕様: catalog-parser-unification-spec.md）。ここでは
        # CatalogEntry（basename/label/section）→ Entry への変換のみを行う。
        # instantiate_entry は常に Entry を返すため compact は不要。
        # 同じ章を二度書いた行だけをまとめ、番号が同じ別の章は残す。番号でまとめると、
        # 重なった片方がビルドから黙って外れ、vs preflight も「未登録の原稿」と誤って案内していた
        # （重なりはビルドの前に DuplicateNumberCheck が止める）
        def load_catalog_entries
          Build::CatalogLoader
            .load_labeled_entries(catalog_path:, contents_dir:)
            .map { instantiate_entry(it.basename, it.label, SECTION_KINDS.fetch(it.section), in_catalog: true) }
            .uniq(&:basename)
        end

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
            # 番号のみ形式: 番号でマッチ。番号の重なった章があれば、どちらを指すか決められないので解決しない
            token_num = format('%02d', token.to_i)
            found = catalog.select { it.number == token_num }
            return instantiate_invalid_entry(token) if found.size > 1
            return found.first if found.any?

            # カタログにない場合、ファイルシステムからスラッグを補完する。
            # 優先順位: スラッグ付き (NN-slug.md) > 数字のみ (NN.md)
            # 例: "2" → contents/02-history.md が存在すれば "02-history" として解決。
            fs_matches = Dir.glob(File.join(contents_dir, "#{token_num}-*.md"))
            return instantiate_invalid_entry(token) if fs_matches.size > 1

            if fs_matches.any?
              fs_basename = File.basename(fs_matches.first, '.md')
              return instantiate_entry(fs_basename, 'UNCATALOGED', nil, in_catalog: false)
            end

            # スラッグ付きファイルが無い場合、数字のみファイル (NN.md) を探索
            # 例: "2" → contents/02.md が存在すれば slug=nil の Entry として解決。
            numeric_file = File.join(contents_dir, "#{token_num}.md")
            if File.exist?(numeric_file)
              return instantiate_entry(token_num, 'UNCATALOGED', nil, in_catalog: false)
            end

            # どちらも見つからない場合、番号のみの新規エントリとして生成
          end
          instantiate_entry(token, 'NEW', nil, in_catalog: false)
        end

        def match_slug_entry(token, catalog)
          slug = normalize_slug_token(token)
          return instantiate_invalid_entry(token) unless slug

          # 名前が同じ章が 2 つ以上あれば、どちらを指すか決められないので解決しない（片方を黙って選ばない）
          found = catalog.select { |entry| entry.slug&.downcase == slug }
          return instantiate_invalid_entry(token) if found.size > 1
          return found.first if found.any?

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
            instantiate_entry(matches.first, 'UNCATALOGED', nil, in_catalog: false)
          else
            instantiate_invalid_entry(token)
          end
        end

        # --- Phase 4: Entry オブジェクトの実体化（正常系）---
        # basename から Entry を生成する。形式が不正なら invalid_entry を返す。
        # 数字のみファイル（NN）にも対応し、slug=nil の Entry を生成する。
        # @param basename [String] 章ファイルのベース名（例: "01-life" または "02"）
        # @param label [String] カタログのセクション名（例: "CHAPTERS"）
        # @param section_kind [Symbol, nil] catalog.yml の区分から決めた kind。nil なら番号の範囲で決める
        # @param in_catalog [Boolean] カタログに登録済みかどうか
        # @return [Entry] 生成された Entry オブジェクト
        def instantiate_entry(basename, label, section_kind, in_catalog:)
          # 形式チェック: 数字で始まり、オプションで -slug または _slug が続く
          return instantiate_invalid_entry(basename) unless basename =~ /\A(\d+)(?:[-_](.+))?\z/

          num = ::Regexp.last_match(1)
          slug = ::Regexp.last_match(2)
          number = format('%02d', num.to_i)
          # slug がある場合は number-slug、ない場合は number のみ
          actual_basename = slug ? "#{number}-#{slug}" : number
          path = File.join(contents_dir, "#{actual_basename}.md")
          kind = section_kind || self.class.kind_for_number(number)

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
          instantiate_entry(basename, 'NEW', nil, in_catalog: false)
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
