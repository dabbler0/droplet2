exports.Stack = class Stack
  constructor: ->
    @head = null

  top: ->
    if @head?
      return @head.data
    else
      return null

  pop: ->
    if @head?
      result = @head.data
      @head = @head.next
      return result
    else
      return null

  push: (data) ->
    @head = {data, next: @head}
    return true

  clear: ->
    @head = null
