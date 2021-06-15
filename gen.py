import json
import os
import sys
import random as rand
import itertools
from collections import namedtuple, defaultdict


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


inst_weights = {
    CallInst: 160,
    BinaryInst: 80,
    VarInst: 20,
    AssignInst: 15,
    NewArrayInst: 10,
    ArrayGetInst: 100,
    NewStructInst: 20,
    StructGetInst: 200,
}
floating_type_weights = {
    FloatType: 1,
}
aggregate_type_weights = {
    ArrayType: 20,
    StructType: 20,
}
type_weights = {**floating_type_weights, **aggregate_type_weights}
param_count_weights = {
    1: 100,
    2: 80,
    3: 40,
    4: 20,
    5: 10,
    6: 5,
    7: 3,
    8: 1,
}
property_count_weights = {
    1: 40,
    2: 1000,
    3: 80,
    4: 40,
    5: 20,
    6: 10,
    7: 5,
    8: 5,
}
return_offset_weights = {
    -1: 100,
    -2: 50,
    -3: 25,
    -4: 10,
    -5: 5,
    -6: 3,
    -7: 2,
    -8: 1,
}


op_limit = 5000
inst_min = 8
inst_limit = 256
func_limit = 128
struct_limit = 16
array_limit = 8


def print_inst(f, inst, dialect):
  if isinstance(inst, ReturnInst):
    if dialect == 'swift':
      f.write("    return {}\n".format(inst.name.str))
    elif dialect == 'mvs':
      f.write("    {}\n".format(inst.name.str))
    return
  elif isinstance(inst, BinaryInst):
    f.write("    let {}: {} = {} {} {}".format(inst.name.str, inst.name.ty, inst.l.str, inst.op, inst.r.str))
  elif isinstance(inst, CallInst):
    f.write("    let {}: {} = {}({})".format(inst.name.str, inst.name.ty, inst.func_name.str, ", ".join(arg.str for arg in inst.args)))
  elif isinstance(inst, VarInst):
    f.write("    var {}: {} = {}".format(inst.name.str, inst.name.ty, inst.r.str))
  elif isinstance(inst, AssignInst):
    f.write("    {} = {}".format(inst.l.str, inst.r.str))
  elif isinstance(inst, NewArrayInst):
    args = ", ".join(arg.str for arg in inst.elements)
    f.write("    let {}: {} = [{}]".format(inst.name.str, inst.name.ty, args))
  elif isinstance(inst, ArrayGetInst):
    f.write("    let {}: {} = {}[{}]".format(inst.name.str, inst.name.ty, inst.arr.str, inst.index))
  elif isinstance(inst, NewStructInst):
    if dialect == 'swift':
      args = ", ".join("p{}: {}".format(n, v.str) 
                       for (n, v) in enumerate(inst.values))
    elif dialect == 'mvs':
      args = ", ".join("{}".format(v.str) 
                       for v in inst.values)
    f.write("    let {}: {} = {}({})".format(inst.name.str, inst.name.ty, inst.name.ty, args))
  elif isinstance(inst, StructGetInst):
    f.write("    let {}: {} = {}.p{}".format(inst.name.str, inst.name.ty, inst.struct.str, inst.index))
  else:
    raise Exception("Unknown instruction: {}".format(inst))
  f.write(' in\n' if dialect == 'mvs' else '\n')


def print_func(f, func, dialect):
  if dialect == 'swift':
    if func.name.str == "f0":
      f.write("  @inline(never)\n")
  func_name = func.name.str
  if dialect == 'mvs':
    if func.name.str == "f0":
      func_name = 'noinline_' + func_name
  param_pre = '_ ' if dialect == 'swift' else ''
  params = ["{}{}: {}".format(param_pre, param.str, param.ty) 
            for param in func.params]
  param_types = [str(param.ty) for param in func.params]
  all_params = ", ".join(params)
  all_param_types = ", ".join(param_types)
  if dialect == 'swift':
    f.write("  func {}({}) -> {} {{\n".format(func_name, all_params, func.name.ty))
  elif dialect == 'mvs':
    f.write("  let {}: ({}) -> {} = ({}) -> {} {{\n".format(
      func_name, all_param_types, func.name.ty, all_params, func.name.ty))
  for inst in func.insts:
    print_inst(f, inst, dialect)
  f.write("  }\n" if dialect == 'swift' else '  } in\n')


