words = 0
footnote_words = 0
counting_footnotes = true
words_by_section = {}
section_order = {}
current_section = "Document"
track_sections = true

-- Config toggles (defaults)
count_code_blocks = true
count_inline_code = true

-- Check if a section already exists
function section_exists(name)
  for _, sec in ipairs(section_order) do
    if sec.title == name then return true end
  end
  return false
end

-- Count words in inline elements
function count_inlines(inlines)
  for _, el in ipairs(inlines) do
    if el.t == "Str" and el.text:match("%P") then
      words = words + 1
      if track_sections then
        words_by_section[current_section] = (words_by_section[current_section] or 0) + 1
      end

    elseif el.t == "Code" and count_inline_code then
      local _, n = el.text:gsub("%S+", "")
      words = words + n
      if track_sections then
        words_by_section[current_section] = (words_by_section[current_section] or 0) + n
      end

    elseif el.t == "Note" then
      -- Count words in footnote content
      local saved_words = words
      count_blocks(el.content)
      if counting_footnotes then
        footnote_words = footnote_words + (words - saved_words)
      end
    end
  end
end

-- Count words in block elements and update section context
function count_blocks(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level <= 3 then
      current_section = pandoc.utils.stringify(block.content)
      if track_sections and not section_exists(current_section) then
        table.insert(section_order, { title = current_section, level = block.level })
      end

    elseif block.t == "Para" or block.t == "Plain" then
      count_inlines(block.content)

    elseif block.t == "CodeBlock" and count_code_blocks then
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

-- Count the references section (from a Div with class 'references')
function count_reference_section(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and block.attr and block.attr.classes then
      for _, class in ipairs(block.attr.classes) do
        if class == "references" then
          local ref_section = "References"
          if not section_exists(ref_section) then
            table.insert(section_order, { title = ref_section, level = 1 })
          end

          local saved_words = words
          local saved_track = track_sections

          track_sections = true
          words = 0 -- avoid adding to total
          current_section = ref_section
          count_blocks(block.content)
          words_by_section[ref_section] = words

          track_sections = saved_track
          words = saved_words
        end
      end
    end
  end
end

-- Truncate and pad section names for alignment
function format_section_name(name, max_length)
  local truncated = string.sub(name, 1, max_length)
  if string.len(name) > max_length then
    truncated = string.sub(truncated, 1, max_length - 3) .. "..."
  end
  return string.format("%-" .. max_length .. "s", truncated)
end

-- Replace {{wordcount}} and {{wordcountref}} in metadata
local function add_count_meta(meta, totalwords)
  for key, val in pairs(meta) do
    local stri = pandoc.utils.stringify(val)
    if string.find(stri, "{{wordcount}}") then
      meta[key] = stri:gsub("{{wordcount}}", totalwords)
    end
    if string.find(stri, "{{wordcountref}}") then
      meta[key] = stri:gsub("{{wordcountref}}", wordsall or totalwords)
    end
  end
end

-- Replace placeholders in document body
function make_add_count_body(totalwords)
  return {
    Str = function(el)
      if el.text == "{{wordcount}}" then
        el.text = tostring(totalwords)
      elseif el.text == "{{wordcountref}}" then
        el.text = tostring(wordsall)
      end
      return el
    end
  }
end

function Pandoc(el)
  -- Read user options from YAML
  if el.meta.wordcount then
    local wc_meta = el.meta.wordcount
    if wc_meta["count-code-blocks"] ~= nil then
      count_code_blocks = pandoc.utils.stringify(wc_meta["count-code-blocks"]) ~= "false"
    end
    if wc_meta["count-inline-code"] ~= nil then
      count_inline_code = pandoc.utils.stringify(wc_meta["count-inline-code"]) ~= "false"
    end
  end

  -- Phase 1: Count words before citeproc
  words = 0
  words_by_section = {}
  section_order = {}
  current_section = "Document"
  track_sections = true
  count_blocks(el.blocks)
  local totalwords = words -- this is for {{wordcount}}
  counting_footnotes = false

  -- Phase 2: Count post-citeproc for {{wordcountref}}
  words = 0
  track_sections = false
  current_section = "Document"
  local el2 = pandoc.utils.citeproc(el)
  count_blocks(el2.blocks)

  -- Phase 3: Count references (for display only, not total)
  count_reference_section(el2.blocks)
  wordsall = words -- this is for {{wordcountref}}

  -- Phase 4: Replace placeholders in body text
  local updated_blocks = pandoc.walk_block(pandoc.Div(el.blocks), make_add_count_body(totalwords))

  -- Phase 5: Replace placeholders in metadata
  add_count_meta(el.meta, totalwords)

  -- Phase 6: Log section counts
  quarto.log.output('----------------------------------------')
  quarto.log.output("📊 Word Count by Section:")
  local section_sum = 0
  local cumulative_count = 0
  for _, sec in ipairs(section_order) do
    local title = sec.title
    local level = sec.level or 1
    local count = words_by_section[title] or 0
    section_sum = section_sum + count
    cumulative_count = cumulative_count + count
    local indent = string.rep("  ", level - 1)
    local indent_length = string.len(indent)
    local available_space = 20 - indent_length - 2
    local formatted_title = format_section_name(title, available_space)
    local total_prefix_length = indent_length + 2 + available_space
    local padding = string.rep(" ", 22 - total_prefix_length)
    quarto.log.output(string.format("%s• %s%s: %4d words (cumulative: %5d)", indent, formatted_title, padding, count, cumulative_count))
  end
  quarto.log.output('----------------------------------------')
  quarto.log.output(string.format("📝 Footnote words: %d", footnote_words))
  quarto.log.output('----------------------------------------')
  quarto.log.output(string.format("🔎 Total words: %d", wordsall))
  quarto.log.output('----------------------------------------')

  return pandoc.Pandoc(updated_blocks.content, el.meta)
end
