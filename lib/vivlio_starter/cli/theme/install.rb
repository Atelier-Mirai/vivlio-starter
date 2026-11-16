# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/install.rb
# ================================================================
# 責務:
#   vs theme:add の取得と複製（theme-contract-spec.md §7.2 の「複製の決まり」）。表示と確認は
#   ThemeCommands が行い、ここは誤りを Theme::Error で上げる。
#
# 経路（§7.2 の「経路と段階」）:
#   同梱のテーマの名前・手元のディレクトリ・手元の zip は S6。git の URL と npm のパッケージ名は S7 で作る。
#
# 複製の決まり（どの経路も同じ）:
#   1. テーマのディレクトリは、theme.yml のあるディレクトリ（指定した場所の直下か、その下の 1 階層）
#   2. 拡張子の許可の表にあるファイルだけを写す。写さなかったものは一覧にする。本の中に実行できる
#      ファイルが入らないので、「スクリプトを実行しない」が作りで成り立つ
#   3. シンボリックリンクは写さない。zip は、展開先の外を指すパス・シンボリックリンクの項目が
#      あれば展開せずに止める。展開は一時ディレクトリで行う
#   4. 置き換えの確認（ThemeCommands）
#   5. extends: の先が本に無ければ、同梱のテーマなら一緒に入れる（ThemeCommands）
# ================================================================

require 'fileutils'
require 'open3'
require 'yaml'
require_relative 'manifest'
require_relative 'contract'

