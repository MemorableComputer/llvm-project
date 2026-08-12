# RUN: llvm-mc %s -triple=riscv64 -mattr=+xmemorable,+v -show-encoding \
# RUN:     | FileCheck -check-prefixes=CHECK-ASM,CHECK-ASM-AND-OBJ %s
# RUN: llvm-mc -filetype=obj -triple=riscv64 -mattr=+xmemorable,+v < %s \
# RUN:     | llvm-objdump --mattr=+xmemorable,+v -d - \
# RUN:     | FileCheck --check-prefix=CHECK-ASM-AND-OBJ %s

# CHECK-ASM-AND-OBJ: vexp2diff.vv v1, v2, v3
# CHECK-ASM: encoding: [0xab,0x10,0x31,0x14]
vexp2diff.vv v1, v2, v3
