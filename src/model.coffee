helper = require './helper.coffee'
{SplayList} = require 'splaylist'

# THE LAYERS
#
# Context -- deals with the undo stack and whitespace management
# Segment -- deals with parenting and interfaces locations
# List -- underlying data structure connecting Tokens
# Nodes -- Droplet tree containing Tokens
# Tokens -- immutable data

# ## Context
# A Context is what other modules with interact with.
class Context
  constructor: (@document) ->
    @undoStack = new helper.Stack()
    @redoStack = new helper.Stack()

  record: (operation) ->
    @undoStack.push operation
    @redoStack.clear()

  # ### Insert
  # Inserts the given list _after_ the given location token, and logs
  # an undo operation about it.
  # ```
  # A A A A A
  #     ^ B B B
  # A A A B B B A A
  # ```
  insert: (location, list) ->
    @document.insert location, list
    @record {
      type: 'insert'

      insertLocation: @document.get(location).locate()
      list: list.clone()

      startLocation: list.first().locate()
      endLocation: list.last().locate()
    }

  # ### Remove
  # Removes the given start location and end location, inclusive, and logs
  # an undo operation about it. Returns the removed list.
  # ```
  # A B C D E F G
  #     ^     ^
  # Becomes A B G
  # Returns C D E F
  # ```
  remove: (startLocation, endLocation) ->
    reinsertLocation = @document.get(startLocation).prev().locate()
    removed = @document.remove startLocation, endLocation
    @record {
      type: 'remove'

      startLocation: startLocation
      endLocation: endLocation

      insertLocation: reinsertLocation
      list: removed.clone()
    }

  # Undo
  undo: ->
    operation = @undoStack.pop()

    if operation.type is 'remove'
      place = @document.get(operation.startLocation).prev().handle
      @document.insert place, operation.list.clone()
    else if operation.type is 'insert'
      @document.remove operation.startLocation, operation.endLocation

    @redoStack.push operation

  # Redo
  redo: ->
    operation = @undoStack.pop()

    if operation.type is 'remove'
      @document.remove operation.startLocation, operation.endLocation
    else if operation.type is 'insert'
      @document.insert operation.startLocation, operation.list.clone()

    @undoStack.push operation

  # Stringify
  stringify: -> @document.stringify()

class DropletLocation
  constructor: (
    @row = 0
    @col = 0
    @type = null
    @length = null
  ) ->

# ## Segment
# A Segment is a list of DropletLeaf objects, which can
# look them up by any of the order statistics:
#   - string length
#   - line number
#   - number of tokens
#
# It can be spliced into or out of other Segments.
#
# TODO update this to a SplayList
exports.Segment = class Segment
  constructor: (@list = new DropletList()) ->

  # TODO linked-list stub
  get: (location) ->
    if location instanceof DropletHandle
      return location.data

    head = @list.first(); row = (if head instanceof NewlineToken then 1 else 0)

    until row is location.row
      head = head.next()
      if head instanceof NewlineToken
        row += 1

    if head instanceof NewlineToken
      col = head.stringify().length - 1
    else
      col = head.stringify().length

    until col >= location.col
      head = head.next()
      col += head.stringify().length

    # If _we_ were the one who made the length equal,
    # move over; locations always refer to the _start_ of the token.
    if col is location.col and head.stringify().length > 0
      head = head.next()

    if location.length?
      until (head.container ? head).stringify().length is location.length
        head = head.next()

    if location.type?
      until head.type is location.type
        head = head.next()

    return head

  # TODO linked-list stub
  insert: (location, segment) ->
    token = @get(location)

    if token instanceof StartToken
      segment.setParent token.container
    else
      segment.setParent token.parent

    handle = token.handle
    @list.insert(handle, segment.list)

  # TODO linked-list stub
  remove: (startLocation, endLocation) ->
    start = @get(startLocation)
    end = @get(endLocation)

    # Make sure the tree is still valid
    if start.parent isnt end.parent
      throw new RangeError 'Attempted to remove an invalidly parented segment'

    startHandle = start.handle
    endHandle = end.handle

    result = new Segment(@list.remove(startHandle, endHandle))
    result.setParent null

    return result

  # TODO linked-list stub
  shallowEach: (fn) ->
    head = @list.first()
    while head?
      if head instanceof StartToken
        fn head.container
        head = head.container.end
      else
        fn head
        head = head.next()

  deepEach: (fn) ->
    head = @list.first()
    while head?
      fn head
      head = head.next()

  # TODO linked-list stub
  clone: ->
    stack = new helper.Stack()
    list = new DropletList()
    @deepEach (node) ->
      if node instanceof StartToken
        container = node.container.clone()
        container.setParent stack.top()
        list.append container.start
        stack.push container
      else if node instanceof EndToken
        list.append stack.pop().end
      else
        clone = node.clone()
        clone.setParent stack.top()
        list.append clone
    return new Segment list

  stringify: ->
    string = ''
    @deepEach (node) ->
      string += node.stringify()
    return string

  setParent: (parent) ->
    @shallowEach (node) ->
      node.setParent parent

  serialize: -> "{#{@list.serialize()}}"

  first: -> @list.first()
  last: -> @list.last()

  append: (token) ->
    last = @last()
    if last? and not (token instanceof EndToken)

      if last instanceof StartToken
        parent = last.container
      else
        parent = last.parent

      if token instanceof StartToken
        token.container.setParent parent
      else
        token.setParent parent

    else
      token.parent = null
    @list.append token

