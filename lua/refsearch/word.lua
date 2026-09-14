---カーソル下の検索語を取り出すための純粋なヘルパ群。
--
-- bunsetsu.nvim (Vibrato) のトークナイズ結果を受け取り、カーソル位置の
-- 語の特定や複合名詞の展開を行う。ファイルの入出力やジョブには依存せず、
-- 単体テスト可能にするため分離している。
-- (表示幅の計算のみ vim.fn.strdisplaywidth を使う)

local M = {}

-- UTF-8 の 1 文字にマッチするパターン (Lua 5.3 の utf8.charpattern と同等)。
-- グローバルの utf8 (lua-utf8) に依存せず文字単位の走査ができる。
local CHAR_PATTERN = "[%z\x01-\x7F\xC2-\xF4][\x80-\xBF]*"

---表示幅に収まるよう先頭から文字単位で切り詰める (全角文字を考慮)。
---@param s string
---@param width number 表示幅 (全角文字は 2 消費する)
---@return string
function M.truncate(s, width)
  local out = {}
  local cur = 0
  for char in s:gmatch(CHAR_PATTERN) do
    local w = vim.fn.strdisplaywidth(char)
    if cur + w > width then
      break
    end
    cur = cur + w
    out[#out + 1] = char
  end
  return table.concat(out)
end

---トークナイザの語列から、行内の各語の開始バイト位置を求める。
---語が行内に見つからない場合は直前の語の直後を使う。
---@param line string
---@param words string[] 表層形
---@return number[] positions 各語の開始位置 (1始まりバイト)
function M.token_positions(line, words)
  local positions = {}
  local search_from = 1
  for i, w in ipairs(words) do
    local found = line:find(w, search_from, true)
    if not found then
      found = search_from
    end
    positions[i] = found
    search_from = found + #w
  end
  return positions
end

---カーソル位置 (1始まりバイト) を含む語のインデックスを返す。無ければ nil。
---@param positions number[] M.token_positions の結果
---@param words string[]
---@param cursor number
---@return number|nil
function M.token_at(positions, words, cursor)
  for i = 1, #words do
    local start_col = positions[i]
    local end_col = start_col + #words[i] - 1
    if cursor >= start_col and cursor <= end_col then
      return i
    end
  end
  return nil
end

---カーソル位置を含む、連続する名詞の複合語を返す。
---複合語 (名詞が 2 つ以上連続) でなければ nil。
---@param words string[]
---@param positions number[]
---@param infos table[] 各語の詳細 { pos, ... }
---@param cursor number
---@return string|nil
function M.compound_noun(words, positions, infos, cursor)
  local cursor_i = M.token_at(positions, words, cursor)
  if not cursor_i then
    return nil
  end

  local is_noun = function(i)
    local info = infos[i]
    return info and info.pos and info.pos:match("名詞") ~= nil
  end
  if not is_noun(cursor_i) then
    return nil
  end

  -- 左右へ連続する名詞まで拡張する
  local lo = cursor_i
  while lo > 1 and is_noun(lo - 1) do
    lo = lo - 1
  end
  local hi = cursor_i
  while hi < #words and is_noun(hi + 1) do
    hi = hi + 1
  end

  if lo == hi then
    return nil -- 単一名詞 (複合語ではない)
  end
  return table.concat(words, "", lo, hi)
end

return M