def print_struct(f, struct, dialect):
  name = struct.name
  ty = struct.ty
  f.write("  struct {} {{\n".format(name.str))
  for (n, prop) in enumerate(ty.properties):
    f.write("    var p{}: {}\n".format(n, prop))
  f.write("  }")
  f.write(" in\n" if dialect == "mvs" else "\n")



def print_program(f, name, program, dialect):
  for struct in program.structs:
    print_struct(f, struct, dialect)
  for func in reversed(program.funcs):
    print_func(f, func, dialect)

  entry = program.funcs[0]
  params = entry.params
  init_values = initial_values(params)
  invoke_args = ["v" + str(n) for n, _ in enumerate(init_values)]
  input_args = ("{}: {}".format(p.str, v) for (p, v) in zip(params, init_values))
  grad_args = ("input.{}".format(p.str) for p in params) 

  if dialect == 'swift':
    f.write('  func main() {\n')
  elif dialect == 'mvs':
    f.write('  let main: () -> {} = () -> {} {{\n'.format(
      entry.name.ty, entry.name.ty))
  for (n, (p, v)) in enumerate(zip(params, init_values)):
    f.write('    let v{}: {} = {}'.format(n, p.ty, print_value(v, dialect)))
    f.write('\n' if dialect == 'swift' else ' in\n')
  if dialect == 'swift':
    f.write('    print(f0({}))\n'.format(', '.join(invoke_args)))
  elif dialect == 'mvs':
    f.write('    noinline_f0({})\n'.format(', '.join(invoke_args)))
  f.write('  }\n' if dialect == 'swift' else '  } in\n')
  f.write('  main()\n')

def print_value(value, dialect):
  if isinstance(value, StructValue):
    args = ''
    if dialect == 'swift':
      args = ", ".join("p{}: {}".format(n, print_value(v, dialect))
                       for (n, v) in enumerate(value.values))
    elif dialect == 'mvs':
      args = ", ".join("{}".format(print_value(v, dialect))
                       for v in value.values)
    return "{}({})".format(value.name.str, args)
  elif isinstance(value, float):
    return str(value)
  elif isinstance(value, list):
    return "[" + ", ".join(print_value(v, dialect) for v in value) + "]"
  else:
    assert False, "unknown value: " + str(value)

def gen_type(weights=type_weights, array_limit=array_limit, struct_env=[]):
  actual_weights = dict(weights)
  # We want to limit nested arrays because they
  # can explode exponentially size-wise.
  if array_limit < 4: 
    actual_weights.pop(ArrayType, None)
  # Must have at least one struct defined to
  # generate a struct type.
  if len(struct_env) == 0:
    actual_weights.pop(StructType, None)

  ty = weighted_pick(actual_weights) 
  if isinstance(ty, FloatingType):
    return ty
  elif ty is ArrayType:
    # Every nested array gets half the weight of getting
    # an array inside of it and the length of the array is half
    # the outer length limit.
    actual_weights[ArrayType] = int(actual_weights[ArrayType]/2)
    array_limit = int(array_limit/2)
    return ArrayType(gen_type(actual_weights, array_limit, struct_env), 
                     rand.randrange(1, array_limit))
  elif ty is StructType:
    return rand.choice(struct_env)
  else:
    raise Exception("Unknown type: {}".format(ty))


def gen_name(name_env, ty):
  top = 8
  names = []
  for values in name_env.values():
    for n in values:
      names.append(n.str)
  suggested = "v{}".format(rand.randrange(top))
  while suggested in names:
    top = int(top * 1.2)
    suggested = "v{}".format(rand.randrange(top))
  return Name(suggested, ty)


def weighted_pick(weights):
  seq = list(weights.items())
  total = sum(el[1] for el in seq)
  bucket = rand.randint(0, total - 1)
  index = 0

  for el, weight in seq:
    if bucket < weight:
      return el
    else:
      bucket -= weight

  raise Exception("unreachable")


def is_inhabited(name_env, ty, n=1):
  return len(name_env[ty]) >= n


