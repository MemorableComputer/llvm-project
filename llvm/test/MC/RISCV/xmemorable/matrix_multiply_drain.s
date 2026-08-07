# RUN: llvm-mc %s -triple=riscv64 -mattr=+xmemorable,+v -show-encoding \
# RUN:     | FileCheck -check-prefixes=CHECK-ASM,CHECK-ASM-AND-OBJ %s
# RUN: llvm-mc -filetype=obj -triple=riscv64 -mattr=+xmemorable,+v < %s \
# RUN:     | llvm-objdump --mattr=+xmemorable,+v -d - \
# RUN:     | FileCheck --check-prefix=CHECK-ASM-AND-OBJ %s

# CHECK-ASM-AND-OBJ: matrix.multiply_drain a0, a1, a2, a3
# CHECK-ASM: encoding: [0x2b,0xa5,0xc5,0x68]
matrix.multiply_drain a0, a1, a2, a3
