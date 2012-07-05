# **Occo**
# If you install Docco, you can run it from the command-line:
#
#     docco src/*.coffee
#
#### Main Documentation Generation Functions

# Generate the documentation for a source file by reading it in, splitting it
# up into comment/code sections, highlighting them for the appropriate language,
# and merging them into an HTML template.
generate_documentation = (source, callback) ->
  fs.readFile source, "utf-8", (error, code) ->
    throw error if error
    sections = parse source, code
    highlight source, sections, ->
      generate_html source, sections
      callback()

# Given a string of source code, parse out each comment and the code that
# follows it, and create an individual **section** for it.
# Sections take the form:
#
#     {
#       docs_text: ...
#       docs_html: ...
#       code_text: ...
#       code_html: ...
#     }
#
parse = (source, code) ->
  lines    = code.split '\n'
  sections = []
  language = get_language source
  has_code = docs_text = code_text = ''

  save = (docs, code) ->
    sections.push docs_text: docs, code_text: code

  for line in lines
    if line.match(language.comment_matcher) or line.match(language.mark_matcher)
      if has_code
        save docs_text, code_text
        has_code = docs_text = code_text = ''
      if line.match(language.spacer_matcher)
        docs_text += '---\n'
        docs_text += '###' + line.replace(language.spacer_matcher, '') + '\n'
      else if line.match(language.mark_matcher)
        docs_text += '###' + line.replace(language.mark_matcher, '') + '\n'
      else
        docs_text += line.replace(language.comment_matcher, '') + '\n'
    else
      has_code = yes
      code_text += line + '\n'
  save docs_text, code_text
  sections

# Highlights a single chunk of CoffeeScript code, using **Pygments** over stdio,
# and runs the text of its corresponding comment through **Markdown**, using
# [Showdown.js](http://attacklab.net/showdown/).
#
# We process the entire file in a single call to Pygments by inserting little
# marker comments between each section and then splitting the result string
# wherever our markers occur.
highlight = (source, sections, callback) ->
  language = get_language source
  pygments = spawn 'pygmentize', ['-l', language.name, '-f', 'html', '-O', 'encoding=utf-8,tabsize=2']
  output   = ''
  
  pygments.stderr.addListener 'data',  (error)  ->
    console.error error.toString() if error
    
  pygments.stdin.addListener 'error',  (error)  ->
    console.error "Could not use Pygments to highlight the source."
    process.exit 1
    
  pygments.stdout.addListener 'data', (result) ->
    output += result if result
    
  pygments.addListener 'exit', ->
    output = output.replace(highlight_start, '').replace(highlight_end, '')
    fragments = output.split language.divider_html
    for section, i in sections
      section.code_html = highlight_start + fragments[i] + highlight_end
      section.docs_html = showdown.makeHtml section.docs_text
    callback()
    
  if pygments.stdin.writable
    pygments.stdin.write((section.code_text for section in sections).join(language.divider_text))
    pygments.stdin.end()
  
# Once all of the code is finished highlighting, we can generate the HTML file
# and write out the documentation. Pass the completed sections into the template
# found in `resources/docco.jst`
generate_html = (source, sections) ->
  title = path.basename source
  dest  = destination source
  html  = docco_template {
    title: title, sections: sections, sources: sources, path: path, destination: destination
  }
  console.log "docco: #{source} -> #{dest}"
  fs.writeFile dest, html

#### Helpers & Setup

# Require our external dependencies, including **Showdown.js**
# (the JavaScript implementation of Markdown).
fs       = require 'fs'
path     = require 'path'
showdown = require('./../vendor/showdown').Showdown
{spawn, exec} = require 'child_process'

# Stores objective-c filetypes
languages = 
  '.h':
    name: 'objective-c', symbol: '//'
  '.m':
    name: 'objective-c', symbol: '//'

# Build out the appropriate matchers and delimiters for each language.
for ext, l of languages

  # Does the line begin with a comment?
  l.comment_matcher = new RegExp('^\\s*' + l.symbol + '\\s?')

  # Does the line begin with a pragma mark?
  l.mark_matcher = new RegExp('^#pragma mark.*')

  # Does the pragma mark line contain a spacer?
  l.spacer_matcher = new RegExp('^#pragma mark ?-')

  # The dividing token we feed into Pygments, to delimit the boundaries between
  # sections.
  l.divider_text = '\n' + l.symbol + 'DIVIDER\n'

  # The mirror of `divider_text` that we expect Pygments to return. We can split
  # on this to recover the original sections.
  # Note: the class is "c" for Python and "c1" for the other languages
  l.divider_html = new RegExp('\\n*<span class="c1?">' + l.symbol + 'DIVIDER<\\/span>\\n*')

# Get the current language we're documenting, based on the extension.
get_language = (source) -> languages[path.extname(source)]

# Compute the destination HTML path for an input source file path. If the source
# is `lib/example.coffee`, the HTML will be at `docs/example.html`
destination = (filepath) ->
  'docs/' + path.basename(filepath) + '_' + path.extname(filepath).replace('.', '') + '.html'

# Ensure that the destination directory exists.
ensure_directory = (dir, callback) ->
  exec "mkdir -p #{dir}", -> callback()

# Micro-templating, originally by John Resig, borrowed by way of
# [Underscore.js](http://documentcloud.github.com/underscore/).
template = (str) ->
  new Function 'obj',
    'var p=[],print=function(){p.push.apply(p,arguments);};' +
    'with(obj){p.push(\'' +
    str.replace(/[\r\t\n]/g, " ")
       .replace(/'(?=[^<]*%>)/g,"\t")
       .split("'").join("\\'")
       .split("\t").join("'")
       .replace(/<%=(.+?)%>/g, "',$1,'")
       .split('<%').join("');")
       .split('%>').join("p.push('") +
       "');}return p.join('');"

# Create the template that we will use to generate the Docco HTML page.
docco_template  = template fs.readFileSync(__dirname + '/../resources/docco.jst').toString()

# The CSS styles we'd like to apply to the documentation.
docco_styles    = fs.readFileSync(__dirname + '/../resources/docco.css').toString()

# The start of each Pygments highlight block.
highlight_start = '<div class="highlight"><pre>'

# The end of each Pygments highlight block.
highlight_end   = '</pre></div>'

# Run the script.
# For each source file passed in as an argument, generate the documentation.
sources = process.argv.sort()
if sources.length
  ensure_directory 'docs', ->
    fs.writeFile 'docs/docco.css', docco_styles
    files = sources.slice(0)
    next_file = -> generate_documentation files.shift(), next_file if files.length
    next_file()

