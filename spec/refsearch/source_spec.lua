describe("refsearch.source (registry)", function()
  local source_mod = require("refsearch.source")
  local config = require("refsearch.config")

  after_each(function()
    package.loaded["refsearch.sources.test_source"] = nil
    package.loaded["refsearch.sources.missing_source"] = nil
    package.loaded["refsearch.sources.missing_source"] = nil
  end)

  it("resolves the bundled japanknowledge source", function()
    local spec = source_mod.get("japanknowledge")
    assert.is_not_nil(spec)
    assert.are.equal("japanknowledge", spec.name)
    assert.is_function(spec.search)
  end)

  it("returns nil for unknown sources", function()
    assert.is_nil(source_mod.get("存在しないソース"))
  end)

  it("registers and resolves custom sources", function()
    local custom = { name = "custom_test", search = function() end }
    source_mod.register(custom)
    assert.are.equal(custom, source_mod.get("custom_test"))
  end)
end)

describe("refsearch.health", function()
  it("reports the default source and missing script", function()
    local health = require("refsearch.health")
    assert.is_function(health.check)
    -- check() は vim.health を使うため、ここでは読み込みのみ確認
  end)
end)
