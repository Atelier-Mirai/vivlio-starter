# frozen_string_literal: true

require_relative '../config_keys'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # Volumes: 分冊（catalog.yml の VOLUMES）
      # ------------------------------------------------
      # 巻は順番のある並びとして扱い、巻の数（上下・上中下・第 N 分冊）を決め打ちしない。
      # 巻の名前の意味は読まず、「前の巻」「最初の巻」「最後の巻」は並びの順から決める（multivolume-spec.md §2）。
      #
      # 目次を読むほかの処理を直さずに済むよう、CatalogLoader.load_catalog は、ここで選んだ範囲の目次を
      # 今と同じ形の Hash（PREFACE・CHAPTERS・APPENDICES・POSTFACE）で返す（§3.4）。選び方は 3 通り:
      #   - 巻（Volume）… vs build lower。その巻の目次
      #   - :combined   … 巻を選ばない vs build（合本）。本全体の前書き（無ければ最初の巻の前書き）・全巻の本文と付録・
      #                   本全体の後書き（無ければ最後の巻の後書き）（§4.3・multivolume-book-matter-spec.md R2）
      #   - :all        … 既定。どれかの巻に載った原稿すべて。原稿の検査と、章の種類の解決に使う（§6.1）
      # 選択はプロセスに一つだけ持つ。全巻を続けて組むとき（vs build all）は巻ごとに別のプロセスで組む（§4.2）。
      #
      # VOLUMES と同じ高さに書いた PREFACE・POSTFACE は、本全体の前書き・後書き（multivolume-book-matter-spec.md）。
      # 巻の目次（sections_of）では、本全体の前書きを最初の巻の、後書きを最後の巻のものとして重ねる。
      # Volume#sections は巻に書いたものだけを持つ（合本で巻の前書き・後書きを外すのに要る）。
      # ------------------------------------------------
      module Volumes
        KEY = 'VOLUMES'

        # VOLUMES と同じ高さに書ける区分（本全体の前書き・後書き）。本文の章・付録は巻の中にだけ書く
        BOOK_MATTER_KEYS = %w[PREFACE POSTFACE].freeze

        # 巻そのものの設定。大文字のキーはその巻の目次（CatalogLoader::SECTION_KEYS）
        VOLUME_KEYS = %w[name id chapter_start appendix_start whole_toc].freeze

        # 巻で上書きできる book.yml の書誌情報（book: の下のキーを平らに書く。multivolume-spec.md §3.2）。
        # 一覧を書き並べず ConfigKeys から作るので、book: にキーを足せば巻でもそのまま上書きできる
        BOOK_KEYS = ConfigKeys.book_keys.freeze

        # 巻に書ける小文字のキーすべて
        SETTING_KEYS = (VOLUME_KEYS + BOOK_KEYS).freeze

        # 巻の id。ファイル名と、コマンドの引数（vs build lower）に使う。英字で始め、数字は末尾だけにするので、
        # 章の番号（21）や範囲（21-23）と読み分けられる。大文字と小文字は区別しない（list が小文字にそろえる）
        ID_PATTERN = /\A[a-z]+[0-9]*\z/

        # vs build all（全巻を続けて組む）のために、id には使えない名前
        ALL = 'all'

        # 巻。index は並びでの位置（0 から）、sections はその巻の目次（区分 => 項目）
        Volume = Data.define(:index, :name, :id, :settings, :sections) do
          def chapter_start = settings['chapter_start']
          def appendix_start = settings['appendix_start']
          def whole_toc? = settings['whole_toc'] == true
          # 巻に書いた書誌情報（book.yml の book: を上書きする値）
          def book_overrides = settings.slice(*BOOK_KEYS)
        end

        module_function

        # --- 選択 ---

        # 今の選択（Volume / :combined / :all）
        def selection = @selection || :all

        def select!(value)
          @selection = value
        end

        # 選んだ巻。巻を選んでいなければ nil
        def current = selection.is_a?(Volume) ? selection : nil

        # 一時的に選択を変えて yield する（全巻の原稿で数えたい検査のため）
        def with_selection(value)
          previous = @selection
          @selection = value
          yield
        ensure
          @selection = previous
        end

        # --- 読み取り ---

        # catalog.yml に VOLUMES が書かれているか
        def defined_in?(catalog) = catalog.is_a?(Hash) && catalog.key?(KEY)

        # 目次に巻が書かれているか（読めない目次は書かれていないとみなす）
        def enabled? = defined_in?(raw_catalog)

        # 巻の並び。形の正しくない項目は飛ばす（知らせるのは Guards::VolumeDefinitionCheck）
        # @return [Array<Volume>]
        def list(catalog = raw_catalog)
          return [] unless defined_in?(catalog)

          Array(catalog[KEY]).select { it.is_a?(Hash) }.each_with_index.map do |entry, index|
            Volume.new(index:, name: entry['name'].to_s, id: entry['id'].to_s.downcase,
                       settings: entry.slice(*SETTING_KEYS),
                       sections: entry.slice(*CatalogLoader::SECTION_KEYS))
          end
        end

        # id で巻を探す
        # @return [Volume, nil]
        def find(token, catalog = raw_catalog)
          key = token.to_s.strip.downcase
          list(catalog).find { it.id == key }
        end

        # 本全体の前書き・後書き（VOLUMES と同じ高さの PREFACE・POSTFACE）。中身の無い区分は書いていないとみなす
        # @return [Hash{String => Array}]
        def book_matter(catalog = raw_catalog)
          return {} unless defined_in?(catalog)

          catalog.slice(*BOOK_MATTER_KEYS).transform_values { Array(it) }.reject { |_, items| items.empty? }
        end

        # 巻の目次（区分 => 項目）。本全体の前書きは最初の巻の前書きに、後書きは最後の巻の後書きに重ねる
        # （multivolume-book-matter-spec.md R3）。巻が一つなら両方とも載る。巻の前書き・後書きにも書いた原稿は、
        # 本全体の側に一度だけ残す。この並びがそのまま紙面の並びになる（catalog-written-order-spec.md R2）
        # @return [Hash]
        def sections_of(volume, catalog = raw_catalog)
          matter = book_matter(catalog)
          sections = volume.sections
          if volume.index.zero? && matter.key?('PREFACE')
            sections = sections.merge('PREFACE' => matter['PREFACE'] + own_items(sections, 'PREFACE', matter))
          end
          if volume.index == list(catalog).size - 1 && matter.key?('POSTFACE')
            sections = sections.merge('POSTFACE' => own_items(sections, 'POSTFACE', matter) + matter['POSTFACE'])
          end
          sections
        end

        # 巻の区分の項目から、本全体の同じ区分に書いた原稿を外したもの
        def own_items(sections, key, matter)
          first_appearances(Array(sections[key]), CatalogLoader.flatten_section(matter[key]).to_set)
        end

        # basename を載せた最初の巻（付録のように二つ以上の巻に載る原稿は最初の巻。本全体の前書きは最初の巻、
        # 後書きは最後の巻）
        # @return [Volume, nil]
        def containing(basename, catalog = raw_catalog)
          list(catalog).find { |volume| basenames_of(volume, catalog).include?(basename) }
        end

        # basenames をすべて載せた最初の巻。一つの巻に収まらなければ nil
        # @return [Volume, nil]
        def containing_all(basenames, catalog = raw_catalog)
          return nil if basenames.empty?

          list(catalog).find { (basenames - basenames_of(it, catalog)).empty? }
        end

        # 選択に応じた目次（区分 => 項目）。VOLUMES が無ければ catalog をそのまま返す
        # @return [Hash]
        def view(catalog)
          return catalog unless defined_in?(catalog)

          volumes = list(catalog)
          case selection
          in Volume => chosen then sections_of(volumes.find { it.id == chosen.id } || chosen, catalog)
          in :combined then combined_sections(volumes, catalog)
          else merged_sections(volumes, catalog)
          end
        end

        # 全巻の目次（本全体の前書き・後書きを含む）を区分ごとに巻の順でつなぐ。二つ以上の巻に載る原稿
        # （共通の付録・共通の章。§3.6）は、最初に載った所に一度だけ残す。部の中に書いた章も原稿の名前で見るので、
        # 部ごとに別物とみなさない
        def merged_sections(volumes, catalog)
          each_sections = volumes.map { sections_of(it, catalog) }
          CatalogLoader::SECTION_KEYS.to_h do |key|
            seen = Set.new
            [key, each_sections.flat_map { first_appearances(Array(it[key]), seen) }]
          end
        end

        # 項目の並びから、すでに載った原稿を外す。中身が無くなった部は載せない
        # @param seen [Set<String>] これまでに載った原稿の basename（書き足していく）
        def first_appearances(items, seen)
          items.filter_map do |item|
            case item
            in Hash
              parts = item.transform_values { first_appearances(Array(it), seen) }.reject { |_, children| children.empty? }
              parts.empty? ? nil : parts
            in nil then nil
            else
              names = CatalogLoader.expand_item(item)
              names = [item.to_s] if names.empty?
              next nil if names.all? { seen.include?(it) }

              seen.merge(names)
              item
            end
          end
        end

        # 全巻の原稿を、区分ごとに巻の順でつないだ並び。merged_sections と違い、二つ以上の巻に載る原稿は
        # 載った巻ごとに現れる（「前の章」の検査で、巻ごとの前後を見るため。§3.6）
        # @return [Array<String>] basename
        def reading_order(catalog = raw_catalog)
          each_sections = list(catalog).map { sections_of(it, catalog) }
          CatalogLoader::SECTION_KEYS.flat_map do |key|
            each_sections.flat_map { CatalogLoader.flatten_section(it[key]) }
          end
        end

        # 合本: 前書き → 全巻の本文 → 全巻の付録 → 後書き（§4.3）。前書きは、本全体の前書きを書いた本ではそれだけ、
        # 書いていない本では最初の巻の前書き。後書きも同じく、本全体の後書きか最後の巻の後書き。前書きと後書きは
        # 別々に決める（multivolume-book-matter-spec.md R2）。書いていない本を最初の巻・最後の巻に任せるのは、
        # 上巻の前書きが本全体の前書きを兼ねる上下巻の本で、合本から前書きが消えないようにするため
        def combined_sections(volumes, catalog)
          matter = book_matter(catalog)
          merged_sections(volumes, catalog).merge(
            'PREFACE' => matter.fetch('PREFACE') { Array(volumes.first&.sections&.[]('PREFACE')) },
            'POSTFACE' => matter.fetch('POSTFACE') { Array(volumes.last&.sections&.[]('POSTFACE')) }
          )
        end

        # 巻に載った原稿の basename（本全体の前書きは最初の巻に、後書きは最後の巻に含める）
        def basenames_of(volume, catalog = raw_catalog)
          sections = sections_of(volume, catalog)
          CatalogLoader::SECTION_KEYS.flat_map { CatalogLoader.flatten_section(sections[it]) }
        end

        # --- 番号（§5） ---

        # 選んだ巻の最初の本文の章の前までの数（「第 N 章」に足す数）。巻を選んでいなければ 0
        def chapter_offset
          volume = current
          return 0 unless volume

          chapter_starts.fetch(volume.id, 1) - 1
        end

        # 巻ごとの最初の本文の章の番号。既定は前の巻から続け、chapter_start を書いた巻はその番号から始める
        # @return [Hash{String => Integer}] id => 番号
        def chapter_starts(volumes = list)
          next_start = 1
          volumes.to_h do |volume|
            start = Integer(volume.chapter_start || next_start, exception: false) || next_start
            next_start = start + CatalogLoader.flatten_section(volume.sections['CHAPTERS']).uniq.size
            [volume.id, start]
          end
        end

        # 付録の記号（小文字 1 字）。VOLUMES が無いとき・付録として載っていないときは nil。
        #
        # 既定は、全巻を巻の順に見て初めて出た付録に次の記号を振り、再び載る巻でも同じ記号を使う。
        # appendix_start を書いた巻を選んで組むときは、その巻の付録だけを指定の記号から振る（§5.2）
        # @param number [Integer, String] 付録の番号
        # @return [String, nil]
        def appendix_letter(number)
          volumes = list
          return nil if volumes.empty?

          n = number.to_i
          volume = current
          index = if volume&.appendix_start
                    appendix_numbers(volume).index(n)&.+(letter_index(volume.appendix_start))
                  else
                    volumes.flat_map { appendix_numbers(it) }.uniq.index(n)
                  end
          index && ('a'..'z').to_a[index]
        end

        # 巻の付録の番号（書いた順。catalog-written-order-spec.md R3）
        def appendix_numbers(volume)
          CatalogLoader.flatten_section(volume.sections['APPENDICES']).filter_map do
            CatalogLoader.extract_chapter_number(it)
          end.uniq
        end

        # 「A」→ 0。読めない値は 0
        def letter_index(letter) = [('a'..'z').to_a.index(letter.to_s.strip.downcase).to_i, 0].max

        # --- 引数での巻の指定（改善案 #126） ---

        # コマンドの引数が巻の指定なら、その id か all（小文字）。巻は 1 語だけで指定する。
        # ほかの引数と並べたものは章の指定として読むので、見つからない章として止まる
        # @param arguments [Array<String>]
        # @return [String, nil]
        def token_in(arguments)
          return nil unless arguments.size == 1 && enabled?

          token = arguments.first.to_s.strip.downcase
          token if token == ALL || find(token)
        end

        # 巻の指定ならその巻を選んで空を、章の指定ならそのまま返す。all は全巻の原稿を見る既定のまま
        # （preflight・lint・metrics 用。vs build は巻の設定を重ねて組むので、自分で選ぶ）
        # @param arguments [Array<String>]
        # @return [Array<String>] 章の指定
        def select_from_arguments!(arguments)
          token = token_in(arguments)
          return arguments unless token

          select!(find(token)) unless token == ALL
          []
        end

        # 巻を選べないとき。detail は直し方
        class SelectionError < StandardError
          attr_reader :detail

          def initialize(message, detail: nil)
            super(message)
            @detail = detail
          end
        end

        # id に当たる巻
        # @raise [SelectionError] 巻が書かれていない・見つからない
        # @return [Volume]
        def find!(token)
          volumes = list
          if volumes.empty?
            raise SelectionError.new(
              "config/catalog.yml に巻（VOLUMES）が書かれていないので、巻 #{token} を選べません",
              detail: ['分冊にするなら、config/catalog.yml を次のように巻ごとに書きます:',
                       'VOLUMES:', '  - name: 上巻', '    id: upper', '    CHAPTERS:', '      - 01-intro',
                       '  - name: 下巻', '    id: lower', '    CHAPTERS:', '      - 21-next']
            )
          end

          find(token) || raise(SelectionError.new(
                                 "巻 #{token} が config/catalog.yml の VOLUMES に見つかりません",
                                 detail: "書かれている巻: #{volumes.map { "#{it.id}（#{it.name}）" }.join('、')}"
                               ))
        end

        # 中間 HTML の置き場に、最後に組んだ巻を記録するファイル。巻を切り替えて --no-clean で組むと、
        # 前の巻の HTML が本文の章の並びに混ざって番号がずれるので、違えば置き場を空にする（§4.1）
        def workspace_marker = File.join(Common::BUILD_DIR, '.volume')

        # 今の選択を表す文字（巻の id・合本・全巻）
        def selection_key = current&.id || selection.to_s

        # 置き場の巻が今の選択と違えば置き場を空にし、今の選択を記録する。巻の無い本では何もしない
        def prepare_workspace!
          return unless enabled?

          recorded = File.read(workspace_marker).strip if File.file?(workspace_marker)
          if recorded && recorded != selection_key
            Common.log_action("[clean] 前回は別の巻（#{recorded}）を組んだので、中間生成物を消してから組みます")
            FileUtils.rm_rf(Common::BUILD_DIR)
          end
          FileUtils.mkdir_p(Common::BUILD_DIR)
          File.write(workspace_marker, selection_key)
        end

        # --- 巻の設定（§4.1） ---

        # 巻に書いた書誌情報（書名・ISBN・発行日・表紙など）を、book.yml の book: に重ねた CONFIG にする。
        # 値を空欄にしたキー（nil）は、book.yml と同じく上書きしない（deep_merge_config の決まり）
        def apply_config!(volume)
          overrides = volume.book_overrides
          return if overrides.empty?

          merged = Common.deep_merge_config(Common.load_config, { book: overrides.transform_keys(&:to_sym) })
          Common.install_configuration!(Common.wrap_config(merged).freeze)
        end

        # 読めない目次は空とみなす（知らせるのは CatalogFileCheck）
        def raw_catalog
          CatalogLoader.load_raw_catalog
        rescue StandardError
          {}
        end
      end
    end
  end
end
