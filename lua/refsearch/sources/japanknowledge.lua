---ジャパンナレッジLib 検索ソース (オプショナル)。
--
-- 専用プロファイルのバックグラウンド Chrome (Puppeteer) で
-- https://japanknowledge.com/lib/ を検索し、結果を JSON で返す。
-- OpenAthens 経由の所属機関アクセスを前提とするため、redirector / proxy の
-- 設定が必須 (機関設定プラグインや vim.g で設定する)。
--
-- 使い方:
--   :RefSearch [語]     検索 (既定ソースが japanknowledge のとき)
--   :RefSearchInit      Chrome セッションを初期化
--   :RefSearchInit!     可視 Chrome で初期化 (手動ログイン用)
--
-- 設定 (vim.g.refsearch_configuration の sources.japanknowledge):
--   redirector : OpenAthens リダイレクタ URL (必須)
--   proxy      : OpenAthens proxy のベース URL (必須)
--   script     : 検索スクリプト (refsearch.js) のパス
--   node       : node 実行ファイル
--   headless   : true でヘッドレス Chrome

local config = require("refsearch.config")

local M = {
  name = "japanknowledge",
}

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

---このソースの設定を返す。
---@return table
local function source_config()
  return (config.DATA.sources and config.DATA.sources[M.name]) or {}
end

---検索スクリプト (bin/refsearch.js) のパスを返す。
---未設定なら runtimepath から自動解決する。
---@return string
local function script_path()
  local sc = source_config()
  if sc.script and sc.script ~= "" then
    return sc.script
  end
  local found = vim.api.nvim_get_runtime_file("bin/refsearch.js", false)
  return found[1] or ""
end

---Chrome 専用プロファイルのパスを返す。
---既定は旧プラグイン名時代と同じパス (Chrome のログインセッションを引き継ぐ)。
---@return string
local function profile_path()
  local sc = source_config()
  return sc.profile or vim.fn.expand("~/.local/share/jk-search/profile")
end

