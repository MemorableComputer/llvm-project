# RUN: llvm-mc %s -triple=riscv64 -mattr=+xmemorable,+v -show-encoding \
# RUN:     | FileCheck --check-prefix=CHECK-ASM %s
# RUN: llvm-mc -filetype=obj -triple=riscv64 -mattr=+xmemorable,+v < %s \
# RUN:     | llvm-objdump --mattr=+xmemorable,+v -d - \
# RUN:     | FileCheck --check-prefix=CHECK-OBJ %s

# CHECK-ASM: store.transposed 3, a0
# CHECK-ASM: encoding: [0xab,0x11,0x05,0x04]
store.transposed 3, a0
# CHECK-OBJ: store.transposed 0x3, a0
