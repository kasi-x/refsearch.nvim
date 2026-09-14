---refsearch.nvim: 検索ソースフレームワークの公開 API。
--
-- 検索そのものは `lua/refsearch/sources/<name>.lua` (例: japanknowledge) が
-- 担当し、このモジュールはクエリ抽出・ソースへのディスパッチ・履歴・
-- ピッカー表示のオーケストレーションを担当する。

local config = require("refsearch.config")
local history = require("refsearch.history")
local picker = require("refsearch.picker")
local source_mod = require("refsearch.source")
local word = require("refsearch.word")

local M = {}

---カーソル位置を含む、連続する名詞の複合語 (名詞+名詞...) を返す。
---複合語でなければ nil。
---@return string|nil
local function compound_noun_under_cursor()
  local line = vim.fn.getline(".")
  if line == "" then
    return nil
  end
  local cursor = vim.fn.col(".")

  local ok, vibrato = pcall(require, "bunsetsu._commands.vibrato")
  if not ok then
    return nil
  end
  local words, infos = vibrato.tokenize_detailed(line)
  if #words == 0 then
    return nil
  end

  local positions = word.token_positions(line, words)
  return word.compound_noun(words, positions, infos, cursor)
end

---カーソル下の語を辞書形化して返す。
---名詞+名詞の複合語は分割せず、連続する名詞全体 (一語) を検索語にする。
---公開 API: 検索語の抽出だけを他の用途から使うこともできる。
---@return string|nil 検索語
function M.word_under_cursor()
  local ok, bunsetsu = pcall(require, "bunsetsu")
  if not ok then
    vim.notify("refsearch: bunsetsu.nvim が見つかりません", vim.log.levels.ERROR)
    return nil
  end
  local r = bunsetsu.lemma_under_cursor()
  if not r then
    vim.notify("refsearch: カーソル下の語を特定できません", vim.log.levels.INFO)
    return nil
  end
  -- 名詞なら複合名詞 (名詞+名詞) を一語で検索する。
  -- 例: 「形態素解析」は 形態素/解析 に分割されるが「形態素解析」で検索する。
  if r.pos and r.pos:match("名詞") then
    local compound = compound_noun_under_cursor()
    if compound then
      return compound
    end
  end
  -- 辞書形が無ければ表面形を使う
  return r.lemma ~= "" and r.lemma or r.surface
end

---検索を実行する (既定ソース)。
---結果は履歴に保存され、ピッカーで表示される。
---@param query string 検索語
function M.search(query)
  local source = source_mod.default()
  if not source or not source.search then
    vim.notify(
      "refsearch: 検索ソースが見つかりません ("
        .. tostring(config.DATA.default_source)
        .. ")",
      vim.log.levels.ERROR
    )
    return
  end
  if not query or query == "" then
    return
  end

  vim.notify(("検索中: %s"):format(query), vim.log.levels.INFO)
  source.search(query, function(data)
    if data.status ~= "ok" then
      vim.notify(data.message or "検索に失敗しました", vim.log.levels.ERROR)
      return
    end

    local exact = data.exact or {}
    if #exact > 0 then
      vim.notify(
        ("完全一致 %d 件 (%s 件中)"):format(#exact, tostring(data.total or "?")),
        vim.log.levels.INFO
      )
    else
      vim.notify(
        ("完全一致なし (%s 件中)"):format(tostring(data.total or "?")),
        vim.log.levels.INFO
      )
    end

    -- 完全一致フラグを付けて履歴に保存 (同じ語の再検索時に再利用)
    local exact_urls = {}
    for _, e in ipairs(exact) do
      exact_urls[e.url] = true
    end
    local results_for_history = {}
    for _, r in ipairs(data.results or {}) do
      results_for_history[#results_for_history + 1] = vim.tbl_extend("force", r, {
        exact = exact_urls[r.url] == true,
      })
    end
    history.store_search(source.name, query, results_for_history)

    picker.show({
      query = query,
      source = source.name,
      results = data.results or {},
      exact = exact,
    }, source)
  end)
end

---コマンド実装: :RefSearch [語]
---語を省略した場合はカーソル下の語を使う。
---@param args string[]
function M.command(args)
  local query = #args > 0 and table.concat(args, " ") or nil
  if not query or query == "" then
    query = M.word_under_cursor()
  end
  if not query or query == "" then
    return
  end
  M.search(query)
end

---カーソル下の語を検索 (キーマップ用)。
function M.search_cursor()
  local query = M.word_under_cursor()
  if query then
    M.search(query)
  end
end

---既定ソースのセッションを初期化する (:RefSearchInit)。
---@param opts? { visible?: boolean }
function M.init_session(opts)
  local source = source_mod.default()
  if source and source.init_session then
    source.init_session(opts)
  else
    vim.notify(
      "refsearch: 既定ソースにセッション初期化がありません",
      vim.log.levels.WARN
    )
  end
end

---互換用エイリアス (:RefSearchInit から呼ばれる)。
M.init = M.init_session

return M