---スクリプト実行用の環境変数プレフィックス ({ "env", "NODE_PATH=...", ... })。
---@return string[]
local function env_args()
  local sc = source_config()
  local args = { "env" }
  local np = node_path_value()
  if np ~= "" then
    args[#args + 1] = "NODE_PATH=" .. np
  end
  if sc.redirector and sc.redirector ~= "" then
    args[#args + 1] = "RS_REDIRECTOR=" .. sc.redirector
  end
  if sc.proxy and sc.proxy ~= "" then
    args[#args + 1] = "RS_PROXY=" .. sc.proxy
  end
  local profile = profile_path()
  if profile ~= "" then
    args[#args + 1] = "RS_PROFILE=" .. profile
  end
  if sc.headless then
    args[#args + 1] = "RS_HEADLESS=1"
  end
  return args
end

---@type table<integer, string[]>
local outputs = {}

---js スクリプトを起動し、完了時に stdout (行配列) と終了コードを返す。
---@param args string[] スクリプトへの引数
---@param on_finish fun(outdata: string[]|nil, code: number)
local function run_js(args, on_finish)
  local sc = source_config()
  local argv = vim.list_extend({ sc.node or "node", script_path() }, args)
  local job = vim.fn.jobstart(vim.list_extend(env_args(), argv), {
    stdout_buffered = true,
    on_stdout = function(j, data)
      if not data then
        return
      end
      outputs[j] = outputs[j] or {}
      vim.list_extend(outputs[j], data)
    end,
    on_exit = function(j, code)
      local outdata = outputs[j]
      outputs[j] = nil
      on_finish(outdata, code)
    end,
  })
  return job
end

---:checkhealth からの拡張ポイント。実行環境を点検する。
function M.check()
  local sc = source_config()
  local name = "japanknowledge"

  if not (sc.redirector and sc.redirector ~= "") or not (sc.proxy and sc.proxy ~= "") then
    vim.health.error(
      "OpenAthens の設定がありません (sources.japanknowledge.redirector / proxy)",
      "所属機関の URL を vim.g.refsearch_configuration に設定してください"
    )
  else
    vim.health.ok("OpenAthens 設定: OK")
  end

  if vim.fn.executable(sc.node or "node") == 1 then
    vim.health.ok(("node: %s"):format(sc.node or "node"))
  else
    vim.health.error(("node が見つかりません: %s"):format(sc.node or "node"))
  end

  local script = script_path()
  if script ~= "" and vim.fn.filereadable(script) == 1 then
    vim.health.ok(("検索スクリプト: %s"):format(script))
  else
    vim.health.error(
      "検索スクリプト (bin/refsearch.js) が見つかりません。script 設定でパスを指定してください"
    )
  end
end

---認証が必要なときの案内。
local function notify_auth()
  vim.notify(
    "ジャパンナレッジ: ログインが必要です (:RefSearchInit! で可視 Chrome を開いて手動ログイン)",
    vim.log.levels.WARN
  )
end

---検索して結果を返す (:RefSearch から呼ばれる)。
---認証が必要・同時接続オーバーの場合は案内を表示し、error ステータスを返す。
---@param query string 検索語
---@param on_result fun(data: table)
function M.search(query, on_result)
  run_js({ query }, function(outdata, code)
    if code ~= 0 then
      on_result({ status = "error", message = table.concat(outdata or {}, "") })
      return
    end
    local json = table.concat(outdata or {}, "")
    local ok, parsed = pcall(vim.json.decode, json)
    if not ok or type(parsed) ~= "table" then
      on_result({ status = "error", message = json })
      return
    end
    if parsed.status == "auth" then
      notify_auth()
      on_result({ status = "error", message = "ログインが必要です" })
      return
    end
    if parsed.status == "full" then
      vim.notify(
        "ジャパンナレッジ: 同時接続数オーバー。時間をおいて再実行してください",
        vim.log.levels.WARN
      )
      on_result({ status = "error", message = "同時接続数オーバー" })
      return
    end
    if parsed.status ~= "ok" then
      on_result({ status = "error", message = parsed.message or json })
      return
    end
    on_result({
      status = "ok",
      query = parsed.query or query,
      total = parsed.total,
      results = parsed.results or {},
      exact = parsed.exact or {},
    })
  end)
end

---項目の意味全文を取得する。
---@param item table 項目 (url フィールドを使用)
---@param on_done fun(text: string|nil)
function M.fetch(item, on_done)
  run_js({ "--fetch", item.url }, function(outdata, code)
    if code ~= 0 then
      on_done(nil)
      return
    end
    local json = table.concat(outdata or {}, "")
    local ok, parsed = pcall(vim.json.decode, json)
    if ok and parsed.status == "ok" and parsed.text then
      on_done(parsed.text)
    else
      on_done(nil)
    end
  end)
end

---項目を常駐 Chrome のタブで開く。
---@param item table 項目 (url フィールドを使用)
function M.open(item)
  if not item.url then
    return
  end
  vim.fn.jobstart(
    vim.list_extend(env_args(), {
      (source_config().node or "node"),
      source_config().script,
      "--open-tabs",
      item.url,
    }),
    { detach = true }
  )
end

---Chrome セッションを初期化する (:RefSearchInit)。
---@param opts? { visible?: boolean }
function M.init_session(opts)
  local args = env_args()
  -- 強制可視 (ログイン時) なら RS_HEADLESS を外す
  if opts and opts.visible then
    for i = #args, 1, -1 do
      if args[i] == "RS_HEADLESS=1" then
        table.remove(args, i)
      end
    end
  end
  local sc = source_config()
  vim.fn.jobstart(vim.list_extend(args, { sc.node or "node", script_path(), "--init" }), {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local json = table.concat(data, "")
        local ok, parsed = pcall(vim.json.decode, json)
        if not ok then
          return
        end
        if parsed.status == "ok" then
          if parsed.state == "ready" then
            vim.notify(
              "ジャパンナレッジ: Chrome 初期化完了 (ログイン済み)",
              vim.log.levels.INFO
            )
          elseif parsed.state == "auth" then
            notify_auth()
          elseif parsed.state == "full" then
            vim.notify("ジャパンナレッジ: 同時接続数オーバー", vim.log.levels.WARN)
          else
            vim.notify(
              "ジャパンナレッジ: 初期化状態 " .. parsed.state,
              vim.log.levels.INFO
            )
          end
        elseif parsed.status == "auth" then
          notify_auth()
        else
          vim.notify(
            "ジャパンナレッジ: 初期化エラー " .. (parsed.message or ""),
            vim.log.levels.ERROR
          )
        end
      end
    end,
  })
end

return M
