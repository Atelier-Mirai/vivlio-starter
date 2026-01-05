# 索引の生成と、index_matches.yml と index_terms.yml、index_candidates.yml の整理について


1. 著者が本文中に [用語|読み] で手動マークアップ
    => これは必ず索引に掲載される。
2. index_terms.yml に登録した用語
    => 索引の「読み」として採用される。索引に掲載する為には、本文への [用語|読み] でマークアップする必要があります。
3. index_candidates.yml で自動抽出した候補
    => index_terms.yml へコピーすることにより、索引の「読み」として採用される。索引に掲載する為には、本文への [用語|読み] でマークアップする必要があります。

0. _index_matches.yml に掲載されている単語 
    => これが索引になる。


