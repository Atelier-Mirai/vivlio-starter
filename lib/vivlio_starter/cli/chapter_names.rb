# frozen_string_literal: true

require_relative 'common'
require_relative 'build/catalog_loader'

module VivlioStarter
  module CLI
    # 章の名前（basename「NN-slug」）の決まりと、ほかの章との重なりを確かめる
    # （pdf-read-file-naming-spec.md §2.2・§4.1・§7）。
    #
    # 章の名前は `vs create` が作る形に限る。番号は 2 桁、スラッグは英小文字・数字・ハイフンで、数字だけにはしない。
    # 点を含む名前（`97-sample.v2`）は章の解決が拡張子と読んで別の章を指し、`_` で番号を区切った名前（`97_sample`）は
    # 存在しない `97-sample.md` を指し、数字だけのスラッグ（`01-245`）は章の範囲と読まれる。
    #
    # 番号が同じ別の章があると、`vs build 97` がどちらを指すか決められない。名前（slug）が同じ別の章があると、
    # `vs build sample` と章のラベル ID（`@ch-sample`）がどちらを指すか決められない。
    # 章を作る・名前を変えるコマンド（vs create・vs rename・vs pdf:read）は作る前にここで確かめ、
    # ビルドの前の検査（ChapterFileNameCheck・DuplicateNumberCheck・DuplicateSlugCheck）は、
    # 手で付けた名前（Finder の複製「97-sample のコピー.md」など）や既にできてしまった重なりを止める。
    module ChapterNames
      module_function

      # 章の名前の決まり（「11-intro」「15」）
      VALID_BASENAME = /\A\d{2}(?:-(?!\d+\z)[a-z0-9]+(?:-[a-z0-9]+)*)?\z/

      def valid?(basename) = basename.to_s.match?(VALID_BASENAME)

      # 著者が打った章の名前を決まりの形に整える（「5-Intro_Guide」→「05-intro-guide」）。
      # 整えるのは番号の 0 埋め・大文字・`_` だけで、点・空白・日本語を含む名前は整えずに nil を返す（§2.2）
      # @return [String, nil]
      def normalize(name)
        digits, slug = name.to_s.strip.match(/\A(\d{1,2})(?:[-_](.+))?\z/)&.captures
        return nil unless digits

        normalized = [format('%02d', digits.to_i), slug&.downcase&.tr('_', '-')].compact.join('-')
        valid?(normalized) ? normalized : nil
      end

      # 今ある章の basename。contents/ の原稿と catalog.yml の章（原稿がまだ無いものも）。
      # システムページ（「_」始まり）は除く
      # @return [Array<String>]
      def existing_basenames
        contents = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { File.basename(it, '.md') }
        (contents + catalog_basenames).uniq.reject { it.start_with?('_') }.sort
      end

      # 2 桁にそろえた番号（「97」）。番号を持たなければ nil。章の解決と同じく `_` も番号の区切りとみなす
      def number_of(basename) = basename[/\A(\d+)(?=[-_]|\z)/, 1]&.then { format('%02d', it.to_i) }

      # 小文字にした名前（「sample」）。番号だけの章（「15」）は nil
      def slug_of(basename) = basename[/\A\d+[-_](.+)\z/, 1]&.downcase

      # basename と重なる今ある章を、理由の文にして返す。
      # 名前を変えるときは、変える元の章を except に渡す。変えない部分（番号だけ変えるときの名前など）は見ない。
      # 既にある重なりを解くための `vs rename 97-sample 97-sample-2` を、番号 97 の重なりで止めないため
      # @return [Array<String>] 「97 番は 97-sample が使っています」の形
      def conflicts(basename, taken, except: nil)
        others = taken - [basename, except]
        number = number_of(basename)
        slug = slug_of(basename)
        number_owner = others.find { number_of(it) == number } if number && number != (except && number_of(except))
        slug_owner = others.find { slug_of(it) == slug } if slug && slug != (except && slug_of(except))
        [number_owner && "#{number} 番は #{number_owner} が使っています",
         slug_owner && "スラッグ #{slug} は #{slug_owner} が使っています"].compact
      end

      # basename を、決まりの形に直し、今ある章と重ならないようにした例。
      # 使えない字はハイフンにし（「97-sample のコピー」→「97-sample」）、重なる番号は同じ区分の空き番号に、
      # 重なるスラッグは「-2」などを足したものにする。直しようがなければ nil
      # @return [String, nil]
      def suggestion(basename, taken, except: nil)
        others = taken - [basename, except]
        number, slug = repaired_parts(basename)
        keep_number = except && number == number_of(except)
        keep_slug = except && slug == slug_of(except)
        if number.nil? || (!keep_number && others.any? { number_of(it) == number })
          number = free_number(number || '01', others)
        end
        slug = free_slug(slug, others) if slug && !keep_slug && others.any? { slug_of(it) == slug }
        number && [number, slug].compact.join('-')
      end

      # 章の名前を old_basename から new_basename へ変えるコマンド。catalog.yml に載っていて章の解決で指せる章は
      # `vs rename`（画像・目次・参照も追随する）、載っていない原稿（vs rename は扱わない）は `mv`。
      # 空白などはエスケープし（shell_word）、引用符を求めない
      # @return [String]
      def rename_command(old_basename, new_basename)
        in_catalog = catalog_basenames.include?(old_basename)
        return "vs rename #{shell_word(old_basename)} #{new_basename}" if in_catalog && old_basename.match?(/\A\d+(?:-|\z)/)

        old_path = File.join(Common::CONTENTS_DIR, "#{old_basename}.md")
        command = "mv #{shell_word(old_path)} #{File.join(Common::CONTENTS_DIR, "#{new_basename}.md")}"
        in_catalog ? "#{command}（config/catalog.yml の #{old_basename} も #{new_basename} に書き換える）" : command
      end

      # シェルにそのまま打てる形。空白・括弧などシェルで意味を持つ ASCII の記号だけを `\` でエスケープする。
      # Shellwords.escape は日本語の字にも `\` を付け（「\の\コ\ピ\ー」）、案内が読めなくなる
      def shell_word(text) = text.gsub(%r{([^A-Za-z0-9_\-.,:+/@%=\p{^ASCII}])}) { "\\#{Regexp.last_match(1)}" }

      # number と同じ区分（本文・付録など）で、taken のどれも使っていない番号
      def free_number(number, taken)
        Build::CatalogLoader.free_number_in_section(number.to_i, taken.filter_map { number_of(it)&.to_i })
      end

      # taken のどれも使っていない名前（「sample-2」「sample-3」…）
      def free_slug(slug, taken)
        used = taken.filter_map { slug_of(it) }
        (2..).lazy.map { "#{slug}-#{it}" }.find { !used.include?(it) }
      end

      # 決まりの形に直した番号とスラッグ。3 桁以上の番号は nil（空き番号を当てる）。
      # スラッグに使える字が残らなければ「chapter」、数字だけになれば「chapter-245」
      def repaired_parts(basename)
        digits, rest = basename.match(/\A(\d+)(?:[-_\s](.*))?\z/m)&.captures
        number = digits && digits.size <= 2 ? format('%02d', digits.to_i) : nil
        return [number, nil] if rest.nil? || rest.empty?

        slug = rest.unicode_normalize(:nfkc).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
        slug = 'chapter' if slug.empty?
        slug = "chapter-#{slug}" if slug.match?(/\A\d+\z/)
        [number, slug]
      end

      # 読めない catalog.yml は CatalogFileCheck が知らせるので、ここでは章として数えない
      def catalog_basenames
        Build::CatalogLoader.load_labeled_entries.map(&:basename)
      rescue StandardError
        []
      end
    end
  end
end
