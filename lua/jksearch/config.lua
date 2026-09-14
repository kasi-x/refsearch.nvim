--- jk-search.nvim 設定。

local M = {}

---@type JKSearch.Config
M.DATA = {
  -- Chrome 実行ファイル
  chrome = "/usr/bin/google-chrome",
  -- 専用プロファイル (cookie を永続化してログイン状態を維持)
  profile = vim.fn.expand("~/.local/share/jk-search/profile"),
  -- node 実行ファイル
  node = "node",
  -- 検索スクリプトのパス
  script = vim.fn.expand("~/.local/share/jk-search/bin/jk-search.js"),
  -- 検索履歴 (JSON) の保存先
  history_file = vim.fn.expand("~/.local/share/jk-search/history.json"),
  -- true ならバックグラウンド Chrome をヘッドレスで起動する (ウィンドウ非表示)。
  -- false なら可視ウィンドウで起動する (初回ログイン時はこちらの方が分かりやすい)。
  headless = false,
  -- 所属機関の OpenAthens リダイレクタ URL (必須)。
  -- 例: "https://go.openathens.net/redirector/<your-domain>"
  redirector = "",
  -- OpenAthens proxy のベース URL (必須)。
  -- 例: "https://<resource>.proxy.openathens.net"
  proxy = "",
}

---設定を更新する。
---@param opts? table
function M.setup(opts)
  if opts then
    M.DATA = vim.tbl_deep_extend("force", M.DATA, opts)
  end
end

-- node のグローバルモジュールパス (NODE_PATH)。初回使用時に一度だけ計算する。
-- npm が無い環境でも require 時に落ちないよう、計算は遅延させる。
local node_path

---@return string 空文字列なら NODE_PATH を設定しない
local function node_path_value()
  if node_path == nil then
    local ok, out = pcall(vim.fn.system, "npm root -g")
    node_path = (ok and vim.v.shell_error == 0) and out:gsub("%s+$", "") or ""
  end
  return node_path
end

---スクリプト実行用の環境変数プレフィックス ({ "env", "NODE_PATH=...", ... })。
---redirector / proxy / headless 設定を環境変数に反映する。
---@return string[]
function M.env_args()
  local args = { "env" }
  local np = node_path_value()
  if np ~= "" then
    args[#args + 1] = "NODE_PATH=" .. np
  end
  if M.DATA.redirector and M.DATA.redirector ~= "" then
    args[#args + 1] = "JK_REDIRECTOR=" .. M.DATA.redirector
  end
  if M.DATA.proxy and M.DATA.proxy ~= "" then
    args[#args + 1] = "JK_PROXY=" .. M.DATA.proxy
  end
  if M.DATA.headless then
    args[#args + 1] = "JK_HEADLESS=1"
  end
  return args
end

return M
