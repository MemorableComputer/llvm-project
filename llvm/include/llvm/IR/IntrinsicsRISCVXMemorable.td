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

let TargetPrefix = "riscv" in {
  // LMUL-polymorphic (framework) intrinsic shapes -- anyvector + VL, the
  // upstream RVV convention (cf. IntrinsicsRISCVXTHead.td); RISCVVIntrinsic
  // wires VLOperand into the backend's intrinsic-info table. No masked
  // forms: this machine has no mask support (isa/vector.yaml).
  class XMVBinaryVVUnMasked
      : DefaultAttrsIntrinsic<[llvm_anyvector_ty],
                              [LLVMMatchType<0>, LLVMMatchType<0>,
                               llvm_anyint_ty],
                              [IntrNoMem]>,
        RISCVVIntrinsic {
    let VLOperand = 2;
  }
  // f32 operands, same-LMUL i32 result (vexp2diff.fx's Q16.16 lanes --
  // isa/vector.yaml's result_type override, generalized per LMUL).
  class XMVBinaryVVFxUnMasked
      : DefaultAttrsIntrinsic<[llvm_anyvector_ty],
                              [llvm_anyvector_ty, LLVMMatchType<1>,
                               llvm_anyint_ty],
                              [IntrNoMem]>,
        RISCVVIntrinsic {
    let VLOperand = 2;
  }
  // Grouped quantize-store: void (value, data, scale, vl), directly
  // side-effecting -- vl/16 adjacent micro-blocks have no single-i64-
  // store/MMO model, so the data-bank pointer is an ordinary argument and
  // the old m1-only fused (IntrNoMem value + addrspace(2) store) contract
  // is retired. Never IntrWriteMem/IntrReadMem: the scale side lives in a
  // mirror bank the IR cannot see (the state trio's accepted-wall rule).
  class XMVStoreInt4UnMasked
      : DefaultAttrsIntrinsic<[],
                              [llvm_anyvector_ty, llvm_ptr_ty, llvm_ptr_ty,
                               llvm_anyint_ty],
                              [IntrHasSideEffects]>,
        RISCVVIntrinsic {
    let VLOperand = 3;
  }

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

  def int_riscv_memorable_int4_quantize_e8m0 : XMVStoreInt4UnMasked;
  def int_riscv_memorable_int4_quantize_e4m3 : XMVStoreInt4UnMasked;
  def int_riscv_memorable_int4_quantize_e8m3 : XMVStoreInt4UnMasked;

  def int_riscv_memorable_vexp2diff_vv : XMVBinaryVVUnMasked;
  def int_riscv_memorable_vexp2diff_fx : XMVBinaryVVFxUnMasked;

  def int_riscv_memorable_matrix_multiply_drain
      : DefaultAttrsIntrinsic<[], [llvm_i64_ty, llvm_i64_ty, llvm_i64_ty, llvm_i64_ty],
                              [IntrHasSideEffects]>;
} // TargetPrefix = "riscv"
