; RUN: not --crash llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o /dev/null 2>&1 | FileCheck %s

define i64 @f(<vscale x 2 x float> %v, ptr %scale) {
  %q = call i64 @llvm.riscv.memorable.int4.quantize.e8m0(<vscale x 2 x float> %v, ptr %scale)
  ret i64 %q
}
declare i64 @llvm.riscv.memorable.int4.quantize.e8m0(<vscale x 2 x float>, ptr)

; CHECK: LLVM ERROR: Cannot select: intrinsic %llvm.riscv.memorable.int4.quantize.e8m0
