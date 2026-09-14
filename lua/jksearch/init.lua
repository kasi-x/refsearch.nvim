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
local picker = require("jksearch.picker")
local word = require("jksearch.word")

local M = {}

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
  local out = vim.fn.jobstart(vim.list_extend(config.env_args(), { node, script, query }), {
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
    picker.show({
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
      picker.show(data)
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
  -- :JKSearch 複数 語 のように空白区切りで複数の引数を 1 語に連結できる
  local query = #args > 0 and table.concat(args, " ") or nil
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
  local args = config.env_args()
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
