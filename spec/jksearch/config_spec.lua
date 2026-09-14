describe("jksearch.config", function()
  local config = require("jksearch.config")

  it("has no institution-specific defaults", function()
    local jk = config.DATA.sources.japanknowledge
    assert.are.equal("", jk.redirector)
    assert.are.equal("", jk.proxy)
  end)

  it("defaults to the japanknowledge source", function()
    assert.are.equal("japanknowledge", config.DATA.default_source)
  end)

  it("merges user configuration via setup()", function()
    config.setup({
      default_source = "japanknowledge",
      sources = {
        japanknowledge = {
          redirector = "https://go.openathens.net/redirector/example.ac.jp",
          proxy = "https://japanknowledge-com.example.proxy.openathens.net",
          headless = true,
        },
      },
    })
    local jk = config.DATA.sources.japanknowledge
    assert.are.equal("https://go.openathens.net/redirector/example.ac.jp", jk.redirector)
    assert.are.equal("https://japanknowledge-com.example.proxy.openathens.net", jk.proxy)
    assert.is_true(jk.headless)
    -- 他の既定値は維持される
    assert.are.equal("node", jk.node)

    -- 後片付け
    config.setup({
      sources = { japanknowledge = { redirector = "", proxy = "", headless = false } },
    })
  end)
end)
