# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- 検索結果パネルの UI を `jksearch.picker` モジュールに分離し、
  init.lua はオーケストレーション専用に (574 行 → init 326 行 + picker 267 行)
- スクリプト実行の環境変数組み立て (`env_args` / NODE_PATH の遅延解決) を
  config モジュールに移動

## [Previous]

### Added

- `require("jksearch").word_under_cursor()`: カーソル下の検索語の抽出
  (辞書形化 + 複合名詞展開) を公開 API 化

### Fixed

- 意味全文の取得が失敗したとき、同じ URL の再取得ができないままになって
  いた問題 (失敗時にフラグを戻すようにした)
- `npm` が無い環境でプラグインの読み込み時にエラーになり得る問題
  (NODE_PATH の計算を初回使用時まで遅延させ、失敗時は設定しない)

### Added

- `jksearch.word` モジュール: カーソル下の語の特定・複合名詞の展開・
  表示幅の切り詰めを純粋関数として分離 (単体テスト可能に)
- config / history / word モジュールの busted テスト (Chrome・ネットワーク不要)

### Changed

- `truncate()` がグローバル `utf8` (lua-utf8) に依存しなくなった
  (`utf8.charpattern` で直接走査)

### Fixed

- 機関固有の OpenAthens URL を既定値に含まないよう変更。
  `redirector` / `proxy` は `vim.g.jksearch_configuration` (または
  `JK_REDIRECTOR` / `JK_PROXY` 環境変数) での設定が必須
- `vim.g.jksearch_configuration` が plugin 読み込み時に `config.setup()`
  に渡されていなかった問題
