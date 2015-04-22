t = require './tree.coffee'
assert = require 'assert'

string = '''
He said 'All right!'
But it wasn't, quite,
'cause I caught him in the autumn
In my garden one night!
He was robbing me,
Raping me,
Rooting through my rutabaga,
Raiding my arugula and
rupping up my rampion --
My champion! My favorite!
I should have laid a spell on him
Right there,
Could have changed him into stone
Or a dog or a chair.
But I let him have the rampion --
I'd lots to spare.
In return, however,
I said, "Fair's fair":
You can let me have the baby that your wife will bear,
and we'll call it square.
'''

stringSections = []; marker = 0
until marker > string.length
  newMarker = marker + 5
  stringSections.push string[marker...newMarker]
  marker = newMarker

tree = new t.Tree [(x) -> x.length]
tree.append el for el in stringSections
console.log tree.root.left.weight, tree.root.right.weight
assert.equal tree.get(0, 100).data, string[95...100]
console.log tree.root.left.weight, tree.root.right.weight
for [1..100]
  index = Math.floor Math.random() * string.length
  tree.get(0, index)
  console.log tree.root.left.weight, tree.root.right.weight
