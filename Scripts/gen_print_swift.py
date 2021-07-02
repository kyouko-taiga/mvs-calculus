from gen_ir import *


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
  if dialect == 'swift':
    f.write('  import Dispatch\n')

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
    f.write('  func main() -> {} {{\n'.format(entry.name.ty))
  elif dialect == 'mvs':
    f.write('  let main: () -> {} = () -> {} {{\n'.format(
      entry.name.ty, entry.name.ty))
  for (n, (p, v)) in enumerate(zip(params, init_values)):
    f.write('    let v{}: {} = {}'.format(n, p.ty, print_value(v, dialect)))
    f.write('\n' if dialect == 'swift' else ' in\n')
  if dialect == 'swift':
    f.write('    return f0({})\n'.format(', '.join(invoke_args)))
  elif dialect == 'mvs':
    f.write('    noinline_f0({})\n'.format(', '.join(invoke_args)))
  f.write('  }\n' if dialect == 'swift' else '  } in\n')

  if dialect == 'swift':
    v = initial_values([entry.name])[0]

    f.write('  func benchmark() {\n')
    f.write('    let start = DispatchTime.now().uptimeNanoseconds\n')
    f.write('    var result: {} = {}\n'.format(entry.name.ty, v))
    f.write('    for _ in 1...1000 {\n')
    f.write('      result = main()\n')
    f.write('    }\n')
    f.write('    let end = DispatchTime.now().uptimeNanoseconds\n')
    f.write('    print(result)\n')
    f.write('    print(end - start)\n')
    f.write('  }\n')
    f.write('  benchmark()\n')
  elif dialect == 'mvs':
    # In MVS function loop is generated with `--benchmark`
    # compiler flag.
    f.write('main()')

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

