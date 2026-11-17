# frozen_string_literal: true

# ================================================================
# Test: theme_commands_test.rb
# ================================================================
# テスト対象:
#   vs theme・vs theme:add・vs theme:check・vs theme:new（ThemeCommands・Theme::Check・Theme::Install・
#   Theme::ZipInspector）
#
# 検証内容（theme-contract-spec.md §7.2・§9 の S6-8 の完了の条件）:
#   - 同梱の standard に theme:check を掛けて 🟡 も 🔴 も出ない
#   - theme:new x --extends standard の出力（と組版のテーマの雛形）が theme:check を通る
#   - theme:check がテーマ自身のファイルの、Kindle に届かない宣言・知らないクラス・!important・外部の URL・
#     Kindle で読者が選ぶ値を示す
#   - theme:add は許可の表のファイルだけを写し、写さなかったものを示す。extends: の先が無ければ同梱のものを一緒に入れる
#   - zip は、展開先の外を指すパス・シンボリックリンクがあれば、展開せずに止める（§7.2 の複製の決まりの 3）
#   - 本にあるテーマを置き換えるときは確認し、「いいえ」なら何も変えない。book.yml は書き換えない
#   - 同梱のテーマは scaffold.lock に記録し、同梱でないテーマは記録を消す（§7.3。S6-9）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'zlib'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/theme_commands'

