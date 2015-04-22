strmul = (a, b) ->
  result = ''
  for i in [0...b]
    result += a
  return result

class IdObject
  constructor: ->
    @_id = IdObject.id++
IdObject.id = 0

# # Tree
# A context for interfacing with TreeNodes
exports.Tree = class Tree
  constructor: (@countFunctions) ->
    @ncounts = @countFunctions.length
    @root = @head = new LeafNode null, (0 for [0...@ncounts])

  # ## append
  append: (data) ->
    # Compute the access counts
    counts = (fn data for fn, i in @countFunctions)
    # Insert it into the tree
    @root = @root.append new LeafNode data, counts
    return null

  # ## get, splice and insert
  # Simple wrappers for the corresponding TreeNode
  # methods that mutate the root instead of returning.
  get: (i, val) ->
    return @root.get i, val

  splice: (a, b) ->
    [@root, result] = @root.splice a, b
    return result

  insert: (node, tree) ->
    @root = @root.insert node, tree
    return null

# # TreeNode
# A node in the splayish tree
exports.TreeNode = class TreeNode extends IdObject
  constructor: (@ncounts, @parent = null, @left = null, @right = null) ->
    super
    @counts = (0 for [0...@ncounts])
    @weight = 0
    @first = @last = null

    # Get the first and last leaves
    @first = @left?.first ? @right?.first
    @last = @right?.last ? @left?.last

    # Assign parenting
    @left?.parent = @right?.parent = @

    # Take cumulative sum of children
    @add @left; @add @right

  # ## add
  # Add a child to cumulative counts
  add: (other) ->
    if other?
      @counts[i] += el for el, i in other.counts
      @weight += other.weight

  flagDelete: ->
    @deleted = true

  # ## Flip
  # This operation:
  # ```
  #      o
  #    /   \
  #   o      o
  #  / \    / \
  # A   B  C   D
  # ```
  # After flip on B, becomes
  # ```
  #     o
  #    / \
  #   A   o
  #      / \
  #     B   o
  #        / \
  #       C   D
  # ```
  #
  # Constant time.
  flip: ->
    unless @parent? and @parent.parent?
      throw new Error "Cannot flip nodes without grandparents"

    if (@ is @parent.left) is (@parent is @parent.parent.left)
      throw new Error "Can only flip inside nodes"

    if @ is @parent.right and @parent is @parent.parent.left
      # Move our left sibling up to the grandparent
      @parent.parent.left = @parent.left; @parent.left.parent = @parent.parent
      # Move to our destination
      @parent.parent.right = new TreeNode @ncounts, @parent.parent, @, @parent.parent.right
      @parent = @parent.parent.right

    else if @ is @parent.left and @parent is @parent.parent.right
      @parent.parent.right = @parent.right; @parent.right.parent = @parent.parent
      @parent.parent.left = new TreeNode @ncounts, @parent.parent, @parent.parent.left, @
      @parent = @parent.parent.left

    else
      throw new Error 'aaaaa'

  # ## Get
  # Access an element by its cumulative sum. Will also rebalance the tree
  # as it traverses it. Operates in O(log(n)).
  get: (i, val) ->
    # Rebalance our children to make them more equal in weight.
    # If our left child is heavier than our right child,
    # give some nodes to the right child; otherwise do the reverse.
    if @left.weight > @right.weight
      @left.right.flip()
    else if @right.weight > @left.weight
      @right.left.flip()

    # Then continue searching for the wanted node.
    if val > @left.counts[i]
      return @right.get i, val - @left.counts[i]
    else
      return @left.get i, val

  # ## Segregate
  # Rebalance so that the `index`th element
  # is the rightmost leaf under its child (so either
  # the rightmost leaf under the left child, or rightmost leaf under
  # the right child).
  #
  # For instance, if we start with:
  # ```
  #     o
  #    / \
  #   A   o
  #      / \
  #     B   o
  #        / \
  #       C   D
  # ```
  #
  # And we segregate at C, we want to end up with:
  # ```
  #       o
  #      / \
  #     o   D
  #    / \
  #   o   C
  #  / \
  # A   B
  # ```
  #
  # We do this by recursing: we tell the right child to segregate,
  # which tells its right child to segregate, ultimately looking like this:
  # ```
  #   o
  #  / \
  # C   D
  # ```
  #
  # Then its parent flips C over to the other side:
  # ```
  #     o            o
  #    / \          / \
  #   B   o   =>   o   D
  #      / \      / \
  #     C   D    B   C
  # ```
  #
  # Then the root flips that whole tree over to the other side, giving
  # us the wanted result.
  #
  # O(log(n))
  #
  segregate: (index) ->
    if index < @left.weight
      isOnLeft = @left.segregate index
      @left.right.flip() if isOnLeft
      return true
    else
      isOnLeft = @right.segregate index - @left.weight
      if isOnLeft
        @right.left.flip()
        return true
      else
        return false

  # ## Cut
  # Segregates and destroys this tree. Returns
  # two subtrees, one with the given node and all the nodes
  # to the left of it, and one with all the nodes to the right
  # of the given nodes.
  cut: (leaf) ->
    @segregate leaf.getIndex()
    @left.parent = @right.parent = null
    return [@left, @right]

  # ## Merge
  # Simple merge.
  merge: (other) ->
    return new TreeNode @ncounts, null, @, other

  # ## Splice
  splice: (a, b) ->
    [left, center] = @cut a
    [center, right] = center.cut b
    result = left.merge right
    return [result, center]

  # ## Insert
  insert: (node, tree) ->
    [left, right] = @cut node
    return left.merge(tree).merge right

  # ## Append
  append: (node) ->
    @parent = new TreeNode @ncounts, null, @, node
    node.parent = @parent
    if @last?
      node.prev = @last; @last.next = node
    @last = node
    return @parent

# # LeafNode
exports.LeafNode = class LeafNode extends TreeNode
  constructor: (@data, @counts, @prev = null, @next = null, @parent = null) ->
    @ncounts = @counts.length
    @weight = 1
    @first = @last = @

  # ## setCount
  # Set a data count and propagate up
  setCount: (i, val) ->
    diff = val - @counts[i]
    head = @

    while head?
      head.counts[i] += diff
      head = head.parent

  get: -> @

  # ## getIndex
  getIndex: ->
    head = @; index = 0
    while head?
      if head.parent? and head is head.parent.right
        index += head.parent.left.weight
      head = head.parent