def gen_inhabited_types(name_env, predicate=None):
  out = []
  for (ty, names) in name_env.items():
    if len(names) > 0:
      if predicate is None or predicate(ty):
        out.append(ty)
  return out

def gen_inhabited_type(name_env, predicate=None):
  options = gen_inhabited_types(name_env, predicate=predicate)
  if len(options) > 0:
    return rand.choice(options)
  else:
    return None


def gen_inhabitants(name_env, ty, exclude=None):
  if exclude is None:
    return name_env[ty]
  else:
    candidates = set(name_env[ty])
    candidates.remove(exclude)
    return list(candidates)
  

def gen_inhabitant(name_env, ty, exclude=None):
  options = gen_inhabitants(name_env, ty, exclude=exclude)
  if len(options) > 0:
    return rand.choice(options)
  else:
    return None

def is_floating_type(ty):
  return isinstance(ty, FloatingType)


def is_array_type(ty):
  return isinstance(ty, ArrayType)


def is_nonempty_array_type(ty):
  return isinstance(ty, ArrayType) and ty.length > 0


def is_struct_type(ty):
  return isinstance(ty, StructType)


def gen_inst(name_env, var_names, func_name, func_env, struct_env):
  func_id = int(func_name.str[1:])

  callable_functions = []
  for (name, params) in func_env.items():
    name_id = int(name.str[1:])
    # To make sure the generated call graph is a DAG,
    # we only allow calls to functions with higher id.
    if name_id > func_id:
      # Function is callable when we have at least one
      # value for each argument.
      if all(is_inhabited(name_env, p.ty) for p in params):
        callable_functions.append(name)

  assignable_vars = []
  for var_name in var_names:
    # For a var to be assignable we need at least
    # two distinct values that can be assigned to it
    # because we can't assign a var to itself.
    if is_inhabited(name_env, var_name.ty, n=2):
      assignable_vars.append(var_name)

  inhabited_floats = gen_inhabited_types(name_env, 
                                         predicate=is_floating_type)
  inhabited_nonempty_arrays = gen_inhabited_types(name_env, 
                                                  predicate=is_nonempty_array_type)
  instantiatable_structs = [s 
                            for s in struct_env
                            if all(is_inhabited(name_env, p) for p in s.properties)]
  inhabited_structs = gen_inhabited_types(name_env, predicate=is_struct_type)

  can_binop = len(inhabited_floats) > 0
  can_call = len(callable_functions) > 0
  can_assign = len(assignable_vars) > 0
  can_arrayget = len(inhabited_nonempty_arrays) > 0
  can_newstruct = len(instantiatable_structs) > 0
  can_structget = len(inhabited_structs) > 0

  weights = dict(inst_weights)
  if not can_binop: weights.pop(BinaryInst, None)
  if not can_call: weights.pop(CallInst, None)
  if not can_assign: weights.pop(AssignInst, None)
  if not can_arrayget: weights.pop(ArrayGetInst, None)
  if not can_newstruct: weights.pop(NewStructInst, None)
  if not can_structget: weights.pop(StructGetInst, None)

  inst = weighted_pick(weights)

  if inst is BinaryInst:
    opty = gen_inhabited_type(name_env, predicate=is_floating_type)
    name = gen_name(name_env, opty)
    l = gen_inhabitant(name_env, opty)
    op = rand.choice(BinaryOps)
    r = gen_inhabitant(name_env, opty)
    return BinaryInst(name, l, op, r)
  elif inst is CallInst:
    func_name = rand.choice(callable_functions)
    name = gen_name(name_env, func_name.ty)
    args = [gen_inhabitant(name_env, p.ty) for p in func_env[func_name]]
    return CallInst(name, func_name, args)
  elif inst is VarInst:
    varty = gen_inhabited_type(name_env)
    name = gen_name(name_env, varty) 
    r = gen_inhabitant(name_env, varty)
    return VarInst(name, r)
  elif inst is AssignInst:
    l = rand.choice(assignable_vars)
    r = gen_inhabitant(name_env, l.ty, exclude=l)
    return AssignInst(l, r)
  elif inst is NewArrayInst:
    elemty = gen_inhabited_type(name_env)
    elems = [gen_inhabitant(name_env, elemty) for _ in range(rand.randrange(1, array_limit))]
    name = gen_name(name_env, ArrayType(elemty, len(elems)))
    return NewArrayInst(name, elems)
  elif inst is ArrayGetInst:
    arrty = gen_inhabited_type(name_env, predicate=is_nonempty_array_type)
    arr = gen_inhabitant(name_env, arrty)
    name = gen_name(name_env, arrty.element)
    index = rand.randint(0, arrty.length - 1)
    return ArrayGetInst(name, arr, index)
  elif inst is NewStructInst:
    structty = rand.choice(instantiatable_structs)
    name = gen_name(name_env, structty)
    values = [gen_inhabitant(name_env, ty) for ty in structty.properties]
    return NewStructInst(name, values)
  elif inst is StructGetInst:
    structty = rand.choice(inhabited_structs)
    struct = gen_inhabitant(name_env, structty)
    index = rand.randint(0, len(structty.properties) - 1)
    name = gen_name(name_env, structty.properties[index])
    return StructGetInst(name, struct, index)
  else:
    raise Exception("Unknown instruction: {}".format(inst))


