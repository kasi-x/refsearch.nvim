-- jk-search 検索履歴の保存・読み込み (ソースごとに分けて保存)。
--
-- 保存ファイルの構造:
--   {
--     "japanknowledge": {
--       "実験": {
--         "query": "実験",
--         "searched_at": "2026-09-13T12:00:00",
--         "results": [ { "title", "dict", "snippet", "url", "exact", "text" } ]
--       }
--     }
--   }
--
-- 互換性: 旧版 (ソース名なしのフラット構造) のエントリは japanknowledge
-- の検索として読み替える。

local config = require("jksearch.config")

local M = {}

---履歴ファイルのパス。
---@return string
function M.file()
  return config.DATA.history_file or vim.fn.expand("~/.local/share/jk-search/history.json")
end

---履歴全体を読み込む。無ければ空テーブル。
---@return table<string, any>
function M.load()
  local path = M.file()
  if not vim.fn.filereadable(path) then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return {}
  end
  local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if ok2 and type(data) == "table" then
    return data
  end
  return {}
end

---履歴全体を書き込む (保存先ディレクトリを作成する)。
---@param data table
function M.save(data)
  local path = M.file()
  local ok_dir = pcall(vim.fn.mkdir, vim.fn.fnamemodify(path, ":h"), "p")
  if not ok_dir then
    return
  end
  local ok, json = pcall(vim.json.encode, data)
  if ok then
    vim.fn.writefile(vim.split(json, "\n", { plain = true }), path)
  end
end

---指定ソース・クエリの保存済み結果を返す。無ければ nil。
---旧版 (ソース名なし) のエントリは japanknowledge の検索として読む。
---@param source string
---@param query string
---@return table|nil
function M.get(source, query)
  local data = M.load()
  local by_source = data[source]
  if by_source and by_source[query] then
    return by_source[query]
  end
  if source == "japanknowledge" then
    return data[query] -- 旧版フラット構造の互換読み
  end
  return nil
end

---検索結果を保存する (新しいクエリのみ、既存は上書きしない)。
---exact フラグは results の各項目に付けて渡す。
---@param source string
---@param query string
---@param results table[] 検索結果一覧
function M.store_search(source, query, results)
  if not query or query == "" then
    return
  end
  local data = M.load()
  local by_source = data[source] or {}
  if by_source[query] then
    return -- 既に保存済みなら上書きしない
  end
  by_source[query] = {
    query = query,
    searched_at = os.date("%Y-%m-%dT%H:%M:%S"),
    results = results,
  }
  data[source] = by_source
  M.save(data)
end

---意味全文を保存する (対応するクエリの結果項目に text を追記)。
---@param source string
---@param query string
---@param url string
---@param text string
function M.store_text(source, query, url, text)
  if not query or query == "" then
    return
  end
  local data = M.load()
  local entry = data[source] and data[source][query]
  if entry and entry.results then
    for _, r in ipairs(entry.results) do
      if r.url == url then
        r.text = text
        break
      end
    end
    M.save(data)
  end
end

---保存済みの意味全文を取得する。無ければ nil。
---@param source string
---@param query string
---@param url string
---@return string|nil
function M.get_text(source, query, url)
  local data = M.load()
  local entry = data[source] and data[source][query]
  if not entry or not entry.results then
    return nil
  end
  for _, r in ipairs(entry.results) do
    if r.url == url and r.text then
      return r.text
    end
  end
  return nil
end

return M
