model = require '../src/model.coffee'
assert = require 'assert'

describe 'DropletList', ->
  it 'should be able to append tokens to construct a list', ->
    list = new model.__internals.DropletList()
    list.append new model.tokens.NewlineToken()
    list.append new model.tokens.TextToken 'hello'
    list.append new model.tokens.NewlineToken()

    assert list.valid()

    assert.equal list.serialize(),
      '[NewlineToken()],[TextToken(hello)],[NewlineToken()]'

  it 'should be able to insert another list in an arbitrary location', ->
    listA = new model.__internals.DropletList()
    listA.append new model.tokens.TextToken '1'
    listA.append new model.tokens.TextToken '2'
    listA.append new model.tokens.TextToken '3'

    listB = new model.__internals.DropletList()
    listB.append new model.tokens.TextToken '4'
    listB.append new model.tokens.TextToken '5'
    listB.append new model.tokens.TextToken '6'

    listA.insert listA.head.next, listB

    assert listA.valid()

    assert.equal listA.serialize(),
      '[TextToken(1)],[TextToken(2)],[TextToken(4)],[TextToken(5)],[TextToken(6)],[TextToken(3)]'

  it 'should be able to remove an arbitrary sublist', ->
    list = new model.__internals.DropletList()
    list.append new model.tokens.TextToken '1'
    list.append new model.tokens.TextToken '2'
    list.append new model.tokens.TextToken '3'
    list.append new model.tokens.TextToken '4'
    list.append new model.tokens.TextToken '5'

    start = list.head.next.next
    end = list.tail.prev

    list.remove start, end

    assert list.valid()

    assert.equal list.serialize(),
      '[TextToken(1)],[TextToken(2)],[TextToken(5)]'

describe 'Segment', ->
  describe 'Locations', ->
    it 'should be able to access a token based on a row/column location', ->
      segment = new model.Segment()
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'abc'
      segment.append new model.tokens.TextToken 'def'
      segment.append new model.tokens.TextToken 'ghi'
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'jkl'
      segment.append new model.tokens.TextToken 'mno'
      segment.append new model.tokens.TextToken 'pqr'
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'stu'
      segment.append new model.tokens.TextToken 'vwx'
      segment.append new model.tokens.TextToken 'yz0'

      location = new model.Location(
        2, 3
      )

      assert.equal segment.get(location).serialize(),
        'TextToken(mno)'

    it 'should be able to relocate a token using its generated location data', ->
      segment = new model.Segment()
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'abc'
      segment.append new model.tokens.TextToken 'def'
      segment.append new model.tokens.TextToken 'ghi'
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'jkl'
      segment.append new model.tokens.TextToken 'mno'
      segment.append new model.tokens.TextToken 'pqr'
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'stu'
      segment.append new model.tokens.TextToken 'vwx'
      segment.append new model.tokens.TextToken 'yz0'

      location = new model.Location(
        2, 3
      )

      relocation = segment.get(location).locate()
      assert.deepEqual relocation, {
        row: 2
        col: 3
        type: 'TextToken'
        length: 3
      }

      assert.equal segment.get(relocation).serialize(), segment.get(location).serialize()

    it 'should be able to remove arbitrary segments based on their location', ->
      segment = new model.Segment()
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'abc'
      segment.append new model.tokens.TextToken 'def'
      segment.append new model.tokens.TextToken 'ghi'
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'jkl'
      segment.append new model.tokens.TextToken 'mno'
      segment.append new model.tokens.TextToken 'pqr'
      segment.append new model.tokens.NewlineToken()
      segment.append new model.tokens.TextToken 'stu'
      segment.append new model.tokens.TextToken 'vwx'
      segment.append new model.tokens.TextToken 'yz0'

      startLocation = new model.Location(
        2, 3
      )

      endLocation = new model.Location(
        3, 3
      )

      removed = segment.remove(startLocation, endLocation)

      assert.equal removed.serialize(),
        '{[TextToken(mno)],[TextToken(pqr)],[NewlineToken()],[TextToken(stu)],[TextToken(vwx)]}'

      assert.equal segment.serialize(),
        '{[NewlineToken()],[TextToken(abc)],[TextToken(def)],[TextToken(ghi)],[NewlineToken()],[TextToken(jkl)],[TextToken(yz0)]}'

  describe 'Parenting', ->
    it 'should assign parenting as tokens are appended', ->
      model.containers.Container._id = 0
      containerA = new model.containers.Container()

      segment = new model.Segment()
      segment.append a = containerA.start
      segment.append b = new model.tokens.TextToken 'abc'
      segment.append c = containerA.end
      segment.append d = new model.tokens.TextToken 'ghi'

      assert not a.parent?
      assert.equal b.parent, containerA
      assert not c.parent?
      assert not d.parent?

    it 'should reassign parents on an inserted segment', ->
      model.containers.Container._id = 0
      containerA = new model.containers.Container()

      segmentA = new model.Segment()
      segmentA.append containerA.start
      segmentA.append new model.tokens.TextToken 'abc'
      segmentA.append containerA.end

      containerB = new model.containers.Container()

      segmentB = new model.Segment()
      segmentB.append startB = containerB.start
      segmentB.append def = new model.tokens.TextToken 'def'
      segmentB.append endB = containerB.end
      segmentB.append ghi = new model.tokens.TextToken 'ghi'


      segmentA.insert(segmentA.first().next().locate(), segmentB)

      assert.equal segmentA.serialize(),
        '{[StartToken(0)],[TextToken(abc)],[StartToken(1)],[TextToken(def)],[EndToken(1)],[TextToken(ghi)],[EndToken(0)]}'
      assert.equal containerB.parent, containerA, 'containerB'
      assert.equal startB.parent, containerA, 'startB'
      assert.equal endB.parent, containerA, 'endB'
      assert.equal def.parent, containerB, 'def'
      assert.equal ghi.parent, containerA, 'ghi'

    it 'should refuse to remove an segment that would destroy parenting', ->
      model.containers.Container._id = 0
      containerA = new model.containers.Container()

      segment = new model.Segment()
      segment.append containerA.start
      segment.append new model.tokens.TextToken 'abc'
      segment.append containerA.end
      segment.append new model.tokens.TextToken 'ghi'

      assert.throws (->
        segment.remove(
          (new model.Location(0, 0, 'TextToken'))
          (new model.Location(0, 3, 'TextToken'))
        )
      ), RangeError

  describe 'Cloning', ->
    it 'should be able to create another Segment with identical structure but different parent ids', ->
      model.containers.Container._id = 0
      containerA = new model.containers.Container()
      containerB = new model.containers.Container()

      segment = new model.Segment()
      segment.append containerA.start
      segment.append new model.tokens.TextToken 'abc'
      segment.append containerB.start
      segment.append new model.tokens.TextToken 'def'
      segment.append containerB.end
      segment.append containerA.end
      segment.append ghi = new model.tokens.TextToken 'ghi'

      assert.equal segment.serialize(),
        '{[StartToken(0)],[TextToken(abc)],[StartToken(1)],[TextToken(def)],[EndToken(1)],[EndToken(0)],[TextToken(ghi)]}'
      assert.equal segment.clone().serialize(),
        '{[StartToken(2)],[TextToken(abc)],[StartToken(3)],[TextToken(def)],[EndToken(3)],[EndToken(2)],[TextToken(ghi)]}'

