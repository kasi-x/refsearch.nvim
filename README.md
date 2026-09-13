# jk-search.nvim

[![Test](https://github.com/kasi-x/jk-search.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/kasi-x/jk-search.nvim/actions/workflows/test.yml)
[![Luacheck](https://github.com/kasi-x/jk-search.nvim/actions/workflows/luacheck.yml/badge.svg)](https://github.com/kasi-x/jk-search.nvim/actions/workflows/luacheck.yml)
[![StyLua](https://github.com/kasi-x/jk-search.nvim/actions/workflows/stylua.yml/badge.svg)](https://github.com/kasi-x/jk-search.nvim/actions/workflows/stylua.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

カーソル下の語で [ジャパンナレッジLib](https://japanknowledge.com/lib/) を検索する
Neovim プラグイン。詳細は Vim help (`:h jksearch`) も参照してください。

> Search Japan Knowledge Lib from Neovim with lemma normalization via
> [bunsetsu.nvim](https://github.com/kasi-x/bunsetsu.nvim) (OpenAthens; docs in Japanese).

日本語の語は [bunsetsu.nvim](https://github.com/kasi-x/bunsetsu.nvim)
(Vibrato + UniDic) で辞書形に正規化してから検索します
(例: 「走っ」→「走る」)。検索は専用プロファイルのバックグラウンド Chrome
(Puppeteer) で実行するため、メインのブラウザには一切触れません。

所属機関の OpenAthens 経由でのアクセスを前提としています
(大学等でジャパンナレッジLib を契約している方向け)。

## 前提

- [bunsetsu.nvim](https://github.com/kasi-x/bunsetsu.nvim)
  (Vibrato バックエンド設定推奨。未設定でも同梱 TinySegmenter の表層形で検索可能)
- Node.js 18 以上
- puppeteer-core (グローバル or 後述のローカルインストール)
- Google Chrome
- 所属機関の OpenAthens アカウント (ジャパンナレッジLib の契約)

## 注意 (必ずお読みください)

ジャパンナレッジLib は有料の契約データベースです。このプラグインは
**契約している機関のアカウントでのみ**使用してください。所属機関や
ジャパンナレッジの利用規約が自動アクセスを禁止している場合は使用しないでください。

過度な連続検索は行わない設計にしています (ローカル履歴キャッシュ、
同時接続数オーバー検知) が、規約の順守は利用者の責任で行ってください。

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "kasi-x/jk-search.nvim",
    dependencies = { "kasi-x/bunsetsu.nvim" },
}
```

puppeteer-core をグローバルにインストールしていない場合は、プラグインの
ディレクトリでローカルインストールできます (node が自動で解決します):

```sh
cd ~/.local/share/nvim/lazy/jk-search.nvim
npm install
```

## 設定

`vim.g.jksearch_configuration` にテーブルで渡します。
`redirector` と `proxy` は所属機関固有のため**必須**です
(図書館のデータベース案内ページ等でご確認ください)。

```lua
vim.g.jksearch_configuration = {
    -- 所属機関の OpenAthens リダイレクタ URL (必須)
    redirector = "https://go.openathens.net/redirector/<your-domain>",
    -- OpenAthens proxy のベース URL (必須)
    proxy = "https://<resource>.proxy.openathens.net",
    -- Google Chrome のパス
    chrome = "/usr/bin/google-chrome",
    -- node 実行ファイル
    node = "node",
    -- true でバックグラウンド Chrome をヘッドレス起動
    -- (初回ログイン時は false が分かりやすい)
    headless = false,
}
```

通常は上記だけで十分です。その他の設定項目 (すべて省略可):

| 項目 | 省略値 | 説明 |
| --- | --- | --- |
| `script` | `~/.local/share/jk-search/bin/jk-search.js` | 検索スクリプトのパス |
| `profile` | `~/.local/share/jk-search/profile` | Chrome 専用プロファイル (ログイン状態の保持用) |
| `history_file` | `~/.local/share/jk-search/history.json` | 検索履歴キャッシュの保存先 |

## 使い方

```vim
:JKSearch 実験        " 指定語を検索
:JKSearch             " カーソル下の語を検索 (bunsetsu.nvim で辞書形化)
:JKSearchInit         " バックグラウンド Chrome を起動してセッション確立
:JKSearchInit!        " 可視ウィンドウで Chrome を起動 (手動ログイン用)
```

Lua API:

```lua
-- カーソル下の検索語を取得 (辞書形化 + 複合名詞展開)
local word = require("jksearch").word_under_cursor()
```

お好みでキーマップに登録できます:

```lua
vim.keymap.set("n", "B", function() require("jksearch").search_cursor() end,
    { desc = "jk-search: カーソル下の語を検索" })
```

検索結果は画面下部のパネルで表示されます:

```
+--------+-----------------------------+
| 索引    | 選択中項目の意味 (全文)       |
+--------+-----------------------------+
```

パネル (索引ウィンドウ) のキー:

| キー | 動作 |
| --- | --- |
| `n` / `e` | 次 / 前の項目 |
| `<CR>` | カーソル行の項目をブラウザ (常駐 Chrome のタブ) で開く |
| `q` | 閉じる |

### 挙動

- 完全一致の項目がある → 先頭に集めて表示。`<CR>` でタブオープン
- 完全一致が無い → 検索結果の見出し一覧から選択
- カーソル下の語が名詞のとき、連続する名詞を一語にまとめて検索する
  (例: 「形態素解析」は 形態素/解析 に分割されず「形態素解析」で検索)
- 未ログイン → ログインを案内 (`:JKSearchInit!` で可視 Chrome を開いて手動ログイン)
- 同時接続数オーバー → その旨を通知
- 検索結果と意味全文はローカル (`~/.local/share/jk-search/history.json`)
  にキャッシュされ、同じ語の再検索はネットワークアクセスなしで表示される

## 開発

テスト・lint:

```sh
eval $(luarocks path --lua-version 5.1 --bin)
busted .
make luacheck
make check-stylua
```

テストはネットワーク・Chrome を使わない (config / history / word モジュール)。

## ライセンス

MIT。
