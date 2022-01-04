local Tree = {}
Tree.__index = Tree

function Tree:new(id, name, type, children)
  local tree = setmetatable({}, Tree)
  tree.id = id
  tree.name = name
  tree.type = type
  tree.children = children or {}
  return tree
end

-- Calling the tree like a function will create and return children if they are not found.
function Tree:__call(id, name, type)
  for _, child in ipairs(self.children) do
    if child.id == id then
      return child
    end
  end
  local child = Tree:new(id, name, type)
  table.insert(self.children, child)
  return child
end

function Tree:flatten_directories()
  for _, child in ipairs(self.children) do
    if child.type == "dir" and #child.children == 1 and child.children[1].type == "dir" then
      --print(child.id, " :: ", child.children[1].id)
      child.id = child.children[1].id
      child.type = child.children[1].type
      child.name = child.children[1].name
      child.children = child.children[1].children
      self:flatten_directories()
    end
  end
  return self
end

return Tree
