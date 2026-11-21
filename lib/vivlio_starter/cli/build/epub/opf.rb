# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub/opf.rb
# ================================================================
# 責務:
#   組み上がった EPUB の content.opf と nav の書き換え（id・識別子）
# ================================================================

require 'digest'
require 'tmpdir'
require_relative 'workspace'

module VivlioStarter
  module CLI
    module Build
      # 組み上がった EPUB の content.opf と nav の書き換え（id・識別子）
      module Epub::Opf
        module_function

        # 展開先の tmpdir を基準に、指定したメンバーだけを EPUB へ差し替える。
        #
        # `Dir.chdir` は**プロセス全体**の cwd を動かすため使わない。EPUB 枝と PDF 枝を
        # 並列に走らせると、PDF 枝が起こす `npx vivliostyle` が一時ディレクトリを cwd と
        # して継いでしまい、ビルドが不定に壊れる（build-target-parallelization-spec.md §3）。
        # 子プロセスの cwd だけを変える spawn の `chdir:` なら親は動かない。
        def zip_into(archive, members, from:)
          system('zip', '-q', archive, *members, chdir: from, out: File::NULL, err: File::NULL)
        end

        # ================================================================
        # content.opf zip 手術（unzip → 書き換え → zip 差し替え）
        # ================================================================
        # 生成済み EPUB の content.opf を後段で修正する 2 種の手術。P2 で pipeline から移設。

        # EPUB の dc:identifier を書籍固有の決定的な UUID に置換する。
        # プロジェクト名（config.project.name）が同一である限り、バージョンが変わっても
        # UUID が変化しないため、電子書籍ストアでの差し替えが容易になる。
        def stabilize_epub_identifier!(epub_path)
          stable_id = stable_project_uuid
          return unless stable_id

          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-id') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            content = File.read(opf_path, encoding: 'UTF-8')
            replaced = content.sub(
              %r{(<dc:identifier\s+id="bookid">)urn:uuid:[0-9a-f-]+(</dc:identifier>)},
              "\\1#{stable_id}\\2"
            )

            if replaced == content
              Common.log_info('[EPUB] identifier は既に安定化済みです')
              return
            end

            File.write(opf_path, replaced)

            zip_into(abs_epub, ['EPUB/content.opf'], from: tmpdir)

            Common.log_info("[EPUB] identifier を安定化しました: #{stable_id}")
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] identifier 安定化に失敗: #{e.message}")
        end

        # content.opf の数字始まり id / idref に接頭辞を付与して NCName 違反を解消する。
        # vivliostyle CLI はファイル名（例: 00-preface）から manifest item の id を
        # 機械生成するため、数字始まりの id が XML の NCName 規則（先頭は英字または _）に
        # 違反し epubcheck の RSC-005 ERROR になる。spine の idref も同値を参照するため、
        # id と idref を同一規則（固定接頭辞 id-）で書き換えて整合を保つ。
        # stabilize_epub_identifier! と同型の unzip → 修正 → zip 差し替え方式。
        def sanitize_epub_opf_ids!(epub_path)
          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-opf') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            content = File.read(opf_path, encoding: 'UTF-8')
            replaced = content.gsub(/\b(id|idref)="(\d[^"]*)"/) do
              %(#{::Regexp.last_match(1)}="id-#{::Regexp.last_match(2)}")
            end

            return if replaced == content

            File.write(opf_path, replaced)

            zip_into(abs_epub, ['EPUB/content.opf'], from: tmpdir)

            Common.log_info('[EPUB] content.opf の数字始まり id を NCName 準拠に修正しました')
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] content.opf id 修正に失敗: #{e.message}")
        end

        # 目次の文書（nav）にある、自分自身を指すリンクへ飛び先の印を付ける（Kindle 専用）。
        #
        # EPUB 3 は目次の文書を必ず 1 つ持ち、Vivliostyle はそれを最初の文書（前書き）の中に
        # hidden で入れる。目次の最初の項目はその文書自身を指す `href="00-preface.xhtml"` になり、
        # Kindle の変換は自分自身を指すファイル名だけのリンクを解決できず、W14001・W14002 の注意を
        # 出す（ほかの文書を指すファイル名だけのリンクは解決できる）。章の参照と同じ
        # `#ch-<スラッグ>` の印を付ければ解決できる。クリーン EPUB の読書アプリは困らないので触らない。
        def anchor_nav_self_link!(epub_path)
          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-nav') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir, out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            nav_href = File.read(opf_path, encoding: 'UTF-8')[/<item\b[^>]*\bhref="([^"]+)"[^>]*\bproperties="[^"]*\bnav\b/, 1]
            return unless nav_href

            member = "EPUB/#{nav_href}"
            system('unzip', '-o', abs_epub, member, '-d', tmpdir, out: File::NULL, err: File::NULL)
            nav_path = File.join(tmpdir, member)
            return unless File.exist?(nav_path)

            xhtml = File.read(nav_path, encoding: 'UTF-8')
            anchor = xhtml[/<span id="(ch-[^"]+)" class="vs-sec-anchor"/, 1]
            return unless anchor

            self_link = %(href="#{File.basename(nav_href)}")
            replaced = xhtml.sub(%r{<nav\b[^>]*epub:type="toc".*?</nav>}m) do
              it.gsub(self_link, %(href="#{File.basename(nav_href)}##{anchor}"))
            end
            return if replaced == xhtml

            File.write(nav_path, replaced)
            zip_into(abs_epub, [member], from: tmpdir)
            Common.log_info("[EPUB] 目次の文書の自分自身へのリンクに ##{anchor} を付けました")
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] 目次の文書のリンクの修正に失敗: #{e.message}")
        end

        # Kindle 用の EPUB の metadata に、本の組方向の meta を足す（縦書きの本だけ）。
        # Kindle は spine の page-progression-direction だけでは縦書きの本と扱わず、この meta を読む
        # （v2-feasibility-notes.md §3.2・novel-vertical-spec.md §2.4）。クリーン EPUB には書かない
        # （EPUB 3 の meta の name は OPF 2 の書き方で、組方向は CSS と spine が決める）
        PRIMARY_WRITING_MODE = '<meta name="primary-writing-mode" content="vertical-rl"/>'

        def mark_primary_writing_mode!(epub_path)
          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-wm') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir, out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            content = File.read(opf_path, encoding: 'UTF-8')
            return if content.include?('name="primary-writing-mode"')

            replaced = content.sub(%r{(\s*)</metadata>}) { "#{::Regexp.last_match(1)}  #{PRIMARY_WRITING_MODE}#{::Regexp.last_match(0)}" }
            return if replaced == content

            File.write(opf_path, replaced)
            zip_into(abs_epub, ['EPUB/content.opf'], from: tmpdir)
            Common.log_info('[EPUB] Kindle 用の EPUB に縦書きの meta（primary-writing-mode）を足しました')
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] 縦書きの meta の追加に失敗: #{e.message}")
        end

        # プロジェクト名から決定的に算出した UUID を urn:uuid: に載せて返す。
        # プロジェクト名が未設定の場合は book.main_title を fallback とし、
        # それでも空なら nil を返す。
        def stable_project_uuid
          book = Common::CONFIG.book

          # 著者が独自 ISBN を取得している場合は urn:isbn を dc:identifier に使う
          # （EPUB の標準作法。未設定ならプロジェクト名由来の安定 UUID を使用）
          isbn = book.isbn.to_s.delete('- ').strip
          return "urn:isbn:#{isbn}" unless isbn.empty?

          # 分冊の巻は巻ごとに違う識別子にする。同じだと、ストアや読書アプリが上巻と下巻を
          # 同じ本の版違いとして扱う（multivolume-spec.md §4.7）。区切りは出力ファイル名と同じ `_`
          # （巻ごとに project.name を変えていた回り道 `mybook_upper` と同じ識別子になる）
          project = Common::CONFIG.project
          raw     = project&.name.to_s.strip
          raw     = "#{raw}_#{Build::Volumes.current.id}" if !raw.empty? && Build::Volumes.current
          fallback = [book&.main_title, book&.subtitle].compact.join(' ').strip
          base = raw.empty? ? fallback : raw
          base = base.to_s.strip
          return if base.empty?

          normalized = base.downcase
          hex = Digest::SHA1.hexdigest(normalized)
          uuid = [
            hex[0, 8],
            hex[8, 4],
            hex[12, 4],
            hex[16, 4],
            hex[20, 12]
          ].join('-')
          "urn:uuid:#{uuid}"
        end
      end
    end
  end
end
