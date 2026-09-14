---検索結果パネル (索引 + 意味ウィンドウ) の UI。
--
-- ソース非依存: 意味全文の取得 (fetch) とブラウザで開く (open) は、
-- 表示中のソース (source.fetch / source.open) に委譲する。
--
-- 使い方: picker.show(data, source)
--   data   : source.search の結果 (results / exact / query / source)
--   source : 検索に使ったソース (fetch / open / name を使用)

local history = require("jksearch.history")
local word = require("jksearch.word")

local M = {}

---検索結果を画面下部のパネルで表示する (元のバッファはそのまま残す)。
---レイアウト (最下部 5 行パネル):
---   左 (幅 20): 索引インデックス (一致項目は辞書名、不一致は見出し)
---   右:        選択中項目の意味 (全文を非同期取得して表示)
---バッファローカル keymap (索引ウィンドウ):
---   n/e  次/前の項目
---   <CR> カーソル行の項目をブラウザで開く
---   q    閉じる
---@param data table source.search の結果
---@param source table 検索に使ったソース (fetch / open / name)
function M.show(data, source)
  source = source
    or {
      name = data.source or "",
      fetch = function(_, cb)
        cb(nil)
      end,
    }
  local hits = data.results or {}
  if #hits == 0 then
    vim.notify(("検索結果 0 件 (%s)"):format(source.name), vim.log.levels.INFO)
    return
  end

  local query = data.query

  -- 完全一致項目は先頭に集めてマーカーを付ける。
  -- data.exact (ネットワーク検索時) か、results 内の exact フラグ
  -- (ローカル履歴読み込み時) のどちらかを使う。
  local exact = {}
  local rest = {}
  local exact_set = {}
  for _, e in ipairs(data.exact or {}) do
    exact_set[e.url] = true
  end
  for _, h in ipairs(hits) do
    local is_exact = exact_set[h.url] or h.exact == true
    if is_exact then
      exact[#exact + 1] = h
    else
      rest[#rest + 1] = h
    end
  end
  local items = {}
  for _, h in ipairs(exact) do
    items[#items + 1] =
      { title = h.title, dict = h.dict, snippet = h.snippet, url = h.url, exact = true }
  end
  for _, h in ipairs(rest) do
    items[#items + 1] =
      { title = h.title, dict = h.dict, snippet = h.snippet, url = h.url, exact = false }
  end

  -- 意味全文のキャッシュ (url -> text)。
  local text_cache = {}
  local fetching = {}

  -- 履歴に保存済みの意味全文を読み込む
  do
    local entry = history.get(source.name, query)
    if entry and entry.results then
      for _, r in ipairs(entry.results) do
        if r.text then
          text_cache[r.url] = r.text
        end
      end
    end
  end

  -- URL の意味全文を非同期で取得してキャッシュする。
  -- 取得完了時に on_done(text) を呼ぶ (キャッシュ済みなら即時呼ぶ)。
  local function fetch_text(item, on_done)
    local url = item.url
    if not url then
      return
    end
    if text_cache[url] then
      if on_done then
        on_done(text_cache[url])
      end
      return
    end
    if fetching[url] then
      return
    end
    fetching[url] = true
    -- 意味全文の取得はソース (source.fetch) に委譲する
    source.fetch(item, function(text)
      fetching[url] = nil
      if text then
        text_cache[url] = text
        history.store_text(source.name, query, url, text)
        if on_done then
          on_done(text)
        end
      end
    end)
  end

  -- 表示幅に収まるよう全角を考慮して文字列を切り詰める。
  local function truncate(s, width)
    return word.truncate(s, width)
  end

  -- 索引ラベル: 一致項目は辞書名、不一致は見出し。
  local function index_label(item)
    if item.exact and item.dict ~= "" then
      return item.dict
    end
    return item.title
  end

  local PANEL_HEIGHT = 5
  local INDEX_WIDTH = 10

  -- 索引バッファ
  local index_buf = vim.api.nvim_create_buf(false, true) -- scratch, unlisted
  local index_lines = {}
  for i, item in ipairs(items) do
    local label = truncate(index_label(item), INDEX_WIDTH - 3)
    index_lines[#index_lines + 1] = string.format("%2d %s", i, label)
  end
  vim.api.nvim_buf_set_lines(index_buf, 0, -1, false, index_lines)
  vim.bo[index_buf].modifiable = false
  vim.bo[index_buf].buftype = "nofile"
  vim.bo[index_buf].bufhidden = "wipe"
  vim.bo[index_buf].filetype = "jksearch"
  vim.b[index_buf].jk_items = items

  -- 意味バッファ
  local meaning_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[meaning_buf].modifiable = false
  vim.bo[meaning_buf].buftype = "nofile"
  vim.bo[meaning_buf].filetype = "text"

  -- 元のウィンドウ/バッファは触らず、最下部に 5 行パネルを開く。
  local orig_win = vim.api.nvim_get_current_win()
  vim.cmd("belowright split")
  local index_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(index_win, PANEL_HEIGHT)

  -- 右側に意味ウィンドウ (左が索引)。
  vim.cmd("belowright vsplit")
  local meaning_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(index_win, INDEX_WIDTH)

  vim.api.nvim_win_set_buf(index_win, index_buf)
  vim.api.nvim_win_set_buf(meaning_win, meaning_buf)
  vim.api.nvim_win_set_option(meaning_win, "wrap", true)
  vim.api.nvim_win_set_option(index_win, "cursorline", true)

  -- 元ウィンドウにフォーカスを戻す
  vim.api.nvim_set_current_win(orig_win)

  -- 意味バッファにテキストを表示する
  local function set_meaning(text)
    if not vim.api.nvim_buf_is_valid(meaning_buf) then
      return
    end
    vim.bo[meaning_buf].modifiable = true
    vim.api.nvim_buf_set_lines(meaning_buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    vim.bo[meaning_buf].modifiable = false
  end

  -- 索引のカーソル行の意味を表示する。fetch 完了時にも、対象が現在行なら再表示する。
  local function update_meaning(lnum)
    if not vim.api.nvim_win_is_valid(index_win) then
      return
    end
    local item = items[lnum]
    if not item then
      return
    end
    local cached = text_cache[item.url]
    local body = cached
      or (item.snippet and item.snippet ~= "" and item.snippet)
      or (item.title .. "\n" .. (item.dict or ""))
    set_meaning(body)
    fetch_text(item, function(full)
      if vim.api.nvim_win_is_valid(index_win) then
        local cur = vim.api.nvim_win_get_cursor(index_win)[1]
        if cur == lnum then
          set_meaning(full)
        end
      end
    end)
  end

  -- 索引ウィンドウの keymap
  local opts = { buffer = index_buf, silent = true }
  vim.keymap.set("n", "n", function()
    local lnum = math.min(vim.api.nvim_win_get_cursor(index_win)[1] + 1, #items)
    vim.api.nvim_win_set_cursor(index_win, { lnum, 1 })
  end, opts)
  vim.keymap.set("n", "e", function()
    local lnum = math.max(vim.api.nvim_win_get_cursor(index_win)[1] - 1, 1)
    vim.api.nvim_win_set_cursor(index_win, { lnum, 1 })
  end, opts)
  vim.keymap.set("n", "<CR>", function()
    local lnum = vim.api.nvim_win_get_cursor(index_win)[1]
    local item = items[lnum]
    if item and item.url and source.open then
      source.open(item)
    end
  end, vim.tbl_extend("force", opts, { desc = "Open in browser" }))
  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, meaning_win, true)
    pcall(vim.api.nvim_win_close, index_win, true)
  end, vim.tbl_extend("force", opts, { desc = "Close" }))

  -- カーソル移動で意味を更新
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = index_buf,
    callback = function()
      update_meaning(vim.api.nvim_win_get_cursor(index_win)[1])
    end,
  })

  -- 初期表示
  update_meaning(1)
end

return M
