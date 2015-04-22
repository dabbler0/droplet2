# # Stack
# Simple stack implementation
class StackNode
  constructor: (@data, @next) ->

exports.Stack = class Stack
  constructor: ->
    @empty = true
    @head = null

  push: (data) ->
    @head = new StackNode data, @head
    @empty = false

  pop: ->
    data = @head.data
    @head = @head.next
    @empty = (@head is null)
    return data
