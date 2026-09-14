--- :checkhealth refsearch の実装。

local config = require("refsearch.config")
local source_mod = require("refsearch.source")

local M = {}

function M.check()
  vim.health.start("refsearch.nvim")

  -- 既定ソース
  local name = config.DATA.default_source or "japanknowledge"
  local source = source_mod.get(name)
  if source then
    vim.health.ok(("既定ソース: %s"):format(name))
  else
    vim.health.error(
      ("既定ソースが見つかりません: %s (lua/refsearch/sources/%s.lua が必要です)"):format(
        name,
        name
      )
    )
    return
  end

  -- クエリ抽出 (bunsetsu)
  if pcall(require, "bunsetsu") then
    vim.health.ok("bunsetsu.nvim: カーソル下の語の辞書形化が利用できます")
  else
    vim.health.info(
      "bunsetsu.nvim がありません (任意。カーソル下の語の辞書形化にのみ影響)"
    )
  end

  -- ソース固有の実行環境
  if source.check then
    source.check()
  end
end

return M
