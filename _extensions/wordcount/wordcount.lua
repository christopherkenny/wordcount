words = 0
words_by_section = {}
section_order = {}
current_section = "Document"
track_sections = true

-- Count words in inline elements
function count_inlines(inlines)
  for _, el in ipairs(inlines) do
    if el.t == "Str" and el.text:match("%P") then
      words = words + 1
      if track_sections then
        words_by_section[current_section] = (words_by_section[current_section] or 0) + 1
      end
    elseif el.t == "Code" then
      local _, n = el.text:gsub("%S+", "")
      words = words + n
      if track_sections then
        words_by_section[current_section] = (words_by_section[current_section] or 0) + n
      end
    end
  end
end

-- Count words in block elements and update section context
function count_blocks(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level <= 3 then
      current_section = pandoc.utils.stringify(block.content)
      if track_sections and not words_by_section[current_section] then
        table.insert(section_order, current_section)
      end
    elseif block.t == "Para" or block.t == "Plain" then
      count_inlines(block.content)
    elseif block.t == "CodeBlock" then
      local _, n = block.text:gsub("%S+", "")
      words = words + n
      if track_sections then
        words_by_section[current_section] = (words_by_section[current_section] or 0) + n
      end
    elseif block.t == "BlockQuote" or block.t == "Div" then
      count_blocks(block.content)
    elseif block.t == "BulletList" or block.t == "OrderedList" then
      for _, item in ipairs(block.content) do
        count_blocks(item)
      end
    end
  end
end

function section_exists(name)
  for _, v in ipairs(section_order) do
    if v == name then return true end
  end
  return false
end

-- Add Reference section word count after citeproc
function count_reference_section(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and block.attr and block.attr.classes then
      for _, class in ipairs(block.attr.classes) do
        if class == "references" then
          local ref_section = "References"
          if not section_exists(ref_section) then
            table.insert(section_order, ref_section)
            words_by_section[ref_section] = 0
          end
          local saved_track = track_sections
          track_sections = true
          current_section = ref_section
          count_blocks(block.content)
          track_sections = saved_track
        end
      end
    end
  end
end

-- Replace {{wordcount}} and {{wordcountref}} in metadata
local function add_count_meta(meta)
  for key, val in pairs(meta) do
    local stri = pandoc.utils.stringify(val)
    if string.find(stri, "{{wordcount}}") then
      meta[key] = stri:gsub("{{wordcount}}", words)
    end
    if string.find(stri, "{{wordcountref}}") then
      meta[key] = stri:gsub("{{wordcountref}}", wordsall)
    end
  end
end

-- Replace {{wordcount}} and {{wordcountref}} in body text
add_count_body = {
  Str = function(el)
    if el.text == "{{wordcount}}" then
      el.text = tostring(words)
    elseif el.text == "{{wordcountref}}" then
      el.text = tostring(wordsall)
    end
    return el
  end
}

function Pandoc(el)
  -- Phase 1: Count body (before citeproc)
  words = 0
  words_by_section = {}
  section_order = {}
  current_section = "Document"
  track_sections = true
  count_blocks(el.blocks)
  wordsbody = words

  -- Phase 2: Count total after citeproc (for wordcountref)
  words = 0
  track_sections = false
  current_section = "Document"
  local el2 = pandoc.utils.citeproc(el)
  count_blocks(el2.blocks)
  wordsall = words

  -- Phase 3: Count References section from citeproc-enhanced blocks
  current_section = "Document"
  count_reference_section(el2.blocks)

  -- Restore pre-citeproc word count for text replacement
  words = wordsbody

  -- Phase 4: Replace {{wordcount}}/{{wordcountref}} in body
  local updated_blocks = pandoc.walk_block(pandoc.Div(el.blocks), add_count_body)

  -- Phase 5: Replace {{wordcount}} in metadata
  add_count_meta(el.meta)

  -- Phase 6: Print section word counts
  quarto.log.output('-------------------------')
  quarto.log.output("📊 Word Count by Section:")
  local section_sum = 0
  for _, section in ipairs(section_order) do
    local count = words_by_section[section] or 0
    section_sum = section_sum + count
    quarto.log.output(string.format("  • %s: %d words", section, count))
  end
  quarto.log.output('-------------------------')

  return pandoc.Pandoc(updated_blocks, el.meta)
end
