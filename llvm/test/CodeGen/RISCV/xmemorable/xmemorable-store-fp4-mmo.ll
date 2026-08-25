; MachineMemOperand gate for the quantize store (machine-pipeliner
; ledger, THE FIX): the getTgtMemIntrinsic hook + SDNPMemOperand
; must put the DATA-bank write footprint on the MachineInstr, and
; that MMO must make the load-above-store reorder legal.
;
; NOTE llc only: neither RUN below is an IR-level pass result, so
; the memeffects gate's `clang -x ir` opt-substitute has nothing to
; contribute here. llc ships in the release image alongside clang
; and FileCheck (llvm-toolchain-release.yml's named ninja targets).
; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b \
; RUN:   -stop-after=finalize-isel %s -o - \
; RUN:   | FileCheck --check-prefix=MIR %s
; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 \
; RUN:   %s -o - | FileCheck --check-prefix=REORDER %s

; ---- (a) the MMO itself, at every LMUL ------------------------
;
; The footprint is 8 bytes per LMUL:
; the ISS (model/vector/vector_engine.h, VectorEngine::StoreFp4)
; writes vl/16 blocks of 8 packed-int4
; bytes, contiguously from the data pointer. The mirror scale-bank
; write is DELIBERATELY absent from the MMO (it lands in a separate
; bank at a derived address; the intrinsic's inaccessiblemem: write
; attribute is what carries it) -- do not "fix" that asymmetry.

define void @mmo_m1(<vscale x 2 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float> %v, ptr %data, ptr %scale, i64 16)
  ret void
}
declare void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv2f32.i64(<vscale x 2 x float>, ptr, ptr, i64)
; MIR-LABEL: name:{{ *}}mmo_m1
; MIR: PseudoXMV_STORE_FP4_E8M0_M1 {{.*}} :: (store (s64) into %ir.data

define void @mmo_m2(<vscale x 4 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv4f32.i64(<vscale x 4 x float> %v, ptr %data, ptr %scale, i64 32)
  ret void
}
declare void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv4f32.i64(<vscale x 4 x float>, ptr, ptr, i64)
; MIR-LABEL: name:{{ *}}mmo_m2
; MIR: PseudoXMV_STORE_FP4_E8M0_M2 {{.*}} :: (store (s128) into %ir.data

define void @mmo_m4(<vscale x 8 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv8f32.i64(<vscale x 8 x float> %v, ptr %data, ptr %scale, i64 64)
  ret void
}
declare void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv8f32.i64(<vscale x 8 x float>, ptr, ptr, i64)
; MIR-LABEL: name:{{ *}}mmo_m4
; MIR: PseudoXMV_STORE_FP4_E8M0_M4 {{.*}} :: (store (s256) into %ir.data
; MIR-SAME: , align 8)

define void @mmo_m8(<vscale x 16 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv16f32.i64(<vscale x 16 x float> %v, ptr %data, ptr %scale, i64 128)
  ret void
}
declare void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv16f32.i64(<vscale x 16 x float>, ptr, ptr, i64)
; MIR-LABEL: name:{{ *}}mmo_m8
; MIR: PseudoXMV_STORE_FP4_E8M0_M8 {{.*}} :: (store (s512) into %ir.data
; MIR-SAME: , align 8)

; ---- (b) the reorder the MMO unlocks --------------------------
;
; The store and the tile.load address provably distinct objects
; (both noalias), so with the MMO in place MachineInstr::mayAlias
; can separate them and the scheduler hoists the load above the
; store. Pre-fix the store had no MMO, mayAlias answered "may
; alias" unconditionally, and this order was pinned to program
; order -- that is the serial gap this whole plan chases.
define <vscale x 8 x float> @load_hoists_above_store(<vscale x 8 x float> %v, ptr noalias %data, ptr addrspace(1) noalias %row, <vscale x 8 x float> %shift) {
  call void @llvm.riscv.memorable.fp4.quantize.e8m0.nxv8f32.i64(<vscale x 8 x float> %v, ptr %data, ptr null, i64 64)
  %t = load <vscale x 8 x float>, ptr addrspace(1) %row, align 64
  %p = call <vscale x 8 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv8f32.i64(<vscale x 8 x float> %t, <vscale x 8 x float> %shift, i64 64)
  ret <vscale x 8 x float> %p
}
declare <vscale x 8 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv8f32.i64(<vscale x 8 x float>, <vscale x 8 x float>, i64)
; REORDER-LABEL: load_hoists_above_store:
; REORDER-NOT: store.fp4.e8m0
; REORDER: tile.load
; REORDER: store.fp4.e8m0
