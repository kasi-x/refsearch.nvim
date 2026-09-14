describe("refsearch.word (cursor word helpers)", function()
  local word = require("refsearch.word")

  describe("truncate()", function()
    it("truncates ascii text to the display width", function()
      assert.are.equal("hello", word.truncate("hello world", 5))
    end)

    it("keeps whole full-width characters only", function()
      -- 各文字は幅 2。width 6 なら 3 文字まで入る
      assert.are.equal("日本語", word.truncate("日本語です", 6))
      -- width 7 でも 4 文字目は入らない (6 + 2 > 7)
      assert.are.equal("日本語", word.truncate("日本語です", 7))
    end)

    it("handles mixed-width text", function()
      -- "Vi" (2) + "は" (2) = 4。width 5 では "Vimは" (2+1+2=5) まで入る
      assert.are.equal("Vimは", word.truncate("Vimはエディタ", 5))
    end)

    it("returns empty string for zero width", function()
      assert.are.equal("", word.truncate("テスト", 0))
    end)

    it("returns the whole string when it fits", function()
      assert.are.equal("テスト", word.truncate("テスト", 10))
    end)
  end)

  describe("token_positions()", function()
    it("locates each word in the line", function()
      local positions =
        word.token_positions("これは走った。", { "これ", "は", "走っ", "た", "。" })
      assert.are.same({ 1, 7, 10, 16, 19 }, positions)
    end)

    it("falls back to the previous word end for unseen words", function()
      local positions = word.token_positions("これは", { "これ", "は", "未知語" })
      assert.are.same({ 1, 7, 10 }, positions)
    end)
  end)

  describe("token_at()", function()
    local words = { "これ", "は", "走っ" }
    local positions = { 1, 7, 10 }

    it("returns the index of the token containing the cursor", function()
      assert.are.equal(1, word.token_at(positions, words, 3))
      assert.are.equal(2, word.token_at(positions, words, 8))
      assert.are.equal(3, word.token_at(positions, words, 12))
    end)

    it("accepts cursor at token boundaries", function()
      assert.are.equal(1, word.token_at(positions, words, 1))
      assert.are.equal(1, word.token_at(positions, words, 6))
      assert.are.equal(2, word.token_at(positions, words, 7))
    end)

    it("returns nil when the cursor is outside every token", function()
      assert.is_nil(word.token_at(positions, words, 99))
    end)
  end)

  describe("compound_noun()", function()
    -- 「形態素解析をする」を Vibrato で分割した想定
    local words = { "形態素", "解析", "を", "する" }
    local positions = { 1, 10, 16, 19 }
    local infos = { { pos = "名詞" }, { pos = "名詞" }, { pos = "助詞" }, { pos = "動詞" } }

    it("expands consecutive nouns around the cursor", function()
      assert.are.equal("形態素解析", word.compound_noun(words, positions, infos, 12))
      assert.are.equal("形態素解析", word.compound_noun(words, positions, infos, 1))
    end)

    it("returns nil for a single noun", function()
      local single_words = { "実験", "する" }
      local single_positions = { 1, 7 }
      local single_infos = { { pos = "名詞" }, { pos = "動詞" } }
      assert.is_nil(word.compound_noun(single_words, single_positions, single_infos, 1))
    end)

    it("returns nil when the cursor is on a non-noun", function()
      assert.is_nil(word.compound_noun(words, positions, infos, 16)) -- 「を」
    end)

    it("returns nil when the cursor is outside every token", function()
      assert.is_nil(word.compound_noun(words, positions, infos, 999))
    end)
  end)
end)
