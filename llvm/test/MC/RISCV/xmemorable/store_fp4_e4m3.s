# RUN: llvm-mc %s -triple=riscv64 -mattr=+xmemorable,+v -show-encoding \
# RUN:     | FileCheck -check-prefixes=CHECK-ASM,CHECK-ASM-AND-OBJ %s
# RUN: llvm-mc -filetype=obj -triple=riscv64 -mattr=+xmemorable,+v < %s \
# RUN:     | llvm-objdump --mattr=+xmemorable,+v -d - \
# RUN:     | FileCheck --check-prefix=CHECK-ASM-AND-OBJ %s

# CHECK-ASM-AND-OBJ: store.fp4.e4m3 v1, a0, a1
# CHECK-ASM: encoding: [0xab,0x10,0xb5,0x0c]
store.fp4.e4m3 v1, a0, a1