def drop_unused_insts(func):
  uses = dict()

  for param in func.params:
    uses[param] = []
  for inst in func.insts:
    if isinstance(inst, BinaryInst):
      uses[inst.name] = [inst.l, inst.r]
    elif isinstance(inst, ReturnInst):
      pass
    elif isinstance(inst, CallInst):
      uses[inst.name] = inst.args
    elif isinstance(inst, VarInst):
      uses[inst.name] = [inst.r]
    elif isinstance(inst, AssignInst):
      uses[inst.l].append(inst.r)
    elif isinstance(inst, NewArrayInst):
      uses[inst.name] = inst.elements
    elif isinstance(inst, ArrayGetInst):
      uses[inst.name] = [inst.arr]
    elif isinstance(inst, NewStructInst):
      uses[inst.name] = inst.values
    elif isinstance(inst, StructGetInst):
      uses[inst.name] = [inst.struct]
    else:
      raise Exception("Unknown instruction: {}".format(inst))

  used = set()

  def mark_used(name):
    if name not in used:
      used.add(name)
      for dep in uses[name]:
        mark_used(dep)

  def is_used(inst):
    if isinstance(inst, ReturnInst):
      return True
    elif isinstance(inst, AssignInst):
      return inst.l in used
    else:
      return inst.name in used

  mark_used(func.insts[-1].name)

  return Func(func.name, func.params, list(filter(is_used, func.insts)))


def gen_func(func_name, func_env, struct_env):
  func_params = func_env[func_name]
  func_insts = []
  name_env = defaultdict(list)
  for name in func_params:
    name_env[name.ty].append(name)
  assert(is_inhabited(name_env, func_name.ty))
  var_names = set()
  for _ in range(rand.randrange(inst_min, inst_limit)):
    inst = gen_inst(name_env, var_names, func_name, func_env, struct_env)
    assert not isinstance(inst, ReturnInst)
    func_insts.append(inst)
    if isinstance(inst, AssignInst):
      pass
    else:
      name = inst.name
      name_env[name.ty].append(name)
      if isinstance(inst, VarInst):
        var_names.add(name)
  
  inhabitants = sorted(gen_inhabitants(name_env, func_name.ty), key=lambda n: int(n.str[1:]))
  ret_offset = max(-len(inhabitants), weighted_pick(return_offset_weights))
  ret_value = inhabitants[ret_offset]
  func_insts.append(ReturnInst(ret_value))

  return drop_unused_insts(Func(func_name, func_params, func_insts))


