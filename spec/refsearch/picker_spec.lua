describe("refsearch.picker (source-delegated UI)", function()
  local picker = require("refsearch.picker")
  local history = require("refsearch.history")
  local config = require("refsearch.config")

  local captured
  local source

  before_each(function()
    captured = { opened = {}, fetched = {} }
    source = {
      name = "fake",
      fetch = function(item, on_done)
        captured.fetched[#captured.fetched + 1] = item.url
        on_done("全文: " .. item.title)
      end,
      open = function(item)
        captured.opened[#captured.opened + 1] = item
      end,
    }
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "本文" })
    config.DATA.history_file = vim.fn.tempname() .. ".json"
  end)

  after_each(function()
    os.remove(config.DATA.history_file)
    pcall(vim.cmd, "silent! only!")
  end)

  ---パネルの索引バッファ (filetype = refsearch) を探す。
  local function find_index_buf()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == "refsearch" then
        return b
      end
    end
    return nil
  end

  it("shows an empty-results notice without panels", function()
    local notified
    local old = vim.notify
    vim.notify = function(msg)
      notified = msg
    end
    picker.show({ query = "何か", results = {} }, source)
    vim.notify = old
    assert.is_truthy(notified:find("検索結果 0 件"))
  end)

  it("sorts exact matches first in the index", function()
    picker.show({
      query = "実験",
      source = "fake",
      results = {
        { title = "実験心理学", dict = "心理学辞典", snippet = "s", url = "u2" },
        { title = "実験", dict = "日本大百科全書", snippet = "ためし", url = "u1" },
      },
      exact = { { url = "u1" } },
    }, source)
    local buf = find_index_buf()
    assert.is_not_nil(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- 完全一致が先頭。ラベルは索引幅に切り詰められる
    assert.is_truthy(lines[1]:find("日本"))
    assert.is_truthy(lines[2]:find("実験"))
  end)

  it("fetches the full text through the source on display", function()
    local fetched_urls = {}
    source.fetch = function(item, on_done)
      fetched_urls[#fetched_urls + 1] = item.url
      on_done("全文: " .. item.title)
    end
    picker.show({
      query = "実験",
      source = "fake",
      results = { { title = "実験", dict = "辞書", snippet = "", url = "u1" } },
      exact = {},
    }, source)
    -- 初期表示 (update_meaning(1)) で fetch がソース経由で呼ばれる
    assert.are.equal(1, #fetched_urls)
    assert.are.equal("u1", fetched_urls[1])
  end)

  it("opens items through source.open", function()
    local opened = {}
    source.open = function(item)
      opened[#opened + 1] = item
    end
    picker.show({
      query = "実験",
      source = "fake",
      results = { { title = "実験", dict = "辞書", snippet = "", url = "u1" } },
      exact = {},
    }, source)
    source.open({ title = "実験", url = "u1" })
    assert.are.equal(1, #opened)
    assert.are.equal("u1", opened[1].url)
  end)

  it("history entries are stored per source", function()
    history.store_search("fake", "実験", { { title = "実験", url = "u1" } })
    local entry = history.get("fake", "実験")
    assert.is_not_nil(entry)
  end)
end)
