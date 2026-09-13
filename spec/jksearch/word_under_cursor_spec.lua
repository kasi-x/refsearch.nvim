describe("jksearch.word_under_cursor() (public API)", function()
  local jksearch = require("jksearch")

  before_each(function()
    -- bunsetsu (Vibrato トークナイザ) のスタブ
    package.preload["bunsetsu"] = function()
      return {
        lemma_under_cursor = function()
          local col = vim.fn.col(".")
          -- 形態素(1-9) 解析(10-15) を(16-18) する(19-24) 。(25-27)
          local tokens = {
            { surface = "形態素", start = 1, pos = "名詞", lemma = "形態素" },
            { surface = "解析", start = 10, pos = "名詞", lemma = "解析" },
            { surface = "を", start = 16, pos = "助詞", lemma = "を" },
            { surface = "する", start = 19, pos = "動詞", lemma = "する" },
          }
          for _, t in ipairs(tokens) do
            if col >= t.start and col <= t.start + #t.surface - 1 then
              return { surface = t.surface, lemma = t.lemma, reading = "", pos = t.pos }
            end
          end
          return nil
        end,
      }
    end
    package.preload["bunsetsu._commands.vibrato"] = function()
      return {
        tokenize_detailed = function(line)
          if line == "形態素解析をする。" then
            return { "形態素", "解析", "を", "する" }, {
              { pos = "名詞" },
              { pos = "名詞" },
              { pos = "助詞" },
              { pos = "動詞" },
            }
          end
          return {}, {}
        end,
      }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "形態素解析をする。" })
  end)

  after_each(function()
    package.preload["bunsetsu"] = nil
    package.preload["bunsetsu._commands.vibrato"] = nil
    package.loaded["bunsetsu"] = nil
    package.loaded["bunsetsu._commands.vibrato"] = nil
  end)

  it("expands consecutive nouns into a compound search word", function()
    vim.api.nvim_win_set_cursor(0, { 1, 2 }) -- 「形態素」の中
    assert.are.equal("形態素解析", jksearch.word_under_cursor())
    vim.api.nvim_win_set_cursor(0, { 1, 11 }) -- 「解析」の中
    assert.are.equal("形態素解析", jksearch.word_under_cursor())
  end)

  it("returns the particle itself when the cursor is on one", function()
    vim.api.nvim_win_set_cursor(0, { 1, 16 }) -- 「を」
    assert.are.equal("を", jksearch.word_under_cursor())
  end)

  it("returns the verb surface when the cursor is on one", function()
    vim.api.nvim_win_set_cursor(0, { 1, 20 }) -- 「する」
    assert.are.equal("する", jksearch.word_under_cursor())
  end)

  it("returns nil when no word is under the cursor", function()
    vim.api.nvim_win_set_cursor(0, { 1, 27 }) -- 「。」の末尾
    assert.is_nil(jksearch.word_under_cursor())
  end)
end)
