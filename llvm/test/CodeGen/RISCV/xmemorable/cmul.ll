; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define i64 @f(i64 %rs1, i64 %rs2) {
  %r = call i64 @llvm.riscv.memorable.cmul(i64 %rs1, i64 %rs2)
  ret i64 %r
}
declare i64 @llvm.riscv.memorable.cmul(i64, i64)

; CHECK: cmul