class DropletList
  constructor: (@head = null, @tail = null) ->

  insert: (handle, list) ->
    handle.next.prev = list.tail; list.tail.next = handle.next
    handle.next = list.head; list.head.prev = handle

  remove: (startHandle, endHandle) ->
    if startHandle.prev?
      startHandle.prev.next = endHandle.next
    if endHandle.next?
      endHandle.next.prev = startHandle.prev

    startHandle.prev = endHandle.next = null

    result = new DropletList(startHandle, endHandle)

  append: (data) ->
    if data instanceof DropletList
      if @head is @tail is null
        @head = data.head; @tail = data.tail
      else
        @tail.next = data.head; data.head.prev = @tail
        @tail = data.tail
    else
      if @head is @tail is null
        @head = @tail = new DropletHandle data
      else
        handle = new DropletHandle data
        @tail.next = handle; handle.prev = @tail
        @tail = handle

  first: -> @head?.data ? null
  last: -> @tail?.data ? null

  # Validate that this is indeed a linked list
  valid: ->
    if @head.prev? or @tail.next?
      return false

    tortoise = @head
    hare = @head.next

    while tortoise?
      # Check asymmetric linkage
      if tortoise.next? and tortoise.next.prev isnt tortoise
        return false

      tortoise = tortoise.next
      if hare? then hare = hare.next
      if hare? then hare = hare.next

      # Check infinite loops (Floyd's cycle-finding algorithm)
      if hare? and tortoise is hare
        return false

    return true

  serialize: ->
    head = @head; str = head.serialize()
    until head is @tail
      head = head.next
      str += ',' + head.serialize()
    return str

class DropletHandle
  constructor: (@data) ->
    @data.handle = @
    @prev = @next = null

  locate: ->
    location = new DropletLocation(); head = @.prev

    location.type = @data.type
    if @data instanceof StartToken
      location.length = @data.container.stringify().length
    else
      location.length = @data.stringify().length

    until (not head?) or head.data instanceof NewlineToken
      location.col += head.data.stringify().length
      head = head.prev
    if head?
      location.col += head.data.stringify().length - 1

    while head?
      if head.data instanceof NewlineToken
        location.row += 1
      head = head.prev

    return location

  serialize: -> '[' + @data.serialize() + ']'

class Node
  constructor: (@parent) ->

  clone: ->

  setParent: (parent) -> @parent = parent

class Container extends Node
  constructor: (@parent) ->
    @start = new StartToken @
    @end = new EndToken @
    @_id = Container._id++

  stringify: ->
    head = @start
    string = head.stringify()
    until head is @end
      head = head.next()
      string += head.stringify()
    return string

  clone: -> new Container()

  setParent: (@parent) ->
    @start.parent = @end.parent = @parent

  serialize: -> "Container(#{@_id})"

Container._id = 0

class Token extends Node
  constructor: (@parent) ->

  # All Leaf objects can traverse forward and backward
  # like linked list elements; this may delegate to associated SplayList
  # Location objects.
  next: -> @handle.next?.data
  prev: -> @handle.prev?.data

  # TODO stub
  getIndent: -> ''

  stringify: -> ''

  locate: -> @handle.locate()

  serialize: -> 'Token'

class StartToken extends Token
  constructor: (@container) ->
    @parent = @container.parent
    @type = 'StartToken'

  serialize: -> "StartToken(#{@container._id})"

class EndToken extends Token
  constructor: (@container) ->
    @parent = @container.parent
    @type = 'EndToken'

  serialize: -> "EndToken(#{@container._id})"

class TextToken extends Token
  constructor: (@value, @parent = null) ->
    @type = 'TextToken'

  stringify: -> @value

  clone: -> new TextToken @value

  serialize: -> "TextToken(#{@value})"

class NewlineToken extends Token
  constructor: (@specialIndent = null, @parent = null) ->
    type = 'NewlineToken'

  stringify: -> '\n' + (@specialIndent ? @getIndent())

  clone: -> new NewlineToken @specialIndent

  serialize: -> "NewlineToken(#{@specialIndent ? ''})"

exports.Context = Context
exports.Segment = Segment
exports.Location = DropletLocation

exports.tokens = {Token, TextToken, NewlineToken}
exports.containers = {Container}

exports.__internals = {DropletList, Node}
