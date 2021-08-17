from .ir import *


def type_str(ty):
  if ty == FloatType:
    return 'Double'
  elif isinstance(ty, StructType):
    return ty.name.str
  elif isinstance(ty, ArrayType):
    return f'Vector[{type_str(ty.element)}]'
  else:
    assert False, f'unknown type: {ty}'


def print_inst(f, inst):
  if isinstance(inst, ReturnInst):
    f.write("    {}\n".format(inst.name.str))
    return
  elif isinstance(inst, AssignInst):
    f.write("    {} = {}\n".format(inst.l.str, inst.r.str))
  elif isinstance(inst, ArraySetInst):
    f.write("    {} = {}.updated({}, {})\n".format(inst.arr.str, inst.arr.str, inst.index, inst.r.str))
  elif isinstance(inst, StructSetInst):
    f.write("    {} = {}.copy(p{} = {})\n".format(inst.struct.str, inst.struct.str, inst.index, inst.r.str))
  else:
    ty = type_str(inst.name.ty)
    if isinstance(inst, BinaryInst):
      f.write("    val {}: {} = {} {} {}".format(inst.name.str, ty, inst.l.str, inst.op, inst.r.str))
    elif isinstance(inst, CallInst):
      f.write("    val {}: {} = {}({})".format(inst.name.str, ty, inst.func_name.str, ", ".join(arg.str for arg in inst.args)))
    elif isinstance(inst, VarInst):
      f.write("    var {}: {} = {}".format(inst.name.str, ty, inst.r.str))
    elif isinstance(inst, NewArrayInst):
      args = ", ".join(arg.str for arg in inst.elements)
      f.write("    val {}: {} = Vector({})".format(inst.name.str, ty, args))
    elif isinstance(inst, ArrayGetInst):
      f.write("    val {}: {} = {}({})".format(inst.name.str, ty, inst.arr.str, inst.index))
    elif isinstance(inst, NewStructInst):
      args = ", ".join("{}".format(v.str)
                       for v in inst.values)
      f.write("    val {}: {} = {}({})".format(inst.name.str, ty, ty, args))
    elif isinstance(inst, StructGetInst):
      f.write("    val {}: {} = {}.p{}".format(inst.name.str, ty, inst.struct.str, inst.index))
    else:
      raise Exception("Unknown instruction: {}".format(inst))
    f.write('\n')


def print_func(f, func):
  if func.name.str == "f0":
    f.write("  @noinline\n")
  func_name = func.name.str
  params = ["{}: {}".format(param.str, type_str(param.ty))
            for param in func.params]
  param_types = [type_str(param.ty) for param in func.params]
  all_params = ", ".join(params)
  all_param_types = ", ".join(param_types)
  f.write("  def {}({}): {} = {{\n".format(func_name, all_params, type_str(func.name.ty)))
  for inst in func.insts:
    print_inst(f, inst)
  f.write("  }\n")


def print_struct(f, struct):
  name = struct.name
  ty = struct.ty
  f.write("  case class {} (\n".format(name.str))
  for (n, prop) in enumerate(ty.properties):
    f.write("    p{}: {}".format(n, type_str(prop)))
    f.write(",\n" if n != len(ty.properties) - 1 else "\n")
  f.write("  )")
  f.write("\n")


def print_program(f, program):
  f.write("import java.lang.System.nanoTime\n")
  f.write("import scala.collection.immutable.Vector\n")
  f.write("object Gen extends App {\n")

  for struct in program.structs:
    print_struct(f, struct)
  for func in reversed(program.funcs):
    print_func(f, func)

  entry = program.funcs[0]
  params = entry.params
  init_values = initial_values(params)
  invoke_args = ["v" + str(n) for n, _ in enumerate(init_values)]
  input_args = ("{}: {}".format(p.str, v) for (p, v) in zip(params, init_values))
  grad_args = ("input.{}".format(p.str) for p in params)

  v = initial_values([entry.name])[0]

  f.write('  def benchmark(): Unit = {\n')
  for (n, (p, v)) in enumerate(zip(params, init_values)):
    f.write('    val v{}: {} = {}\n'.format(n, type_str(p.ty), print_value(v)))
  f.write('    val start = nanoTime()\n')
  f.write('    var result: {} = {}\n'.format(type_str(entry.name.ty), v))
  f.write('    (1 to 1000).foreach { _ =>\n')
  f.write('      result = f0({})\n'.format(', '.join(invoke_args)))
  f.write('    }\n')
  f.write('    val end = nanoTime()\n')
  f.write('    println(result)\n')
  f.write('    println(end - start)\n')
  f.write('  }\n')
  f.write('  benchmark()\n')
  f.write('}')

def print_value(value):
  if isinstance(value, StructValue):
    args = ", ".join("{}".format(print_value(v))
                     for v in value.values)
    return "{}({})".format(value.name.str, args)
  elif isinstance(value, float):
    return str(value)
  elif isinstance(value, list):
    return "Vector(" + ", ".join(print_value(v) for v in value) + ")"
  else:
    assert False, "unknown value: " + str(value)
