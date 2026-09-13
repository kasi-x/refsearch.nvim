--- jk-search.nvim プラグイン本体。
---
--- カーソル下の語を bunsetsu.nvim (Vaporetto + UniDic) で辞書形に正規化し、
--- ジャパンナレッジLib で検索する。バックグラウンド Chrome (Puppeteer) で
--- 実行するため、メインブラウザには一切触れない。
---
--- 挙動:
---   * 完全一致の項目がある → それらをバックグラウンド Chrome のタブで複数開く
---   * 完全一致が無い → 検索結果の見出し一覧を picker に表示して選べる
---   * 認証が必要 → ログイン画面を開いて案内
---   * 同時接続オーバー → その旨を通知

local config = require("jksearch.config")
local word = require("jksearch.word")

local M = {}

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

---スクリプト実行の環境変数プレフィックスを返す。
---設定済みなら JK_REDIRECTOR / JK_PROXY、headless 設定が有効なら
---JK_HEADLESS=1 を付ける。
---@return string[]
local function env_args()
  local args = { "env" }
  local np = node_path_value()
  if np ~= "" then
    args[#args + 1] = "NODE_PATH=" .. np
  end
  if config.DATA.redirector and config.DATA.redirector ~= "" then
    args[#args + 1] = "JK_REDIRECTOR=" .. config.DATA.redirector
  end
  if config.DATA.proxy and config.DATA.proxy ~= "" then
    args[#args + 1] = "JK_PROXY=" .. config.DATA.proxy
  end
  if config.DATA.headless then
    args[#args + 1] = "JK_HEADLESS=1"
  end
  return args
end

---@class JKSearch.Result
---@field status string "ok"|"error"|"auth"|"full"
---@field query? string
---@field total? number
---@field exact? JKSearch.Hit[]
---@field results? JKSearch.Hit[]

---@class JKSearch.Hit
---@field title string
---@field dict string
---@field snippet string
---@field url string

---スクリプトを実行して結果を JSON で得る。
---@param query string
---@param on_result fun(data: JKSearch.Result)
local function run_script(query, on_result)
  local node = config.DATA.node or "node"
  local script = config.DATA.script

  local stderr = {}
  local out = vim.fn.jobstart(vim.list_extend(env_args(), { node, script, query }), {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local json = table.concat(data, "")
        local ok, parsed = pcall(vim.json.decode, json)
        if ok and type(parsed) == "table" then
          on_result(parsed)
        else
          on_result({ status = "error", message = json })
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr, data)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        on_result({
          status = "error",
          message = table.concat(stderr, ""),
        })
      end
    end,
  })

  if out <= 0 then
    on_result({ status = "error", message = "failed to start jk-search.js" })
  end
end

---常駐 Chrome のタブで URL を複数開く (jk-search.js --open-tabs)。
---@param urls string[]
local function open_tabs(urls)
  if #urls == 0 then
    return
  end
  local args = vim.list_extend(env_args(), {
    config.DATA.node,
    config.DATA.script,
    "--open-tabs",
  })
  for _, u in ipairs(urls) do
    args[#args + 1] = u
  end
  vim.fn.jobstart(args, { detach = true })
end

---検索結果を画面下部のパネルで表示する (元のバッファはそのまま残す)。
---レイアウト (最下部 5 行パネル):
---   左 (幅 20): 索引インデックス (一致項目は辞書名、不一致は見出し)
---   右:        選択中項目の意味 (全文を非同期取得して表示)
---バッファローカル keymap (索引ウィンドウ):
---   n/e  次/前の項目
---   <CR> カーソル行の項目をブラウザで開く
---   q    閉じる
---@param data JKSearch.Result
local function show_picker(data)
  local hits = data.results or {}
  if #hits == 0 then
    vim.notify("ジャパンナレッジ: 検索結果 0 件", vim.log.levels.INFO)
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
  local history = require("jksearch.history")
  local text_cache = {}
  local fetching = {}

  -- 履歴に保存済みの意味全文を読み込む
  do
    local entry = history.get(query)
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
    local node = config.DATA.node or "node"
    local script = config.DATA.script
    vim.fn.jobstart(vim.list_extend(env_args(), { node, script, "--fetch", url }), {
      stdout_buffered = true,
      on_stdout = function(_, outdata)
        if outdata and #outdata > 0 then
          local json = table.concat(outdata, "")
          local ok, parsed = pcall(vim.json.decode, json)
          if ok and parsed.status == "ok" and parsed.text then
            text_cache[url] = parsed.text
            fetching[url] = nil
            history.store_text(query, url, parsed.text)
            if on_done then
              on_done(parsed.text)
            end
          else
            -- 失敗時はフラグを戻して再取得できるようにする
            fetching[url] = nil
          end
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          fetching[url] = nil
        end
      end,
    })
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
    if item and item.url then
      open_tabs({ item.url })
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

---検索を実行する。
---ローカル履歴に保存済みの結果があればネットワーク検索をせず、それを優先して表示する。
---@param query string 検索語 (辞書形)
local function search(query)
  local history = require("jksearch.history")

  -- 1. ローカル履歴にあればそれを優先
  local saved = history.get(query)
  if saved and saved.results and #saved.results > 0 then
    vim.notify(
      "ジャパンナレッジ: " .. query .. " (ローカル保存済み)",
      vim.log.levels.INFO
    )
    show_picker({
      query = query,
      total = #saved.results,
      exact = vim.tbl_filter(function(r)
        return r.exact
      end, saved.results),
      results = saved.results,
    })
    return
  end

  -- 2. 無ければネットワーク検索
  vim.notify("ジャパンナレッジ: " .. query .. " を検索中...", vim.log.levels.INFO)
  run_script(query, function(data)
    if data.status == "ok" then
      local exact = data.exact or {}
      -- 完全一致件数を通知して、常にピッカーで結果を表示する
      if #exact > 0 then
        vim.notify(
          ("ジャパンナレッジ: 完全一致 %d 件 (%d 件中)。ピッカーで選択してください"):format(
            #exact,
            tonumber(data.total) or 0
          ),
          vim.log.levels.INFO
        )
      else
        vim.notify(
          ("ジャパンナレッジ: 完全一致なし (%d 件中)。候補をピッカーで選択してください"):format(
            tonumber(data.total) or 0
          ),
          vim.log.levels.INFO
        )
      end
      -- 検索結果をローカル履歴に保存 (同じ語の再検索時に再利用)
      -- exact フラグを付けて保存し、ローカル読み込み時に完全一致表示を再現できるようにする
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
      history.store_search(data.query, results_for_history)
      show_picker(data)
    elseif data.status == "auth" then
      vim.notify(
        "ジャパンナレッジ: ログインが必要です。ブラウザでログインしてください",
        vim.log.levels.WARN
      )
    elseif data.status == "full" then
      vim.notify(
        "ジャパンナレッジ: 同時接続数オーバー。時間をおいて再実行してください",
        vim.log.levels.WARN
      )
    else
      vim.notify(
        "ジャパンナレッジ: エラー " .. (data.message or ""),
        vim.log.levels.ERROR
      )
    end
  end)
end

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

---カーソル下の語を bunsetsu で辞書形化して返す。
---名詞+名詞の複合語は分割せず、連続する名詞全体 (一語) を検索語にする。
---公開 API: 検索語の抽出だけを他の用途から使うこともできる。
---@return string|nil 検索語
function M.word_under_cursor()
  local ok, bunsetsu = pcall(require, "bunsetsu")
  if not ok then
    vim.notify("jk-search: bunsetsu.nvim が見つかりません", vim.log.levels.ERROR)
    return nil
  end
  local r = bunsetsu.lemma_under_cursor()
  if not r then
    vim.notify("jk-search: カーソル下の語を特定できません", vim.log.levels.INFO)
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

---コマンド実装: :JKSearch [語]
---語を省略した場合はカーソル下の語を使う。
---@param args string[]
function M.command(args)
  local query = args[1]
  if not query or query == "" then
    query = M.word_under_cursor()
  end
  if not query or query == "" then
    return
  end
  search(query)
end

---カーソル下の語を検索 (B キー用)。
function M.search_cursor()
  local query = M.word_under_cursor()
  if query then
    search(query)
  end
end

---Chrome を起動して OpenAthens セッションを初期化する (先回りのウォームアップ)。
---Chrome は常駐させたままにするため、初回検索が速くなる。
---bang (:JKSearchInit!) 付きなら可視ウィンドウを強制する (手動ログイン用)。
---@param opts? { visible?: boolean }
function M.init(opts)
  local args = env_args()
  -- 強制可視 (ログイン時) なら JK_HEADLESS を外す
  if opts and opts.visible then
    for i = #args, 1, -1 do
      if args[i] == "JK_HEADLESS=1" then
        table.remove(args, i)
      end
    end
  end
  args = vim.list_extend(args, {
    config.DATA.node,
    config.DATA.script,
    "--init",
  })
  vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local json = table.concat(data, "")
        local ok, parsed = pcall(vim.json.decode, json)
        if ok then
          if parsed.status == "ok" then
            if parsed.state == "ready" then
              vim.notify(
                "ジャパンナレッジ: Chrome 初期化完了 (ログイン済み)",
                vim.log.levels.INFO
              )
            elseif parsed.state == "auth" then
              vim.notify(
                "ジャパンナレッジ: ログインが必要です。開いた Chrome でログインしてください",
                vim.log.levels.WARN
              )
            elseif parsed.state == "full" then
              vim.notify(
                "ジャパンナレッジ: 同時接続数オーバー",
                vim.log.levels.WARN
              )
            else
              vim.notify(
                "ジャパンナレッジ: 初期化状態 " .. parsed.state,
                vim.log.levels.INFO
              )
            end
          elseif parsed.status == "auth" then
            vim.notify(
              "ジャパンナレッジ: ログインが必要です。開いた Chrome でログインしてください",
              vim.log.levels.WARN
            )
          else
            vim.notify(
              "ジャパンナレッジ: 初期化エラー " .. (parsed.message or ""),
              vim.log.levels.ERROR
            )
          end
        end
      end
    end,
  })
end

return M
