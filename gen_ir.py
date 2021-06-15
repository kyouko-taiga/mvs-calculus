from collections import namedtuple


Program = namedtuple("Program", ["structs", "funcs", "meta"])
Func = namedtuple("Func", ["name", "params", "insts"]) 
Struct = namedtuple("Struct", ["name", "ty"])
Name = namedtuple("Name", ["str", "ty"])


BinaryInst = namedtuple("BinaryInst", ["name", "l", "op", "r"]) 
BinaryOps = ["+", "-", "*", "/"]
ReturnInst = namedtuple("ReturnInst", ["name"]) 
CallInst = namedtuple("CallInst", ["name", "func_name", "args"])
VarInst = namedtuple("VarInst", ["name", "r"])
AssignInst = namedtuple("AssignInst", ["l", "r"])
NewArrayInst = namedtuple("NewArrayInst", ["name", "elements"])
ArrayGetInst = namedtuple("ArrayGetInst", ["name", "arr", "index"])
NewStructInst = namedtuple("NewStructInst", ["name", "values"])
StructGetInst = namedtuple("StructGetInst", ["name", "struct", "index"])


FloatingType = namedtuple("FloatingType", ["name"])
FloatingType.__str__ = lambda self: self.name
FloatType = FloatingType("Float")
ArrayType = namedtuple("ArrayType", ["element", "length"])
ArrayType.__str__ = lambda self: "[{}]".format(self.element)
StructType = namedtuple("StructType", ["name", "properties"]) 
StructType.__str__ = lambda self: self.name.str


class StructValue:
  def __init__(self, name, values):
    self.name = name
    self.values = values
  def __repr__(self):
    return f"StructValue({self.name}, {self.values})"
  def __getitem__(self, index):
    return self.values[index]


def initial_values(params):
  count = 0

  def loop(ty):
    nonlocal count
    if isinstance(ty, FloatingType):
      value = float(count)
      count += 1
      return value
    elif isinstance(ty, ArrayType):
      value = []
      for _ in range(ty.length):
        value.append(loop(ty.element))
      return value
    elif isinstance(ty, StructType):
      props = []
      for prop in ty.properties:
        props.append(loop(prop))
      return StructValue(ty.name, props)
    else:
      raise Exception("Unknown type: {}".format(ty))

  return [loop(p.ty) for p in params]
