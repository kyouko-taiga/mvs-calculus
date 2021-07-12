from .ir import *


def type_str(ty):
  if ty == FloatType:
    return 'double'
  elif isinstance(ty, StructType):
    return ty.name.str
  elif isinstance(ty, ArrayType):
    return f'std::vector<{type_str(ty.element)}>'
  else:
    assert False, f'unknown type: {ty}'


def print_inst(f, inst):
  if isinstance(inst, ReturnInst):
    f.write("    return {};\n".format(inst.name.str))
    return
  elif isinstance(inst, AssignInst):
    f.write("    {} = {};\n".format(inst.l.str, inst.r.str))
  elif isinstance(inst, ArraySetInst):
    f.write("    {}[{}] = {};\n".format(inst.arr.str, inst.index, inst.r.str))
  elif isinstance(inst, StructSetInst):
    f.write("    {}.p{} = {};\n".format(inst.struct.str, inst.index, inst.r.str))
  else:
    ty = type_str(inst.name.ty)
    if isinstance(inst, BinaryInst):
      f.write("    const {} {} = {} {} {}".format(ty, inst.name.str, inst.l.str, inst.op, inst.r.str))
    elif isinstance(inst, CallInst):
      f.write("    const {} {} = {}({})".format(ty, inst.name.str, inst.func_name.str, ", ".join(arg.str for arg in inst.args)))
    elif isinstance(inst, VarInst):
      f.write("    {} {} = {}".format(ty, inst.name.str, inst.r.str))
    elif isinstance(inst, NewArrayInst):
      args = ", ".join(arg.str for arg in inst.elements)
      f.write("    const {} {} {{ {} }}".format(ty, inst.name.str, args))
    elif isinstance(inst, ArrayGetInst):
      f.write("    const {} {} = {}[{}]".format(ty, inst.name.str, inst.arr.str, inst.index))
    elif isinstance(inst, NewStructInst):
      args = ", ".join(v.str
                       for v in inst.values)
      f.write("    const {} {}({})".format(ty, inst.name.str, args))
    elif isinstance(inst, StructGetInst):
      f.write("    const {} {} = {}.p{}".format(ty, inst.name.str, inst.struct.str, inst.index))
    else:
      raise Exception("Unknown instruction: {}".format(inst))
    f.write(';\n')


def print_func(f, func):
  if func.name.str == "f0":
    f.write("  __attribute__((noinline))\n")
  func_name = func.name.str
  params = ["const {} &{}".format(type_str(param.ty), param.str,)
            for param in func.params]
  param_types = [str(param.ty) for param in func.params]
  all_params = ", ".join(params)
  all_param_types = ", ".join(param_types)
  f.write("  {} {}({}) {{\n".format(
    type_str(func.name.ty), func_name, all_params))
  for inst in func.insts:
    print_inst(f, inst)
  f.write("  }\n")


def print_struct(f, struct):
  name = struct.name
  ty = struct.ty
  f.write("  struct {} {{\n".format(name.str))
  for (n, prop) in enumerate(ty.properties):
    f.write("    {} p{};\n".format(type_str(prop), n))
  params = ", ".join("{} {}".format(type_str(p), f"v{i}")
                     for i, p in enumerate(ty.properties))
  init_params = ", ".join("p{}(v{})".format(i, i)
                          for i, _ in enumerate(ty.properties))
  f.write("    {}({}): {} {{ }}\n".format(name.str, params, init_params))
  f.write("  };")
  f.write("\n")



def print_program(f, program):
  f.write("  #include <vector>\n")
  f.write("  #include <iostream>\n")
  f.write("  #include <chrono>\n")

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

  f.write('  {} benchmark() {{\n'.format(type_str(entry.name.ty)))
  for (n, (p, v)) in enumerate(zip(params, init_values)):
    f.write('    {} v{}({});'.format(type_str(p.ty), n, print_value(v)))
    f.write('\n')
  f.write('    return f0({});\n'.format(', '.join(invoke_args)))
  f.write('  }\n')

  v = initial_values([entry.name])[0]

  f.write('  int main() {\n')
  f.write('    auto start = std::chrono::high_resolution_clock::now();\n')
  f.write('    {} result;\n'.format(type_str(entry.name.ty)))
  f.write('    for (int i = 0; i < 1000; i ++) {\n')
  f.write('      result = benchmark();\n')
  f.write('    }\n')
  f.write('    auto end = std::chrono::high_resolution_clock::now();\n')
  f.write('    double value = *((double*) &result);\n')
  f.write('    std::cout << value << "\\n";\n')
  f.write('    std::cout << std::chrono::duration_cast<std::chrono::nanoseconds>(end-start).count();\n')
  f.write('    std::cout << "\\n";\n')
  f.write('    return 0;\n')
  f.write('  }\n')

def print_value(value):
  if isinstance(value, StructValue):
    args = ", ".join(print_value(v)
                     for v in value.values)
    return "{{ {} }}".format(args)
  elif isinstance(value, float):
    return str(value)
  elif isinstance(value, list):
    return "{ " + ", ".join(print_value(v) for v in value) + " }"
  else:
    assert False, "unknown value: " + str(value)