module VivlioStarter
  module CLI
    class ThemeCommandsTest < Minitest::Test
      REPO_ROOT = File.expand_path('../../..', __dir__)

      # 完了の条件: 同梱の standard に掛けて 🟡 が 0 件（紙の寸法は 💡 で数だけ）
      def test_should_find_nothing_to_fix_in_the_bundled_standard_theme
        report = Theme::Check.run('standard', root: REPO_ROOT)

        assert_empty report.errors.map(&:message)
        assert_empty report.warnings.map(&:message)
        assert(report.findings.any? { it.level == :hint && it.message.include?('紙の寸法') })
      end

      # 完了の条件: theme:new の雛形（配色のテーマ・組版のテーマ）が theme:check を通る
      def test_should_create_themes_that_pass_the_check
        with_book do |root|
          out, = capture_io do
            assert_equal 0, ThemeCommands.new_theme('mono', extends: 'standard', root:)
            assert_equal 0, ThemeCommands.new_theme('plain', root:)
          end

          assert_equal [], Theme::Check.run('mono', root:).findings.map(&:message)
          assert_equal [], Theme::Check.run('plain', root:).findings.map(&:message)
          assert_equal 'standard', Theme.resolve('mono', root:).manifest.extends
          assert_includes out, 'name: mono'
          capture_io { assert_equal 1, ThemeCommands.new_theme('mono', root:) }
        end
      end

      # テーマ自身のファイルだけを見て、§3.5・§7.2 の範囲の外の書き方を示す
      def test_should_report_what_the_theme_writes_outside_the_contract
        with_book do |root|
          write_theme(root, 'loose', {
                        'extends' => 'standard', 'styles' => %w[theme.css],
                        'kindle_tokens' => { 'font-size' => '12pt', 'font-heading' => '"Noto Serif JP", serif' }
                      },
                      'theme.css' => <<~CSS,
                        .output { color: red !important; }
                        .sparkle { color: var(--book-color-accent); }
                        .talk p { color: var(--book-talk-accent); }
                        @import url("https://example.com/x.css");
                      CSS
                      'kindle.css' => "body.vs-kindle { --book-line-height: 1.8; --book-font-body: serif; }\n")

          messages = Theme::Check.run('loose', root:).warnings.map(&:message)

          assert(messages.any? { it.include?('theme.css:1') && it.include?('!important') })
          assert(messages.any? { it.include?('.sparkle は、契約 HTML に無いクラス') })
          assert(messages.any? { it.include?('var(--book-talk-accent)') && it.include?('Kindle では効きません') })
          assert(messages.any? { it.include?('theme.css:4') && it.include?('ネットワーク') })
          assert(messages.any? { it.include?('kindle_tokens.font-size') && it.include?('読者が選ぶ値') })
          assert(messages.any? { it.include?('kindle_tokens.font-heading') && it.include?('使えない書体') })
          assert(messages.any? { it.include?('kindle.css:1 の --book-line-height') })
          refute(messages.any? { it.include?('--book-font-body') }, '総称の名前は書いてよい')
          refute(messages.any? { it.include?('themes/standard/') }, '土台のテーマのファイルは見ない')
        end
      end

      # 見出しの改ページを値で書いた規則は、page.chapter_pagebreak・section_pagebreak が効かない（§3.5）。
      # 出力先の CSS では章見出しを見ない（章の改丁は PDF だけの設定）
      def test_should_report_heading_breaks_written_as_values
        with_book do |root|
          write_theme(root, 'breaks', { 'extends' => 'standard', 'styles' => %w[theme.css] },
                      'theme.css' => <<~CSS,
                        body.chapter h1 { break-before: recto; }
                        .section-topic h2 { break-before: page; }
                        h2.vs-break-merged { break-before: auto; }
                        body.chapter h2 { break-before: var(--book-section-break-before); }
                      CSS
                      'kindle.css' => "body.vs-kindle h1 { break-before: page; }\nbody.vs-kindle h2 { break-before: page; }\n")

          messages = Theme::Check.run('breaks', root:).warnings.map(&:message)

          assert_includes messages, 'themes/breaks/theme.css:1 の break-before: recto では、config/book.yml の page.chapter_pagebreak が効きません'
          assert_includes messages, 'themes/breaks/theme.css:2 の break-before: page では、config/book.yml の page.section_pagebreak が効きません'
          assert_includes messages, 'themes/breaks/kindle.css:2 の break-before: page では、config/book.yml の page.section_pagebreak が効きません'
          assert_equal 3, messages.count { it.include?('break-before') }, '値が auto・var() の規則と、出力先の CSS の h1 は出さない'
        end
      end

      # 写すのは許可の表のファイルだけ。土台が本に無ければ同梱のものを一緒に入れる。book.yml は変えない
      def test_should_copy_only_allowed_files_and_bring_the_bundled_base
        with_book(themes: false) do |root|
          source = File.join(root, 'download', 'mono-theme')
          write_theme_files(source, { 'name' => 'mono', 'contract' => 1, 'extends' => 'standard', 'tokens' => { 'color-accent' => '#555555' } },
                            'README.md' => '# mono', 'LICENSE.txt' => 'MIT', 'images/a.png' => 'png',
                            'package.json' => '{}', 'run.sh' => 'echo', '.git/HEAD' => 'ref')
          File.symlink('/etc/hosts', File.join(source, 'hosts.css'))
          book_yml = File.read(File.join(root, 'config', 'book.yml'))

          out, = capture_io { assert_equal 0, ThemeCommands.add(source, root:, input: StringIO.new('')) }

          assert_equal %w[LICENSE.txt README.md images/a.png theme.yml], Theme::Install.files_in(File.join(root, 'themes', 'mono'))
          assert File.file?(File.join(root, 'themes', 'standard', 'theme.yml')), '土台の standard も入る'
          %w[package.json run.sh .git/ hosts.css（シンボリックリンク）].each { assert_includes out, it }
          assert_includes out, 'config/book.yml の theme.color: green が、テーマ mono の値（#555555）を覆っています'
          assert_equal book_yml, File.read(File.join(root, 'config', 'book.yml'))
        end
      end

      # 本にあるテーマを置き換えるときは全部を見せて確認する。「いいえ」なら何も変えない
      def test_should_ask_before_replacing_a_theme_in_the_book
        with_book do |root|
          source = File.join(root, 'download', 'mono')
          write_theme_files(source, { 'name' => 'mono', 'contract' => 1, 'extends' => 'standard', 'version' => '2' })
          write_theme(root, 'mono', { 'extends' => 'standard', 'version' => '1' }, 'old.css' => '')
          before = Theme::Install.files_in(File.join(root, 'themes', 'mono')).to_h { [it, File.read(File.join(root, 'themes', 'mono', it))] }

          out, = capture_io { assert_equal 0, ThemeCommands.add(source, root:, input: StringIO.new("n\n")) }
          after = Theme::Install.files_in(File.join(root, 'themes', 'mono')).to_h { [it, File.read(File.join(root, 'themes', 'mono', it))] }

          assert_includes out, '置き換え: theme.yml'
          assert_includes out, '削除: old.css'
          assert_equal before, after

          capture_io { assert_equal 0, ThemeCommands.add(source, root:, input: StringIO.new("y\n")) }
          assert_equal %w[theme.yml], Theme::Install.files_in(File.join(root, 'themes', 'mono'))
        end
      end

      # §7.3: 同梱のテーマを入れたら scaffold.lock に記録する（vs upgrade が更新する）。同梱でないテーマは
      # 同じ名前でも記録を消し、vs upgrade が触らない著者のテーマにする。ほかの記録は変えない
      def test_should_record_bundled_themes_in_the_scaffold_lock
        with_book(themes: false) do |root|
          ScaffoldLock.write(root, version: '2.0.0', files: { 'stylesheets/custom.css' => 'sha256:x', 'themes/standard/old.css' => 'sha256:y' },
                                   declined: { 'themes/standard/old.css' => 'sha256:z' })

          capture_io { assert_equal 0, ThemeCommands.add('standard', root:, input: StringIO.new('')) }
          lock = ScaffoldLock.read(root)

          installed = Theme::Install.files_in(File.join(root, 'themes', 'standard')).map { "themes/standard/#{it}" }
          assert_equal installed.sort, lock[:files].keys.grep(%r{\Athemes/}).sort
          assert_equal ScaffoldLock.file_digest(File.join(root, 'themes', 'standard', 'theme.yml')), lock[:files]['themes/standard/theme.yml']
          assert_equal 'sha256:x', lock[:files]['stylesheets/custom.css']
          assert_empty lock[:declined]
          assert_path_exists File.join(root, '.cache', 'vs', 'scaffold-base', 'themes', 'standard', 'theme.yml'), '三方向のマージの祖先も進める'

          source = File.join(root, 'download', 'standard')
          write_theme_files(source, { 'name' => 'standard', 'contract' => 1 })
          capture_io { ThemeCommands.add(source, root:, input: StringIO.new("y\n")) }

          assert_empty ScaffoldLock.read(root)[:files].keys.grep(%r{\Athemes/})
          assert_equal 'sha256:x', ScaffoldLock.read(root)[:files]['stylesheets/custom.css']
        end
      end

      # 完了の条件: zip は、展開先の外を指すパスとシンボリックリンクがあれば展開しない。
      # 安全な zip は一時ディレクトリで展開し、1 階層下の theme.yml を見つける
      def test_should_refuse_unsafe_zips_and_install_safe_ones
        with_book do |root|
          {
            '../evil.css' => '展開先の外',
            '/etc/evil.css' => '展開先の外',
            'theme/../../evil.css' => '展開先の外',
            'C:/evil.css' => '展開先の外'
          }.each do |name, reason|
            zip = File.join(root, 'bad.zip')
            write_zip(zip, [['mono/theme.yml', "name: mono\ncontract: 1\n"], [name, 'x']])
            assert_includes Theme::ZipInspector.problems(zip), "#{name}（#{reason}を指すパス）"
            out, = capture_io { assert_equal 1, ThemeCommands.add(zip, root:) }
            assert_includes out, '展開しません'
          end
          link = File.join(root, 'link.zip')
          write_zip(link, [['mono/theme.yml', "name: mono\ncontract: 1\n"], ['mono/a.css', '/etc/passwd', true]])
          assert_equal ['mono/a.css（シンボリックリンク）'], Theme::ZipInspector.problems(link)
          refute File.exist?(File.join(root, 'themes', 'mono')), '検査に通らなければ何も入らない'

          safe = File.join(root, 'mono.zip')
          write_zip(safe, [['mono-main/theme.yml', "name: mono\ncontract: 1\nextends: standard\n"], ['mono-main/run.sh', 'echo']])
          out, = capture_io { assert_equal 0, ThemeCommands.add(safe, root:) }
          assert_equal %w[theme.yml], Theme::Install.files_in(File.join(root, 'themes', 'mono'))
          assert_includes out, 'run.sh'
        end
      end

      # git の URL と npm のパッケージ名は、まだ受けない（S7）。見つからない名前は同梱のテーマを示す
      def test_should_explain_sources_it_cannot_take_yet
        with_book do |root|
          out, = capture_io do
            assert_equal 1, ThemeCommands.add('https://github.com/example/theme.git', root:)
            assert_equal 1, ThemeCommands.add('@vivliostyle/theme-bunko', root:)
            assert_equal 1, ThemeCommands.add('bunko', root:)
          end

          assert_equal 2, out.scan('この版ではまだできません').size
          assert_includes out, 'テーマ bunko が見つかりません'
          assert_includes out, '同梱のテーマ: standard'
        end
      end

      # vs theme: 本のテーマと選ばれているもの。本に無い theme.name は、同梱なら theme:add を示す
      def test_should_list_the_themes_of_the_book
        with_book do |root|
          write_theme(root, 'mono', { 'extends' => 'standard', 'title' => '単色' })
          out, = capture_io do
            ThemeCommands.list(root:, config: Common.wrap_config({ theme: { name: 'mono' } }))
          end

          assert_match(/▶ mono  単色・土台: standard  ← config\/book.yml の theme.name/, out)
          assert_match(/^ {4}standard  標準（技術書）/, out)
        end
        with_book(themes: false) do |root|
          out, = capture_io { ThemeCommands.list(root:, config: Common.wrap_config({ theme: { name: 'standard' } })) }

          assert_includes out, '同梱のテーマなので、vs theme:add standard で本に入れられます'
          assert_includes out, '同梱のテーマ（vs theme:add <名前> で本に入れます）'
        end
      end

      private

      # stylesheets/ はリポジトリへの参照、themes/standard/ は写し、book.yml は color: green だけ
      def with_book(themes: true)
        Dir.mktmpdir('vs-theme-commands') do |tmp|
          root = File.realpath(tmp)
          File.symlink(File.join(REPO_ROOT, 'stylesheets'), File.join(root, 'stylesheets'))
          FileUtils.mkdir_p(File.join(root, 'config'))
          File.write(File.join(root, 'config', 'book.yml'), "theme:\n  name: standard\n  color: green\n")
          if themes
            FileUtils.mkdir_p(File.join(root, 'themes'))
            FileUtils.cp_r(File.join(REPO_ROOT, 'themes', 'standard'), File.join(root, 'themes'))
          end
          yield root
        end
      end

      def write_theme(root, name, manifest, files = {})
        write_theme_files(File.join(root, 'themes', name), { 'name' => name, 'contract' => 1 }.merge(manifest), files)
      end

      def write_theme_files(dir, manifest, files = {})
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'theme.yml'), manifest.to_yaml)
        files.each do |path, body|
          FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
          File.write(File.join(dir, path), body)
        end
      end

      # 無圧縮の zip を書く。項目は [名前, 中身, シンボリックリンクか]（Unix で作った形）
      def write_zip(path, entries)
        locals = +''
        centrals = +''
        entries.each do |name, data, symlink|
          crc = Zlib.crc32(data)
          offset = locals.bytesize
          locals << [0x04034b50, 20, 0, 0, 0, 0, crc, data.bytesize, data.bytesize, name.bytesize, 0].pack('VvvvvvVVVvv') << name << data
          mode = symlink ? 0o120777 : 0o100644
          centrals << [0x02014b50, (3 << 8) | 20, 20, 0, 0, 0, 0, crc, data.bytesize, data.bytesize, name.bytesize, 0, 0, 0, 0,
                       mode << 16, offset].pack('VvvvvvvVVVvvvvvVV') << name
        end
        tail = [0x06054b50, 0, 0, entries.size, entries.size, centrals.bytesize, locals.bytesize, 0].pack('VvvvvVVv')
        File.binwrite(path, locals + centrals + tail)
      end
    end
  end
end