def gen_program():
  struct_env = []
  for n in range(rand.randrange(0, struct_limit)):
    properties = [gen_type(struct_env=struct_env) 
                  for n in range(weighted_pick(property_count_weights))]
    n = "s{}".format(n)
    ty = StructType(Name(n, None), tuple(properties))
    struct_env.append(ty)

  func_names = ["f{}".format(n) for n in range(rand.randrange(1, func_limit))]
  func_params = {}
  for n in func_names:
    params = [Name("v{}".format(n), gen_type(type_weights, struct_env=struct_env)) 
              for n in range(weighted_pick(param_count_weights))]
    func_params[n] = params

  func_env = {}
  for n in func_names:
    # Entry-point function must return a scalar type,
    # because it's result is used in gradient computation.
    options = func_params[n]
    if n == "f0":
      options = [p for p in options if is_floating_type(p.ty)]
      if len(options) == 0:
        scalar_ty = gen_type(floating_type_weights)
        count = len(func_params[n])
        extra_param = Name("v{}".format(count), scalar_ty)
        func_params[n].append(extra_param)
        options.append(extra_param)
    name = Name(n, rand.choice(options).ty)
    func_env[name] = func_params[n]

  structs = [Struct(ty.name, ty) for ty in struct_env]
  funcs = [gen_func(name, func_env, struct_env) for name in func_env.keys()]
  return Program(structs=structs, funcs=funcs, meta={})


class TooManyOps(Exception): pass


def validate_program(program):
  funcs = program.funcs
  func_map = { func.name: func for func in funcs }
  entry_name = funcs[0].name
  op_count = 0
  called_funcs = set()
  used_structs = set()

  def count_op():
    nonlocal op_count
    op_count += 1
    if op_count > op_limit:
      raise TooManyOps()

  def interp_binary(op, l, r):
    assert(isinstance(l, float))
    assert(isinstance(r, float))

    if op == "+":
      return l + r
    elif op == "-":
      return l - r
    elif op == "*":
      return l * r
    elif op == "/":
      return l / r
    else:
      raise Exception("Unknown instruction: {}".format(inst))

  def interp_call(func_name, func_args):
    nonlocal called_funcs
    called_funcs.add(func_name)

    func = func_map[func_name]
    assert(len(func_args) == len(func.params))
    env = dict(zip(func.params, func_args))

    for inst in func.insts:
      count_op()
      if isinstance(inst, BinaryInst):
        env[inst.name] = interp_binary(inst.op, env[inst.l], env[inst.r])
      elif isinstance(inst, ReturnInst):
        return env[inst.name]
      elif isinstance(inst, CallInst):
        env[inst.name] = interp_call(inst.func_name, list(map(lambda n: env[n], inst.args)))
      elif isinstance(inst, VarInst):
        env[inst.name] = env[inst.r]
      elif isinstance(inst, AssignInst):
        env[inst.l] = env[inst.r]
      elif isinstance(inst, NewArrayInst):
        env[inst.name] = [env[n] for n in inst.elements]
      elif isinstance(inst, ArrayGetInst):
        env[inst.name] = env[inst.arr][inst.index]
      elif isinstance(inst, NewStructInst):
        nonlocal used_structs
        used_structs.add(inst.name.ty.name)
        env[inst.name] = [env[n] for n in inst.values]
      elif isinstance(inst, StructGetInst):
        env[inst.name] = env[inst.struct][inst.index]
      else:
        raise Exception("Unknown instruction: {}".format(inst))

  def mark_used_structs(value):
    if isinstance(value, float):
      pass
    elif isinstance(value, list):
      for v in value:
        mark_used_structs(v)
    elif isinstance(value, StructValue):
      nonlocal used_structs
      used_structs.add(value.name)
      for v in value.values:
        mark_used_structs(v)
    else:
      raise Exception("Unknown value: {}".format(value))

  entry_args = initial_values(func_map[entry_name].params)
  mark_used_structs(entry_args)
  try: 
    interp_call(entry_name, entry_args)
    if op_count > 10:
      new_funcs = [f for f in program.funcs if f.name in called_funcs]
      new_structs = [s for s in program.structs if s.name in used_structs]
      return Program(funcs=new_funcs, structs=new_structs, meta={"op_count": op_count})
    else:
      return None
  except ZeroDivisionError:
    return None
  except TooManyOps:
    return None


class StructValue:
  def __init__(self, name, values):
    self.name = name
    self.values = values
  def __repr__(self):
    return print_value(self, 'swift')
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


def main(prefix):
  program = None 
  while program is None:
    program = validate_program(gen_program())
  with open(f"{prefix}.swift", "w") as f:
    print_program(f, "Gen", program, "swift")
  with open(f"{prefix}.mvs", "w") as f:
    print_program(f, "Gen", program, "mvs")


if __name__ == "__main__":
  main('gen')
