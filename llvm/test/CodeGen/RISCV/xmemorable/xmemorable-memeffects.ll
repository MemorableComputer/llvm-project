; Memory-effects gate (machine-pipeliner plan Task 1): the precise
; intrinsic memory attributes, end-to-end -- attribute truth, the
; RETIRED store-hoisting caveat (positive direction), and the walls
; that MUST hold (negative direction). See the sched-model findings
; doc's caveat and the pipeliner plan's design table.
;
; NOTE clang, not opt: the release-gate PATH carries no opt binary
; (llvm-toolchain-release.yml builds only clang/llc/llvm-mc/
; llvm-objdump/FileCheck/not/count), so the IR-level RUNs drive
; clang's own pipeline over IR input; its -O2 contains early-cse,
; gvn, globalopt and dse, so the walls below are tested against a
; STRICT superset of the individual passes.
; RUN: clang --target=riscv64 -S -emit-llvm -x ir %s -o - \
; RUN:   | FileCheck --check-prefix=ATTRS %s
; RUN: clang --target=riscv64 -O2 -S -emit-llvm -x ir %s -o - \
; RUN:   | FileCheck --check-prefix=O2 %s
; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - \
; RUN:   | FileCheck --check-prefix=ORDER %s

@score_region = global [64 x float] zeroinitializer
@prob_region = internal global [64 x i8] zeroinitializer

; THE CAVEAT RETIRED: the load from the score region is CSE'd ACROSS
; the quantize-store (argmem is noalias-elsewhere, inaccessiblemem
; never aliases IR memory). At the old blanket attrs this call was an
; unknown-memory wall and the second load survived (measured).
define <vscale x 2 x float> @hoist_across_quantize_store(<vscale x 2 x float> %v, ptr noalias %data, ptr noalias %scale) {
  %a = load <vscale x 2 x float>, ptr @score_region, align 64
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float> %v, ptr %data, ptr %scale, i64 16)
  %b = load <vscale x 2 x float>, ptr @score_region, align 64
  %s = fadd <vscale x 2 x float> %a, %b
  ret <vscale x 2 x float> %s
}
; O2-LABEL: @hoist_across_quantize_store(
; O2: load <vscale x 2 x float>
; O2-NOT: load
; O2: fadd

; WALL: identical vappend calls must BOTH survive (the
; inaccessiblemem write is the CSE anchor -- IntrReadMem here was the
; PR #21 measured miscompile).
; O2-LABEL: @vappend_pair_survives(
; O2: call void @llvm.riscv.memorable.vappend(ptr
; O2: call void @llvm.riscv.memorable.vappend(ptr
define void @vappend_pair_survives(ptr %src) {
  call void @llvm.riscv.memorable.vappend(ptr %src)
  call void @llvm.riscv.memorable.vappend(ptr %src)
  ret void
}

; WALL: a quantize-store whose data region is a store-only INTERNAL
; global must survive the O2 pipeline (globalopt/dse included) -- the
; inaccessiblemem:write half (the mirror scale bank) keeps the call
; alive where a pure argmem store could be reasoned away.
; O2-LABEL: @quantize_store_only_global(
; O2: call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(
define void @quantize_store_only_global(<vscale x 2 x float> %v) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float> %v, ptr @prob_region, ptr null, i64 16)
  ret void
}

; WALL: IR order store.fp4 -> drain -> tile.load survives -O2 into
; the final asm (ordering-edge audit items 1 and 2: unknown-store vs
; unknown-memory call, then unknown-memory call vs MMO load).
define <vscale x 8 x float> @wall_order(<vscale x 2 x float> %v, ptr %data, ptr %scale, i64 %desc, i64 %a, i64 %b, i64 %c, ptr addrspace(1) %row) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float> %v, ptr %data, ptr %scale, i64 16)
  call void @llvm.riscv.memorable.matrix.multiply.drain(i64 %desc, i64 %a, i64 %b, i64 %c)
  %t = load <vscale x 8 x float>, ptr addrspace(1) %row, align 64
  ret <vscale x 8 x float> %t
}
; ORDER-LABEL: wall_order:
; ORDER: store.fp4.e8m0
; ORDER: matrix.multiply_drain
; ORDER: tile.load

; ATTRIBUTE TRUTH (the parser materializes intrinsic attributes from
; the fork's own tablegen, so these pin IntrinsicsRISCVXMemorable.td's
; derived memory effects exactly; the tbuf pair shares ONE group by
; variable reuse, and the drain group's end-of-line anchor pins "no
; memory attribute at all").
declare <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float>, <vscale x 2 x float>, i64)
declare void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float>, ptr, ptr, i64)
declare void @llvm.riscv.memorable.vappend(ptr)
declare void @llvm.riscv.memorable.store.transposed(i64 immarg, ptr)
declare void @llvm.riscv.memorable.matrix.multiply.drain(i64, i64, i64, i64)

; ATTRS: declare <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float>, <vscale x 2 x float>, i64) [[NOMEM:#[0-9]+]]
; ATTRS: declare void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float>, ptr, ptr, i64) [[WRONLY:#[0-9]+]]
; ATTRS: declare void @llvm.riscv.memorable.vappend(ptr) [[TBUF:#[0-9]+]]
; ATTRS: declare void @llvm.riscv.memorable.store.transposed(i64 immarg, ptr) [[TBUF]]
; ATTRS: declare void @llvm.riscv.memorable.matrix.multiply.drain(i64, i64, i64, i64) [[MACC:#[0-9]+]]
; ATTRS: attributes [[NOMEM]] = { {{.*}}memory(none){{.*}} }
; ATTRS: attributes [[WRONLY]] = { {{.*}}memory(argmem: write, inaccessiblemem: write){{.*}} }
; ATTRS: attributes [[TBUF]] = { {{.*}}memory(argmem: readwrite, inaccessiblemem: readwrite){{.*}} }
; ATTRS: attributes [[MACC]] = { nocallback nofree nosync nounwind willreturn }{{$}}
