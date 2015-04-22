model = require './model.coffee'
assert = require 'assert'

simpleParse = (text) ->
  context = new model.Context()
  context.push new model.NewlineToken()
  stack = []; lastText = ''
  for char, i in text
    container = null

    if char in '[('
      context.push new model.TextToken lastText
      lastText = char
    else if char in '{})]'
      context.push new model.TextToken lastText + char
      lastText = ''
    else if char is '\n' and lastText.length > 0
      context.push new model.TextToken lastText
      lastText = ''
    else unless char is '\n'
      lastText += char

    switch char
      when '['
        container = new model.Block()
      when '('
        container = new model.Socket()
      when '{'
        container = new model.Indent('')
      when ']', ')', '}'
        context.push stack.pop()
      when '\n'
        context.push new model.NewlineToken()

    if container?
      context.push container.start
      stack.push container.end

  if lastText.length > 0
    context.push new model.TextToken lastText

  return context

context = simpleParse '''
[if ([(a) is (b)]) {
  [do (something)]
  [do ([something (else)])]
}]
'''

console.log 'IDENTITY:'
console.log context.list.stringify()

# Remove [do (something)]
context.cleanRemove new model.DropletLocation(1, 0, 'start:block'), new model.DropletLocation(1, 19, 'end:block')

console.log 'REMOVED LINE 1:'
console.log context.list.stringify()

console.log 'UNDO STACK:'
console.log context.undoStack.head
console.log context.list.locate(context.undoStack.head.data.start)

context.undo()
console.log 'UNDO, SHOULD RETURN:'
console.log context.list.stringify()
