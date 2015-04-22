{SplayList} = require 'splaylist'
{Stack} = require './helper.coffee'

###
BASIC ARCHITECTURE NOTES:
```
Context
   |
   V
DropletList
   |
   V
Data types
```

**Context**
Cleanly deals with Droplet mutations. Keeps an undo stack
and has the concept of a cursor.

**DropletList**
Deals with locating and getting locations for data elements, and
makes sure that parent is good at construction time (parenting is not
guaranteed after mutations; that is Context's responsibility).

**Data types**
These do not mutate themselves. They contain static information about
the document and its markup.
###

###
Context
###

# # Context
# An editing context for a Droplet document
#
# A context contains:
#   - A document
#   - An undo stack
#   - A cursor
#
# A context knows how to:
#   - Do splices with proper whitespace, undo stack management, and reparenting
#   - Undo and redo
#   - Move the cursor properly
exports.Context = class Context
  constructor: ->
    @list = new DropletList()
    @undoStack = new Stack()
    @redoStack = new Stack()
    @cursor = {
      row: 0
      char: 0
      n: 0
    }

  push: (token) -> @list.push token

  validateRemovalSegment: (startLoc, endLoc) -> startLoc.val().parent is endLoc.val().parent

  # ## remove and insert
  # Raw changes with undo logs
  remove: (start, end) ->
    # Clear the redo stack
    unless @redoStack.empty
      @redoStack = new Stack()

    # Validate the selection. A selection
    # must be at only one tree level to be removed.
    startLoc = @list.locate start
    endLoc = @list.locate end

    startLocation = @list.location startLoc
    endLocation = @list.location endLoc.next()

    unless @validateRemovalSegment startLoc, endLoc
      throw new RangeError 'Attempted to remove an illegal segment'

    # Remove and remember the segment.
    # spliceList includes first but not last; our convention is
    # to include last but not first, so we need to shift everything
    # by one.
    segment = @list.spliceList(startLoc.next(), endLoc.next(), null)

    # Deparent the segment
    segment.setParent null

    # Add an undo operation
    @undoStack.push new RemoveOperation startLocation, segment.clone(), endLocation

    # Return the removed segment
    return segment

  insert: (start, segment) ->
    unless segment instanceof DropletList
      segment = new DropletList segment

    # Clear the redo stack
    unless @redoStack.empty
      @redoStack = new Stack()

    # Remember the last node for later location retrieval
    lastNode = segment.last()

    # Enparent the segment
    segment.setParent start.parent

    # Insert the segment
    @list.spliceList start, 0, segment

    # Add the undo operation
    @stack.push new InsertOperation start, segment.clone(), @list.location(lastNode)

    return null

  # ## cleanRemove and cleanInsert
  # These deal with whitespace. As a rule, when doing normal editing,
  # we always remove all whitespace preceding a segment,
  # and insert one newline where necessary.
  #
  # Additionally, for convenience, cleanRemove is inclusive.
  cleanRemove: (start, end) ->
    startLoc = @list.locate start
    endLoc = @list.locate end

    # Back up to swallow all whitespace before our first token
    while startLoc.prev().val().isNewline
      startLoc = startLoc.prev()

    # Raw remove is not inclusive, so back up one more
    startLoc = startLoc.prev()

    # Actually remove
    removedSegment = @remove startLoc, end

    # Make sure that we never leave an empty indent;
    # if the indent is now empty, insert a newline token.
    if startLoc.next().val() is startLoc.val().container?.end and
        startLoc.val().container instanceof Indent
      @insert startLoc, [new NewlineToken()]

    return removedSegment

  cleanInsert: (start, segment) ->
    startLoc = @list.locate start
    startToken = startLoc.val()

    # Insert a newline if necessary. This is necessary
    # if there is not already a newline there, and we
    # are inserting into something with an indent
    # as a parent.
    unless startToken.isNewline or
        (not startToken.parent instanceof Indent) or
        segment.first().val().isNewline
      segment.unshift new NewlineToken()

    # The do the raw insert
    @insert start, segment

  # ## undo and redo
  # Pop from the undo/redo stacks
  # and perform the operations
  undo: ->
    unless @undoStack.empty
      operation = @undoStack.pop()
      @opBackward operation
      @redoStack.push operation

  redo: ->
    unless @redoStack.empty
      operation = @redoStack.pop()
      @opForward operation
      @undoStack.push operation

  # ## opForward and opBackward
  # Perform InsertOperations and RemoveOperations
  opForward: (operation) ->
    if operation instanceof InsertOperation
      @list.spliceList operation.start, 0, operation.segment
    else if operation instanceof RemoveOperation
      @list.spliceList operation.start.next(), operation.end.next(), null

  opBackward: (operation) ->
    if operation instanceof InsertOperation
      @list.spliceList operation.start.next(), operation.end.next(), null
    else if operation instanceof RemoveOperation
      @list.spliceList @list.locate(operation.start), 0, operation.segment

# # Undo Operations
class Operation
  constructor: ->

class RemoveOperation extends Operation
  constructor: (@start, @segment, @end) ->

class InsertOperation extends Operation
  constructor: (@start, @segment, @end) ->

###
DropletList
###

# # DropletLocation
# Shell struct for a location object in Droplet.
exports.DropletLocation = class DropletLocation
  constructor: (@row, @col, @type, @length) ->

# # DropletList
# A subclass of SplayList which also knows
# how to deal with the Droplet tree and location scheme.
#
# DropletList is responsible for:
#   - location serialization and lookup
#   - conversion from Droplet tree to a string
#   - managing basic Droplet tree parenting
class DropletList extends SplayList
  constructor: (arr) ->
    @_root = null

    # Can construct from array
    if arr?
      @push el for el, i in arr

  spliceList: (first, limit, insert) ->
    super first, limit, insert, new DropletList()

  # Override "push" to properly do Droplet
  # parent tree
  push: (node) ->
    node.parent ?= @last()?.parent
    if node instanceof StartToken
      node.container.parent = node.parent
    super node

  # Droplet stringify
  stringify: (start = @first(), end = @last()) ->
    string = ''
    indent = ''
    until start is end
      tok = start.val()
      switch tok.type
        when 'text'
          string += tok.value
        when 'newline'
          string += '\n' + (tok.special ? indent)
        when 'start:indent'
          indent += tok.container.prefix
        when 'end:indent'
          indent = indent[...-tok.container.prefix.length]
      start = start.next()
    return string

  # ## setParent
  # Set the parent of everything at the root level of this segment.
  setParent: (parent) ->
    # Iterate from start to end
    head = @first()
    tail = @last()
    until head is tail or head is null
      console.log @stat('n', head), @stat('n', tail)
      tok = head.val()

      # If the token we're at is the start of
      # a container, set the container parent and
      # skip to the end of the container
      # instead.
      #
      # We do not set any parents of start tokens of containers,
      # because those parents are always the containers themselves
      # and will not change if this segment is splice in somewhere.
      if tok instanceof StartToken
        tok = tok.container.end
        tok.container.parent = parent
        head = tok.loc

      # Set the parent of whatever token we landed on.
      tok.parent = parent
      head = head.next()

    tail.val().parent = parent

  # ## clone
  clone: ->
    clone = new DropletList()

    # Stack to keep track of cloned container objects
    stack = []

    @each (loc) ->
      tok = loc.val()

      # When we clone a start token, create a corresponding
      # end token and add it to the stack,
      # so that end tokens can match up with corresponding
      # start tokens when popped.
      if tok instanceof StartToken
        container = tok.container.clone()
        clone.push container.start
        stack.push container.end

      # Instead of cloning an end token, just pop from the stack
      else if tok instanceof EndToken
        clone.push stack.pop()

      # Everything else is simple.
      else
        clone.push tok.clone()

    return clone

  # ## orderstats
  # Standard SplayList orderstats override to count
  # string length and newlines.
  orderstats: (V, X, L, R) ->
    # Init to V's values
    n = 1
    strlen = V.getStringRepresentation().length # TODO this is not used.
    newlines = (if V.isNewline then 1 else 0)

    # Add L and R
    if L isnt null
      n += L.n; strlen += L.strlen; newlines += L.newlines
    if R isnt null
      n += R.n; strlen += R.strlen; newlines += R.newlines

    # Store in X
    X.n = n; X.strlen = strlen; X.newlines = newlines

  # ## locate
  # Given a Droplet location object:
  # {
  #   row: int
  #   col: int
  #   length: int # length of string representation
  #   type: str # type of token
  # }
  # Find the corresponding token.
  locate: (location) ->
    if location instanceof SplayList.Location
      return location

    else if location instanceof DropletLocation
      # Get to the row
      head = @find 'newlines', location.row

      # Advance until column condition is fulfilled
      length = head.val().getStringRepresentation().length
      head = head.next()
      until length >= location.col or
            head.val().isNewline
        length += head.val().getStringRepresentation().length
        head = head.next()

      # Advance until length and type conditions are fulfilled.
      # We may be looking for a start/end token for a
      # container of a certain length
      if location.length? and (/(start|end).*/.exec(location.type)?)
        until head.val().type is location.type and
            @stringify(head, head.val().conatiner.end.loc).length is location.length
          head = head.next()

      # Or we may be looking for a text/newline token with a certain length
      else if location.length?
        until head.val().getStringRepresentation().length is location.length
          head = head.next()

      # Or we may not have length info
      else
        until head.val().type is location.type or
              head.val().isNewline
          head = head.next()
      return head
    else
      throw new RangeError location + ' is not a location'

  location: (node) ->
    row = @stat('newlines', node) - 1

    # Find the starting newline of this line
    # and see how many characters away we are
    # from it.
    head = @find('newlines', row)
    col = head.val().getStringRepresentation().length # (include indent)
    until head is node
      head = head.next()
      col += head.val().getStringRepresentation().length

    type = node.val().type

    # Get the string representation of this node length
    if /(start|end).*/.exec(node.val().type)?
      container = node.val().container
      length = @stringify(container.start.loc, container.end.loc)#.length
    else
      length = node.val().getStringRepresentation().length

    # Return all this info.
    return new DropletLocation row, col, type, length # TODO as above

# # IdObject
# Simple class for assign object ids
class IdObject
  constructor: ->
    @id = IdObject.id++

IdObject.id = 0

# # The Data Objects
# These are the elements of the Droplet tree and the data
# that is stored in the DropletList. They hold info on the
# actual content of the document and its markup.
#
# As a rule, these classes should not have mutator functions, nor
# should their data ever change after parse-time.

exports.DropletNode = class DropletNode extends IdObject
  constructor: ->
    @parent = null

# ## Container
# A Container is not attached to a location, instead
# pointing to two different nodes which are its start and end.
#
# A Container can have children in the Droplet tree.
exports.Container = class Container extends DropletNode
  constructor: (@type = 'container')->
    super

    @start = new StartToken @
    @start.type += ':' + @type

    @end = new EndToken @
    @end.type += ':' + @type

# ### The types of containers
exports.Indent = class Indent extends Container
  constructor: (@prefix) ->
    super 'indent'

  clone: -> new Indent @prefix

exports.Block = class Block extends Container
  constructor: (@lotsofargs) -> # TODO arguments
    super 'block'

  clone: -> new Block @lotsofargs

exports.Socket = class Socket extends Container
  constructor: (@lotsofargs) -> # TODO arguments
    super 'socket'

  clone: -> new Socket @lotsofargs

# ## Token
# A Token is a piece of data attached to a location.
# Tokens cannot have children.
exports.Token = class Token extends DropletNode
  constructor: ->
    super
    @location = null

  # ### getIndent
  # Travel up the parent tree to find
  # what the indent prefix should be on the line on
  # which this token is.
  getIndent: ->
    head = @; indent = ''
    while head?
      if head instanceof Indent
        indent += head.prefix
      head = head.parent
    return indent

  getStringRepresentation: -> ''

# ## The types of tokens
# StartToken and EndToken, which have to do with Containers;
# TextToken, which contains a string, and NewlineToken, which contains
# a newline and possibly some whitespace.
exports.StartToken = class StartToken extends Token
  constructor: (@container) ->
    super
    @parent = @container
    @type = 'start'

exports.EndToken = class EndToken extends Token
  constructor: (@container) ->
    super
    @parent = @container.parent
    @type = 'end'

exports.TextToken = class TextToken extends Token
  constructor: (@value) ->
    @super
    @isText = true
    @type = 'text'

  clone: -> new TextToken @value

  getStringRepresentation: -> @value

exports.NewlineToken = class NewlineToken extends Token
  constructor: (@special = null) ->
    @isNewline = true
    @type = 'newline'

  clone: -> new NewlineToken @special

  getStringRepresentation: -> '\n' + (@special ? @getIndent())
