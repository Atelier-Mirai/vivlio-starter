## Skills Usage
- OpenSkills CLI が `~/.claude/skills` にインストールされています。
- スキルが必要なときは `openskills read <skill-name>` を実行してSKILL.mdの指示を読み込んでください。
- 代表例: `openskills read docx`, `openskills read pdf`, `openskills read webapp-testing`.
- 新しいスキルを同期する場合は `openskills sync --output AGENTS.md` を呼び出してください。


<!-- ## Windsurf側での利用フロー
- Windsurfのチャット（Cascade）を開き、対象リポジトリ配下で作業します。CascadeはAGENTS.mdを読み込み、ガイドラインを常に参照します。
- スキルを呼びたい場面で「PDFスキルを使って…」などと指示すると、Cascadeはopenskills read pdfを実行してSKILL.mdの指示文を読み込み、そこに沿ったワークフローを続行します。
- スキル一覧を更新・共有したい場合は openskills sync を実行し、AGENTS.mdへ <available_skills> セクションを再生成しておくと、他メンバーや他エージェントでも同じセットを共有可能です。@https://raw.githubusercontent.com/numman-ali/openskills/main/README.md#20-120 -->