describe("jksearch.history (source-keyed)", function()
  local config = require("jksearch.config")
  local history = require("jksearch.history")

  local tmp

  before_each(function()
    tmp = vim.fn.tempname() .. ".json"
    config.DATA.history_file = tmp
  end)

  after_each(function()
    os.remove(tmp)
  end)

  it("returns empty results when the file does not exist", function()
    assert.are.same({}, history.load())
    assert.is_nil(history.get("japanknowledge", "実験"))
  end)

  it("stores and loads search results per source", function()
    local results = {
      {
        title = "実験",
        dict = "日本大百科全書",
        snippet = "ため-す 【実験】",
        url = "https://example.com/1",
        exact = true,
      },
      {
        title = "実験心理学",
        dict = "心理学辞典",
        snippet = "experimental psychology",
        url = "https://example.com/2",
        exact = false,
      },
    }
    history.store_search("japanknowledge", "実験", results)

    local entry = history.get("japanknowledge", "実験")
    assert.is_not_nil(entry)
    assert.are.equal("実験", entry.query)
    assert.are.equal(2, #entry.results)
    assert.are.equal("日本大百科全書", entry.results[1].dict)
    assert.is_true(entry.results[1].exact)
    assert.is_false(entry.results[2].exact)
  end)

  it("keeps sources separate", function()
    history.store_search("japanknowledge", "実験", { { title = "jk", url = "u1" } })
    history.store_search("weblio", "実験", { { title = "weblio", url = "u2" } })

    assert.are.equal("jk", history.get("japanknowledge", "実験").results[1].title)
    assert.are.equal("weblio", history.get("weblio", "実験").results[1].title)
  end)

  it("does not overwrite an existing entry", function()
    history.store_search(
      "japanknowledge",
      "実験",
      { { title = "実験", url = "https://example.com/1" } }
    )
    history.store_search(
      "japanknowledge",
      "実験",
      { { title = "別物", url = "https://example.com/9" } }
    )

    local entry = history.get("japanknowledge", "実験")
    assert.are.equal(1, #entry.results)
    assert.are.equal("実験", entry.results[1].title)
  end)

  it("stores and gets full text by url", function()
    history.store_search(
      "japanknowledge",
      "実験",
      { { title = "実験", url = "https://example.com/1" } }
    )
    assert.is_nil(history.get_text("japanknowledge", "実験", "https://example.com/1"))

    history.store_text("japanknowledge", "実験", "https://example.com/1", "意味の全文")
    assert.are.equal(
      "意味の全文",
      history.get_text("japanknowledge", "実験", "https://example.com/1")
    )
  end)

  it("survives save/load roundtrip", function()
    history.store_search(
      "japanknowledge",
      "実験",
      { { title = "実験", url = "https://example.com/1" } }
    )
    history.store_text("japanknowledge", "実験", "https://example.com/1", "全文")

    local data = history.load()
    assert.is_not_nil(data.japanknowledge["実験"])
    assert.are.equal("全文", data.japanknowledge["実験"].results[1].text)
  end)
end)
