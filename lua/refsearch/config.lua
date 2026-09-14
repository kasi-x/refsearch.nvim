--- refsearch.nvim 設定。

local M = {}

---@type RefSearch.Config
M.DATA = {
  -- 既定の検索ソース名 (lua/refsearch/sources/<name>.lua)
  default_source = "japanknowledge",
  -- 検索履歴キャッシュの保存先 (ソース名ごとに分けて保存される)
  history_file = vim.fn.expand("~/.local/share/refsearch/history.json"),
  -- ソースごとの設定
  sources = {
    japanknowledge = {
      -- 所属機関の OpenAthens リダイレクタ URL (必須)
      redirector = "",
      -- OpenAthens proxy のベース URL (必須)
      proxy = "",
      -- node 実行ファイル
      node = "node",
      -- 検索スクリプトのパス
      script = vim.fn.expand("~/.local/share/refsearch/bin/refsearch.js"),
      -- true でバックグラウンド Chrome をヘッドレス起動
      -- (初回ログイン時は false が分かりやすい)
      headless = false,
    },
  },
}

---設定を更新する。
---@param opts? table
function M.setup(opts)
  if opts then
    M.DATA = vim.tbl_deep_extend("force", M.DATA, opts)
  end
end

return M
