# refsearch.nvim

[![Test](https://github.com/kasi-x/refsearch.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/kasi-x/refsearch.nvim/actions/workflows/test.yml)
[![Luacheck](https://github.com/kasi-x/refsearch.nvim/actions/workflows/luacheck.yml/badge.svg)](https://github.com/kasi-x/refsearch.nvim/actions/workflows/luacheck.yml)
[![StyLua](https://github.com/kasi-x/refsearch.nvim/actions/workflows/stylua.yml/badge.svg)](https://github.com/kasi-x/refsearch.nvim/actions/workflows/stylua.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

カーソル下の語で [ジャパンナレッジLib](https://japanknowledge.com/lib/) を検索する
Neovim プラグイン。詳細は Vim help (`:h refsearch`) も参照してください。

> Search Japan Knowledge Lib from Neovim with lemma normalization via
> [bunsetsu.nvim](https://github.com/kasi-x/bunsetsu.nvim) (OpenAthens; docs in Japanese).

[bunsetsu.nvim](https://github.com/kasi-x/bunsetsu.nvim)
(Vibrato + UniDic) で辞書形に正規化した語で検索します
(例: 「走っ」→「走る」)。検索は専用プロファイルのバックグラウンド Chrome
(Puppeteer) で実行するため、メインのブラウザには一切触れません。

**アーキテクチャ (ref.vim 風)**: このプラグインは検索ソースのフレームワーク
(ピッカー・クエリ抽出・履歴) であり、検索先は**ソース**として追加します。
ジャパンナレッジLib は同梱のオプショナルソース
(`lua/refsearch/sources/japanknowledge.lua`) で、使わなければ読み込まれません。
自前のソースを `lua/refsearch/sources/<name>.lua` に置けば追加できます。

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
    "kasi-x/refsearch.nvim",
    dependencies = { "kasi-x/bunsetsu.nvim" },
}
```

puppeteer-core をグローバルにインストールしていない場合は、プラグインの
ディレクトリでローカルインストールできます (node が自動で解決します):

```sh
cd ~/.local/share/nvim/lazy/refsearch.nvim
npm install
```

## 設定

`vim.g.refsearch_configuration` にテーブルで渡します。
`redirector` と `proxy` は所属機関固有のため**必須**です
(図書館のデータベース案内ページ等でご確認ください)。

```lua
vim.g.refsearch_configuration = {
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

### 機関設定をプラグインとして分離する (推奨パターン)

`redirector` / `proxy` は機関固有のため、公開リポジトリに含めたくない場合。
薄い設定プラグインを作り、そこにだけ機関情報を置くことができます:

```
~/dev/jk_ac.nvim/          ← private (機関情報を含む)
  lua/jk_ac/init.lua
  plugin/jk_ac.lua
```

```lua
-- lua/jk_ac/init.lua (private)
local M = {}

M.institution = {
  redirector = "https://go.openathens.net/redirector/<your-domain>",
  proxy = "https://<resource>.proxy.openathens.net",
}

return M
```

```lua
-- plugin/jk_ac.lua (private)
require("refsearch.config").setup(require("jk_ac").institution)

vim.keymap.set("n", "B", function()
  require("refsearch").search_cursor()
end, { desc = "jk-ac: カーソル下の語をジャパンナレッジで検索" })
```

lazy.nvim では dependencies に refsearch.nvim を指定します (dependency が
先に読み込まれるため、設定はコマンド実行時に確実に反映されます):

```lua
{
    "/home/user/dev/jk_ac.nvim",
    dependencies = { "kasi-x/refsearch.nvim" },
}
```

通常は上記だけで十分です。その他の設定項目 (すべて省略可):

| 項目 | 省略値 | 説明 |
| --- | --- | --- |
| `script` | `~/.local/share/refsearch/bin/refsearch.js` | 検索スクリプトのパス |
| `profile` | `~/.local/share/refsearch/profile` | Chrome 専用プロファイル (ログイン状態の保持用) |
| `history_file` | `~/.local/share/refsearch/history.json` | 検索履歴キャッシュの保存先 |

## 使い方

```vim
:RefSearch 実験        " 指定語を検索
:RefSearch             " カーソル下の語を検索 (bunsetsu.nvim で辞書形化)
:RefSearchInit         " バックグラウンド Chrome を起動してセッション確立
:RefSearchInit!        " 可視ウィンドウで Chrome を起動 (手動ログイン用)
```

Lua API:

```lua
-- カーソル下の検索語を取得 (辞書形化 + 複合名詞展開)
local word = require("refsearch").word_under_cursor()
```

お好みでキーマップに登録できます:

```lua
vim.keymap.set("n", "B", function() require("refsearch").search_cursor() end,
    { desc = "refsearch: カーソル下の語を検索" })
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
- 未ログイン → ログインを案内 (`:RefSearchInit!` で可視 Chrome を開いて手動ログイン)
- 同時接続数オーバー → その旨を通知
- 検索結果と意味全文はローカル (`~/.local/share/refsearch/history.json`)
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

## ソースを追加する

`lua/refsearch/sources/<name>.lua` に次のフィールドを持つテーブルを返す
モジュールを置くと (自プラグインの runtimepath でも可)、`default_source`
やソース切り替えから使えます:

```lua
local M = { name = "<name>" }

function M.search(query, on_result)
  -- 非同期で検索し、結果を on_result に渡す
  on_result({
    status = "ok",
    total = 3,
    results = {
      { title = "見出し", dict = "辞書名", snippet = "概要", url = "https://..." },
    },
    exact = {}, -- 見出しが検索語と完全一致した項目
  })
end

function M.fetch(item, on_done)
  on_done("項目の意味全文") -- 任意
end

function M.open(item) -- 任意
  vim.fn.jobstart({ "xdg-open", item.url }, { detach = true })
end

return M
```

## ライセンス

MIT。
