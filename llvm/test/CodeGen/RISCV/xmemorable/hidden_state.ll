; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define void @f(ptr %src, ptr %dst, i64 %desc, i64 %a, i64 %b, i64 %c) {
  call void @llvm.riscv.memorable.vappend(ptr %src)
  call void @llvm.riscv.memorable.vappend(ptr %src)
  call void @llvm.riscv.memorable.store.transposed(i64 3, ptr %dst)
  call void @llvm.riscv.memorable.store.transposed(i64 3, ptr %dst)
  call void @llvm.riscv.memorable.matrix.multiply.drain(i64 %desc, i64 %a, i64 %b, i64 %c)
  call void @llvm.riscv.memorable.matrix.multiply.drain(i64 %desc, i64 %a, i64 %b, i64 %c)
  ret void
}

declare void @llvm.riscv.memorable.vappend(ptr)
declare void @llvm.riscv.memorable.store.transposed(i64, ptr)
declare void @llvm.riscv.memorable.matrix.multiply.drain(i64, i64, i64, i64)

; CHECK: vappend
; CHECK: vappend
; CHECK: store.transposed
; CHECK: store.transposed
; CHECK: matrix.multiply_drain
; CHECK: matrix.multiply_drain
