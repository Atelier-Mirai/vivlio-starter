## generate_frontispiece_and_ornament_fromメソッドについて（pre_process.rb内に実装完了）
pre_process.rb内に、「指定された一つの画像ファイル」からfrontispiece/ornament生成処理を行なうとして、generate_frontispiece_and_ornament_fromメソッドは次の仕様である。

仕様:
# 利用者の準備している画像から生成する場合
  generate_frontispiece_and_ornament_from("filename.png/jpg/webp")
  filename_portrait.webp, filename_landscape.webpを生成する
# 事前に準備されている画像から生成する場合
  generate_frontispiece_and_ornament_from("bundled/filename.webp")
  bundled/filename_portrait.webp, bundled/filename_landscape.webpを生成する

（既存のdecorative_frame_generator.rbやdiagonal_split_transform.rb、trim_image_borders.rbを参考にしてください。
 なお、decorative_frame_generator.rbやdiagonal_split_transform.rb、trim_image_borders.rbは削除予定なので、必要なコードがあれば、pre_process.rb内で完結するようにしてください）
