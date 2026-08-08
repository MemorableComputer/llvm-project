# RUN: llvm-mc %s -triple=riscv64 -mattr=+xmemorable,+v -show-encoding \
# RUN:     | FileCheck -check-prefixes=CHECK-ASM,CHECK-ASM-AND-OBJ %s
# RUN: llvm-mc -filetype=obj -triple=riscv64 -mattr=+xmemorable,+v < %s \
# RUN:     | llvm-objdump --mattr=+xmemorable,+v -d - \
# RUN:     | FileCheck --check-prefix=CHECK-ASM-AND-OBJ %s

# CHECK-ASM-AND-OBJ: vappend a0
# CHECK-ASM: encoding: [0x2b,0x10,0x05,0x00]
vappend a0
