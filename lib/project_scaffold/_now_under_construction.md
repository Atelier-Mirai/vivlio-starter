# このディレクトリは開発中です。

- 将来的には、プロジェクトルート配下の各種資産（contents / stylesheets / codes / chapter_templates / images など）を lib/project_template に複製し、lib 以下を gem 化する予定である。

- 現在は開発途中なので、「プロジェクトルート直下にある資産こそが project_template にあるものだ」という前提で実装を進める。

- したがって、book.yml で指定されたテーマについても、プロジェクトルート直下の stylesheets/ を参照して実現する。