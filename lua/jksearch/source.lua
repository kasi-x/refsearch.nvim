---検索ソースのレジストリ (ref.vim の source のような仕組み)。
--
-- ソースは `lua/jksearch/sources/<name>.lua` として実装し、次のフィールドを
-- 持つテーブルを返す (自プラグインの runtimepath におけばサードパーティ製
-- ソースも解決できる):
--
--   name  : string                          ソース名 (省略時はモジュール名)
--   search: fun(query, on_result)          検索して結果を返す (必須)
--   fetch : fun(item, on_done)|nil          項目の全文を非同期取得 (任意)
--   open  : fun(item)|nil                   項目をブラウザで開く (任意)
--   init  : fun(opts)|nil                   セッション初期化 (任意)
--
-- on_result / on_done は非同期でもよく、コールバック内で完結させる。
-- search の結果は { status = "ok", results = {...}, exact = {...}, total = n }
-- か { status = "error", message = "..." }。

local config = require("jksearch.config")

local M = {}

---@type table<string, table>
local registry = {}

---ソースを登録する (テストや動的登録用。通常は sources/<name>.lua を置く)。
---@param spec table ソース実装 (name フィールド必須)
---@return table spec
function M.register(spec)
  registry[spec.name] = spec
  return spec
end

---ソース名からソースを取得する。組み込みソースは遅延読み込みされる。
---@param name string
---@return table|nil spec 見つからなければ nil
function M.get(name)
  if registry[name] then
    return registry[name]
  end
  local ok, mod = pcall(require, "jksearch.sources." .. name)
  if not ok then
    return nil
  end
  local spec = type(mod) == "table" and mod or {}
  spec.name = spec.name or name
  registry[name] = spec
  return spec
end

---設定 (default_source) で指定された既定のソースを取得する。
---@return table|nil spec
function M.default()
  return M.get(config.DATA.default_source or "japanknowledge")
end

return M
