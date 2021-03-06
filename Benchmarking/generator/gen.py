import json
import os
import sys
import random as rand
import itertools

from collections import namedtuple, defaultdict

from .ir import *
from .cpp import print_program as print_cpp
from .swift import print_program as print_swift
from .scala import print_program as print_scala

ROOT_DIR = 'Benchmarking'
SRC_DIR = os.path.join(ROOT_DIR, 'src')

inst_weights = {
    CallInst: 10,
    BinaryInst: 1,
    VarInst: 10,
    AssignInst: 1,
    NewArrayInst: 1,
    ArrayGetInst: 10,
    ArraySetInst: 5,
    NewStructInst: 1,
    StructGetInst: 10,
    StructSetInst: 5,
}

floating_type_weights = {
    FloatType: 1,
}

aggregate_type_weights = {
    ArrayType: 50,
    StructType: 50,
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
  assignable_arrays = []
  assignable_structs = []
  for var_name in var_names:
    # For a var to be assignable we need at least
    # two distinct values that can be assigned to it
    # because we can't assign a var to itself.
    if is_inhabited(name_env, var_name.ty, n=2):
      assignable_vars.append(var_name)

    if isinstance(var_name.ty, ArrayType):
      if is_inhabited(name_env, var_name.ty.element):
        assignable_arrays.append(var_name)

    if isinstance(var_name.ty, StructType):
      can_assign_prop = False
      for prop in var_name.ty.properties:
        if is_inhabited(name_env, prop):
          can_assign_prop = True
          break
      if can_assign_prop:
        assignable_structs.append(var_name)

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
  can_arrayset = len(assignable_arrays) > 0
  can_newstruct = len(instantiatable_structs) > 0
  can_structget = len(inhabited_structs) > 0
  can_structset = len(assignable_structs) > 0

  weights = dict(inst_weights)
  if not can_binop: weights.pop(BinaryInst, None)
  if not can_call: weights.pop(CallInst, None)
  if not can_assign: weights.pop(AssignInst, None)
  if not can_arrayget: weights.pop(ArrayGetInst, None)
  if not can_arrayset: weights.pop(ArraySetInst, None)
  if not can_newstruct: weights.pop(NewStructInst, None)
  if not can_structget: weights.pop(StructGetInst, None)
  if not can_structset: weights.pop(StructSetInst, None)

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
  elif inst is ArraySetInst:
    arr = rand.choice(assignable_arrays)
    index = rand.randint(0, arr.ty.length - 1)
    r = gen_inhabitant(name_env, arr.ty.element)
    return ArraySetInst(arr, index, r)
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
  elif inst is StructSetInst:
    struct = rand.choice(assignable_structs)
    assignable_props = []
    for (idx, prop) in enumerate(struct.ty.properties):
      if is_inhabited(name_env, prop):
        assignable_props.append((prop, idx))
    prop, index = rand.choice(assignable_props)
    r = gen_inhabitant(name_env, prop)
    return StructSetInst(struct, index, r)
  else:
    raise Exception("Unknown instruction: {}".format(inst))


def compute_func_uses(func):
  uses = compute_inst_uses(func.insts)
  for param in func.params:
    uses[param] = []
  return uses


def compute_inst_uses(insts):
  uses = dict()

  for inst in insts:
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
    elif isinstance(inst, ArraySetInst):
      uses[inst.arr].append(inst.r)
    elif isinstance(inst, NewStructInst):
      uses[inst.name] = inst.values
    elif isinstance(inst, StructGetInst):
      uses[inst.name] = [inst.struct]
    elif isinstance(inst, StructSetInst):
      uses[inst.struct].append(inst.r)
    else:
      raise Exception("Unknown instruction: {}".format(inst))

  return uses


def drop_unused_insts(func):
  uses = compute_func_uses(func)
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
    elif isinstance(inst, ArraySetInst):
      return inst.arr in used
    elif isinstance(inst, StructSetInst):
      return inst.struct in used
    else:
      return inst.name in used

  mark_used(func.insts[-1].name)

  return Func(func.name, func.params, list(filter(is_used, func.insts)))


def compute_inst_sizes(insts):
  uses = compute_inst_uses(insts)
  sizes = defaultdict(lambda: 1)

  for inst in insts:
    if hasattr(inst, "name"):
      total_size = 1
      for use in uses[inst.name]:
        total_size += sizes[use]
      sizes[inst.name] = total_size

  return sizes

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
    elif isinstance(inst, ArraySetInst):
      pass
    elif isinstance(inst, StructSetInst):
      pass
    else:
      name = inst.name
      name_env[name.ty].append(name)
      if isinstance(inst, VarInst):
        var_names.add(name)

  sizes = compute_inst_sizes(func_insts)
  inhabitants = sorted(gen_inhabitants(name_env, func_name.ty), key=lambda n: sizes[n])
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
  total_op_count = 0
  op_count = defaultdict(lambda: 0)
  called_funcs = set()
  used_structs = set()

  def count_op(inst):
    nonlocal total_op_count
    op_name = inst.__class__.__name__
    op_count[op_name] += 1
    total_op_count += 1
    if total_op_count > op_limit:
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
      count_op(inst)
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
      elif isinstance(inst, ArraySetInst):
        env[inst.arr][inst.index] = env[inst.r]
      elif isinstance(inst, NewStructInst):
        nonlocal used_structs
        used_structs.add(inst.name.ty.name)
        env[inst.name] = [env[n] for n in inst.values]
      elif isinstance(inst, StructGetInst):
        env[inst.name] = env[inst.struct][inst.index]
      elif isinstance(inst, StructSetInst):
        env[inst.struct][inst.index] = env[inst.r]
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
    if total_op_count > 10:
      new_funcs = [f for f in program.funcs if f.name in called_funcs]
      new_structs = [s for s in program.structs if s.name in used_structs]
      meta = {}
      meta['op_count'] = op_count
      meta['total_count'] = total_op_count
      return Program(funcs=new_funcs, structs=new_structs, meta=meta)
    else:
      return None
  except ZeroDivisionError:
    return None
  except TooManyOps:
    return None


def main(prefix):
  program = None
  while program is None:
    program = validate_program(gen_program())
  if not os.path.exists(SRC_DIR):
    os.makedirs(SRC_DIR)
  with open(f"{SRC_DIR}/{prefix}.json", "w") as f:
    f.write(json.dumps(program.meta))
  with open(f"{SRC_DIR}/{prefix}.swift", "w") as f:
    print_swift(f, "Gen", program, "swift")
  with open(f"{SRC_DIR}/{prefix}.mvs", "w") as f:
    print_swift(f, "Gen", program, "mvs")
  with open(f"{SRC_DIR}/{prefix}.cpp", "w") as f:
    print_cpp(f, program)
  with open(f"{SRC_DIR}/{prefix}.scala", "w") as f:
    print_scala(f, program)


if __name__ == "__main__":
  for i in itertools.count(start=1):
    prefix = f'gen{i}'
    if not os.path.exists(f'{SRC_DIR}/{prefix}.json'):
      print(f"Generating {prefix}")
      main(prefix)
