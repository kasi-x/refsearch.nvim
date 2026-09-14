# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (breaking)

- **検索ソースアーキテクチャ (ref.vim 風)**: 検索先を「ソース」として
  追加できるように内部を再構築。ジャパンナレッジLib は同梱の
  オプショナルソース (`lua/jksearch/sources/japanknowledge.lua`) となり、
  未使用時は読み込まれない。自前のソースは
  `lua/jksearch/sources/<name>.lua` として追加できる
- 設定を `sources.<name>` のネスト構造に変更:
  `sources.japanknowledge.redirector / proxy / node / script / headless`
- 履歴をソース名ごとに分けて保存 (旧フラット構造は japanknowledge の
  履歴として互換読み込み)
- 検索結果パネルの UI を `jksearch.picker` モジュールに分離し、
  init.lua はオーケストレーション専用に (574 行 → init 326 行 + picker 267 行)
- スクリプト実行の環境変数組み立て (`env_args` / NODE_PATH の遅延解決) を
  config モジュールに移動

### Added

- `require("jksearch").word_under_cursor()`: カーソル下の検索語の抽出
  (辞書形化 + 複合名詞展開) を公開 API 化
- ソース追加のためのドキュメント (`:h jksearch-add-source`)

### Fixed

- 意味全文の取得が失敗したとき、同じ URL の再取得ができないままになって
  いた問題 (失敗時にフラグを戻すようにした)
- `npm` が無い環境でプラグインの読み込み時にエラーになり得る問題
  (NODE_PATH の計算を初回使用時まで遅延させ、失敗時は設定しない)

### Added (1.0)

- `jksearch.word` モジュール: カーソル下の語の特定・複合名詞の展開・
  表示幅の切り詰めを純粋関数として分離 (単体テスト可能に)
- config / history / word モジュールの busted テスト (Chrome・ネットワーク不要)
- `truncate()` がグローバル `utf8` (lua-utf8) に依存しなくなった
  (`utf8.charpattern` で直接走査)
- 機関固有の OpenAthens URL を既定値に含まないよう変更。
  `redirector` / `proxy` は `vim.g.jksearch_configuration` での設定が必須
- `vim.g.jksearch_configuration` が plugin 読み込み時に `config.setup()`
  に渡されていなかった問題
