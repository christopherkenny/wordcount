-- this chunk is modified by deleting out non-word counter information from
-- https://github.com/pandoc/lua-filters/blob/master/wordcount/wordcount.lua
words = 0
wordcount = {
  Str = function(el)
    -- we don't count a word if it's entirely punctuation:
    if el.text:match("%P") then
        words = words + 1
    end
  end,

  Code = function(el)
    _,n = el.text:gsub("%S+","")
    words = words + n
  end,

  CodeBlock = function(el)
    _,n = el.text:gsub("%S+","")
    words = words + n
  end
}

-- original meta thing. the element is called meta, then we can loop over elements
-- check if the `wordcount` variable is set to `process-anyway`
-- function Meta(meta)
--   if meta.wordcount and (meta.wordcount=="process-anyway"
--     or meta.wordcount=="process" or meta.wordcount=="convert") then
--       process_anyway = true
--   end
-- end

local function add_count_meta(meta)
  -- loop like so https://github.com/quarto-dev/quarto-cli/discussions/4042
  for key, val in pairs(meta) do
    -- convert val to string https://pandoc.org/lua-filters.html#pandoc.utils.stringify
    stri = pandoc.utils.stringify(val)
    -- lua str_detect = string.find https://www.lua.org/pil/20.1.html
    -- can't gsub a null thing, so this checks first and that's enough
    if string.find(stri, "{{wordcount}}") then
      meta[key] = stri:gsub("{{wordcount}}", words)
    end
    if string.find(stri, "{{wordcountref}}") then
      meta[key] = stri:gsub("{{wordcountref}}", wordsall)
    end
  end
  -- modified meta directly, so don't need to return it
end

add_count_body = {
  -- we only care if it's a Str type
  Str = function(el)
    -- it breaks on spaces 
    -- so use {{wordcount}} over  {{ wordcount }}
    -- then we can directly check for {{wordcount}} and replace w/ number
    if el.text == "{{wordcount}}" then
      el.text = words
    end
    if el.text == "{{wordcountref}}" then
      el.text = wordsall
    end
    -- return here because this is applied as a filter in walk_block
    return el
  end
}

function Pandoc(el)
    -- skip metadata, just count body:
    -- 1. tally count
    -- Could be either of these. The second seems simpler, but not sure the difference
    -- https://github.com/pandoc/lua-filters/blob/master/wordcount/wordcount.lua
    pandoc.walk_block(pandoc.Div(el.blocks), wordcount)

    -- other example https://pandoc.org/lua-filters.html#counting-words-in-a-document
    -- el.blocks:walk(wordcount)
    
    -- reset vars
    wordsbody = words
    words = 0
    
    -- proc cites
    el2 = pandoc.utils.citeproc(el)
    pandoc.walk_block(pandoc.Div(el2.blocks), wordcount)
    wordsall = words
    words = wordsbody
    
    -- 2. replace {{wordcount}} with words for body
    Str = pandoc.walk_block(pandoc.Div(el.blocks), add_count_body)

    -- 3. replace {{wordcount}} with words for metadata
    -- modifies the meta data directly, oop-like
    add_count_meta(el.meta)
    
    -- 4. return new pandoc object, with modified text `Str` and metadata `el.meta` 
    -- like in https://github.com/ute/search-replace/blob/main/_extensions/search-replace/search-replace.lua
    -- see also https://pandoc.org/lua-filters.html#type-pandoc
    return pandoc.Pandoc(Str, el.meta)
end