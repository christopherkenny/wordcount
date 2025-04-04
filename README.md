# Word Count Extension For Quarto

This extension *inserts* word counts into Quarto documents in the place of `{{wordcount}}`.
Word counts can be inserted in the body or metadata (YAML header) of a document.
To include the number of words in the references, use `{{wordcountref}}`.

You may also be interested in:

- [Andrew Heiss's Word Count Extension](https://github.com/andrewheiss/quarto-wordcount): this prints word counts by body/references to the log file.
- [Ben Marwick's wordcountaddin RStudio Addin](https://github.com/benmarwick/wordcountaddin): this provides a word count of a markdown document.

## Installing

```bash
quarto add christopherkenny/wordcount
```

This will install the extension under the `_extensions` subdirectory.
If you're using version control, you will want to check in this directory.

## Using

After installing:

- Add
  ```
  filters:
    - wordcount
  ```
  to the YAML header of your Quarto file
- Add `{{wordcount}}` or `{{wordcountref}}` in your document (without the \`tics\`). Make sure there are spaces around it.

For example you could write:
> There are {{wordcount}} words in this document.

and it will replace `{{wordcount}}` with its estimate.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

<!-- pdftools::pdf_convert('example.pdf',pages = 1) -->
![[example.qmd](example.qmd)](example_1.png) 

## Licensing

The original wordcount filter is licensed under a [MIT license to 2017-2021 pandoc Lua filters contributors](https://github.com/pandoc/lua-filters/blob/master/LICENSE).
This Quarto extension is also licensed under the MIT license.