describe 'Context', ->
  it 'should be able to undo a simple remove', ->
    segment = new model.Segment()
    segment.append new model.tokens.NewlineToken()
    segment.append new model.tokens.TextToken 'abc'
    segment.append new model.tokens.TextToken 'def'
    segment.append new model.tokens.TextToken 'ghi'
    segment.append new model.tokens.NewlineToken()
    segment.append new model.tokens.TextToken 'jkl'
    segment.append new model.tokens.TextToken 'mno'
    segment.append new model.tokens.TextToken 'pqr'
    segment.append new model.tokens.NewlineToken()
    segment.append new model.tokens.TextToken 'stu'
    segment.append new model.tokens.TextToken 'vwx'
    segment.append new model.tokens.TextToken 'yz0'

    context = new model.Context segment

    original = segment.serialize()

    removed = context.remove(
      (new model.Location(1, 3))
      (new model.Location(2, 6))
    )

    assert.notEqual segment.serialize(), original
    context.undo()
    assert.equal segment.serialize(), original

  it 'should be able to undo a simple insert', ->
    segment = new model.Segment()
    segment.append new model.tokens.NewlineToken()
    segment.append new model.tokens.TextToken 'abc'
    segment.append new model.tokens.TextToken 'def'
    segment.append new model.tokens.TextToken 'ghi'
    segment.append new model.tokens.NewlineToken()
    segment.append new model.tokens.TextToken 'stu'
    segment.append new model.tokens.TextToken 'vwx'
    segment.append new model.tokens.TextToken 'yz0'

    segmentB = new model.Segment()
    segmentB.append new model.tokens.NewlineToken()
    segmentB.append new model.tokens.TextToken 'jkl'
    segmentB.append new model.tokens.TextToken 'mno'
    segmentB.append new model.tokens.TextToken 'pqr'

    context = new model.Context segment

    original = segment.serialize()

    context.insert(
      (new model.Location(1, 6)),
      segmentB
    )

    assert.notEqual segment.serialize(), original
    context.undo()
    assert.equal segment.serialize(), original
