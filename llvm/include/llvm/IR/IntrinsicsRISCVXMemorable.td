//===- IntrinsicsRISCVXMemorable.td - Xmemorable intrinsics -----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines all of the Memorable decode-engine vendor (Xmemorable)
// intrinsics for RISC-V.
//
//===----------------------------------------------------------------------===//

// Not predefined by Intrinsics.td (unlike llvm_anyvector_ty etc.); AArch64's
// SVE intrinsics alias their own fixed scalable-vector types the same way.
def llvm_nxv2f32_ty : LLVMType<nxv2f32>;
def llvm_nxv2i32_ty : LLVMType<nxv2i32>;

let TargetPrefix = "riscv" in {
  def int_riscv_memorable_cmul
      : DefaultAttrsIntrinsic<[llvm_i64_ty],
                              [llvm_i64_ty, llvm_i64_ty], [IntrNoMem]>;

  // Hidden-state ops (task 8, findings §6 as revised by PR #21): these
  // touch state the IR cannot see (TBUF/MACC) via a plain memory read (or
  // no memory access at all for the drain), so [IntrReadMem] would look
  // right and is NOT: readonly + identical args is CSE-able at the IR
  // level regardless of [IntrHasSideEffects] -- [IntrHasSideEffects] alone,
  // never [IntrReadMem], is the measured-correct shape for all three.
  def int_riscv_memorable_vappend
      : DefaultAttrsIntrinsic<[], [llvm_ptr_ty],
                              [IntrHasSideEffects]>;   // reads mem BUT writes TBUF: never IntrReadMem
  def int_riscv_memorable_store_transposed
      : DefaultAttrsIntrinsic<[], [llvm_i64_ty, llvm_ptr_ty],
                              [IntrHasSideEffects, ImmArg<ArgIndex<0>>]>;

  // Fused-only: legal solely as the stored value of an addrspace(2) store
  // (see the store_databank PatFrag + Pat in RISCVInstrInfoXMemorable.td).
  // Pure value producer (IntrNoMem) -- the scale pointer rides through to
  // the instruction's rs2 as a plain operand; per spec Sec 3.1 the
  // scale-bank slot is a pure function of the data address, so the data
  // store's MMO alone carries the ordering. Do NOT add IntrReadMem here.
  def int_riscv_memorable_int4_quantize_e8m0
      : DefaultAttrsIntrinsic<[llvm_i64_ty],
                              [llvm_nxv2f32_ty, llvm_ptr_ty], [IntrNoMem]>;
  def int_riscv_memorable_int4_quantize_e4m3
      : DefaultAttrsIntrinsic<[llvm_i64_ty],
                              [llvm_nxv2f32_ty, llvm_ptr_ty], [IntrNoMem]>;
  def int_riscv_memorable_int4_quantize_e8m3
      : DefaultAttrsIntrinsic<[llvm_i64_ty],
                              [llvm_nxv2f32_ty, llvm_ptr_ty], [IntrNoMem]>;

  def int_riscv_memorable_vexp2diff_vv
      : DefaultAttrsIntrinsic<[llvm_nxv2f32_ty],
                              [llvm_nxv2f32_ty, llvm_nxv2f32_ty], [IntrNoMem]>;
  def int_riscv_memorable_vexp2diff_fx
      : DefaultAttrsIntrinsic<[llvm_nxv2i32_ty],
                              [llvm_nxv2f32_ty, llvm_nxv2f32_ty], [IntrNoMem]>;

  def int_riscv_memorable_matrix_multiply_drain
      : DefaultAttrsIntrinsic<[], [llvm_i64_ty, llvm_i64_ty, llvm_i64_ty, llvm_i64_ty],
                              [IntrHasSideEffects]>;
} // TargetPrefix = "riscv"