module VivlioStarter
  module CLI
    module Theme
      # テーマの取得と複製
      module Install
        # 写すファイルの拡張子（§7.2 の 2）。README.md と LICENSE* は名前で許す
        ALLOWED_EXTENSIONS = %w[.yml .css .webp .png .jpg .jpeg .svg .avif .ttf .otf .woff .woff2].freeze

        # 一時ディレクトリに写したテーマ。dir は写した先（<一時>/themes/<名前>）、skipped は写さなかったもの
        Staged = Data.define(:name, :dir, :manifest, :skipped)

        # 本の themes/<名前>/ との違い（本のルートからでなく、テーマのディレクトリからの相対パス）
        Changes = Data.define(:added, :replaced, :removed) do
          def none? = added.empty? && replaced.empty? && removed.empty?
          def replacing? = !replaced.empty? || !removed.empty?
        end

        module_function

        # 指定からテーマのディレクトリを得る（zip は work の下へ展開する）
        # @param source [String] 同梱のテーマの名前・ディレクトリ・zip のパス
        # @param work [String] 一時ディレクトリ
        # @return [String] theme.yml のあるディレクトリ
        # @raise [Theme::Error]
        def fetch(source, work, root:, bundled_root: BUNDLED_ROOT)
          text = source.to_s.strip
          bundled = File.join(bundled_root, DIR, text)
          return bundled if text.match?(Manifest::NAME_PATTERN) && File.file?(File.join(bundled, Manifest::FILE))

          path = File.expand_path(text, root)
          return theme_directory(path, text) if File.directory?(path)
          return theme_directory(extract_zip(path, File.join(work, 'zip'), text), text) if File.file?(path) && zip?(path)

          if remote?(text)
            raise Error.new("#{text} からの追加は、この版ではまだできません",
                            detail: 'テーマのディレクトリか zip を手元に置いて、そのパスを指定してください')
          end

          names = Dir.glob("*/#{Manifest::FILE}", base: File.join(bundled_root, DIR)).map { File.dirname(it) }.sort
          raise Error.new("テーマ #{text} が見つかりません",
                          detail: ["同梱のテーマ: #{names.join('・')}", 'ディレクトリか zip なら、パスを確かめてください'])
        end

        # git の URL・npm のパッケージ名の形か（S7 で作る経路）
        def remote?(text) = text.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || text.start_with?('git@', '@') || text.end_with?('.git')

        def zip?(path) = File.extname(path).casecmp?('.zip')

        # theme.yml のあるディレクトリ（直下か、その下の 1 階層。§7.2 の 1）
        def theme_directory(path, label)
          return path if File.file?(File.join(path, Manifest::FILE))

          found = Dir.children(path).sort.select do |child|
            dir = File.join(path, child)
            !child.start_with?('.') && !File.symlink?(dir) && File.file?(File.join(dir, Manifest::FILE))
          end
          return File.join(path, found.first) if found.size == 1
          raise Error.new("#{label} に、テーマが #{found.size} 個あります: #{found.join('・')}", detail: '入れるテーマのディレクトリを指定してください') if found.size > 1

          raise Error.new("#{label} に #{Manifest::FILE} が見つかりません",
                          detail: "#{Manifest::FILE} のあるディレクトリ（またはその 1 つ上）を指定してください")
        end

        # zip を検査してから展開する（§7.2 の 3）。検査に通らなければ展開しない
        def extract_zip(path, dest, label)
          problems = ZipInspector.problems(path)
          unless problems.empty?
            raise Error.new("#{label} は展開しません（中に、展開先の外を指すパスかシンボリックリンクがあります）",
                            detail: problems.first(10))
          end
          raise Error.new('zip を展開する unzip が見つかりません', detail: 'zip を展開したディレクトリを指定してください') unless Common.external_command_available?('unzip')

          FileUtils.mkdir_p(dest)
          _out, err, status = Open3.capture3('unzip', '-qq', path, '-d', dest)
          raise Error.new("#{label} を展開できません", detail: err.lines.first(5).map(&:chomp)) unless status.success?

          dest
        end

        # テーマを一時ディレクトリの themes/<名前>/ へ、許可の表のファイルだけ写し、theme.yml を検査する
        # @param from [String] theme.yml のあるディレクトリ
        # @param stage_root [String] 写す先の本のルートに見立てた一時ディレクトリ
        # @return [Staged]
        def stage(from, stage_root)
          name = declared_name(from)
          dir = File.join(stage_root, DIR, name)
          FileUtils.rm_rf(dir)
          FileUtils.mkdir_p(dir)
          skipped = copy_allowed(from, dir)
          manifest = Manifest.load(File.join(DIR, name), root: stage_root).tap { Contract.check!(it) }
          Staged.new(name:, dir:, manifest:, skipped:)
        end

        # theme.yml の name:（写す先のディレクトリの名前になる）
        def declared_name(from)
          raw = YAML.safe_load_file(File.join(from, Manifest::FILE))
          name = raw.is_a?(Hash) ? raw['name'] : nil
          return name if name.is_a?(String) && name.match?(Manifest::NAME_PATTERN)

          raise Error.new("#{Manifest::FILE} の name: が、テーマの名前の形になっていません: #{name.inspect}",
                          detail: 'name: は半角の英小文字・数字・ハイフンで書きます（例: name: mono）')
        rescue Psych::Exception => e
          raise Error.new("#{Manifest::FILE} を読めません", detail: e.message)
        end

        # 許可の表のファイルだけを写す。写さなかったもの（相対パス）を返す。
        # . で始まるディレクトリ（.git など）は中を見ずに 1 行で数える
        def copy_allowed(from, to, relative = '', skipped = [])
          Dir.children(File.join(from, relative)).sort.each do |child|
            path = relative.empty? ? child : File.join(relative, child)
            full = File.join(from, path)
            stat = File.lstat(full)
            if stat.symlink?
              skipped << "#{path}（シンボリックリンク）"
            elsif stat.directory?
              child.start_with?('.') ? skipped << "#{path}/" : copy_allowed(from, to, path, skipped)
            elsif stat.file? && allowed?(child)
              FileUtils.mkdir_p(File.dirname(File.join(to, path)))
              FileUtils.cp(full, File.join(to, path))
            else
              skipped << path
            end
          end
          skipped
        end

        def allowed?(name)
          ALLOWED_EXTENSIONS.include?(File.extname(name).downcase) || name == 'README.md' || name.start_with?('LICENSE')
        end

        # 本の themes/<名前>/ と、写したテーマの違い
        def changes(staged, root)
          dest = File.join(root, DIR, staged.name)
          incoming = files_in(staged.dir)
          current = File.directory?(dest) ? files_in(dest) : []
          replaced = (incoming & current).reject { FileUtils.identical?(File.join(staged.dir, it), File.join(dest, it)) }
          Changes.new(added: incoming - current, replaced:, removed: current - incoming)
        end

        def files_in(dir) = Dir.glob('**/*', File::FNM_DOTMATCH, base: dir).select { File.file?(File.join(dir, it)) }.sort

        # 写したテーマで本の themes/<名前>/ を置き換える
        def apply!(staged, root)
          dest = File.join(root, DIR, staged.name)
          FileUtils.rm_rf(dest)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp_r(staged.dir, dest)
        end
      end

      # zip の中央ディレクトリを読み、展開してはいけない項目を挙げる（§7.2 の 3）。
      # 展開する道具（unzip）の振る舞いに頼らず、展開の前に Ruby で読む
      module ZipInspector
        END_OF_CENTRAL_DIRECTORY = [0x06054b50].pack('V')
        CENTRAL_HEADER = 0x02014b50

        # Unix の S_IFMT と S_IFLNK（外部属性の上位 16 ビット）
        FILE_TYPE_MASK = 0o170000
        SYMLINK = 0o120000

        # 作った OS が Unix（外部属性に Unix のモードが入る）
        UNIX = 3

        module_function

        # @return [Array<String>] 問題のある項目の説明（無ければ空）
        # @raise [Theme::Error] zip として読めない
        def problems(path)
          entries(path).filter_map do |name, symlink|
            if symlink then "#{name}（シンボリックリンク）"
            elsif unsafe?(name) then "#{name}（展開先の外を指すパス）"
            end
          end
        end

        # 絶対パス・ドライブ名・.. を含むパス
        def unsafe?(name)
          name.start_with?('/', '\\') || name.match?(/\A[A-Za-z]:/) || name.split(%r{[/\\]}).include?('..')
        end

        # [名前, シンボリックリンクか] の並び
        def entries(path)
          data = File.binread(path)
          eocd = data.rindex(END_OF_CENTRAL_DIRECTORY)
          raise Error.new("#{File.basename(path)} は zip として読めません") unless eocd

          count, _size, offset = data.byteslice(eocd + 10, 10).unpack('vVV')
          raise Error.new("#{File.basename(path)} は大きすぎて読めません（ZIP64）", detail: '展開したディレクトリを指定してください') if count == 0xFFFF || offset == 0xFFFFFFFF

          position = offset
          Array.new(count) do
            header = data.byteslice(position, 46)
            raise Error.new("#{File.basename(path)} は zip として読めません（壊れています）") unless header&.bytesize == 46 && header.unpack1('V') == CENTRAL_HEADER

            made_by = header.byteslice(4, 2).unpack1('v')
            name_length, extra_length, comment_length = header.byteslice(28, 6).unpack('vvv')
            external = header.byteslice(38, 4).unpack1('V')
            name = data.byteslice(position + 46, name_length).force_encoding(Encoding::UTF_8)
            position += 46 + name_length + extra_length + comment_length
            [name.scrub, (made_by >> 8) == UNIX && ((external >> 16) & FILE_TYPE_MASK) == SYMLINK]
          end
        end
      end
    end
  end
end
