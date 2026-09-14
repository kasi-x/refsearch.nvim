describe("documentation consistency", function()
  it("resolves every |reference| in the help to a defined tag", function()
    local defined = {}
    for _, line in ipairs(vim.fn.readfile("doc/tags")) do
      defined[vim.split(line, "\t", { plain = true })[1]] = true
    end
    local refs = {}
    for _, line in ipairs(vim.fn.readfile("doc/refsearch.txt")) do
      for ref in line:gmatch("|([%w:.-]+)|") do
        refs[#refs + 1] = ref
      end
    end
    assert.is_true(#refs >= 5)
    for _, ref in ipairs(refs) do
      assert.is_truthy(defined[ref], "undefined help tag: |" .. ref .. "|")
    end
  end)
end)
