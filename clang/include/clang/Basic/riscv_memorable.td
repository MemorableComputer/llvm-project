//==--- riscv_memorable.td - RISC-V Memorable Xmemorable builtin list -----------===//
//
//  Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
//  See https://llvm.org/LICENSE.txt for license information.
//  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines the builtins for the Memorable decode-engine Xmemorable
// custom vector ops. See:
//
//     projects/decode_engine/docs/2026-08-04-llvm-xmemorable-td-backend-design.md
//
//===----------------------------------------------------------------------===//

include "riscv_vector_common.td"

let RequiredFeatures = ["xmemorable"], IRName = "memorable_vexp2diff_vv",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_vexp2diff_vv : RVVBuiltin<"vv", "vvv", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_int4_quantize_e8m0",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_int4_quantize_e8m0 : RVVBuiltin<"v", "uvPCe", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_int4_quantize_e4m3",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_int4_quantize_e4m3 : RVVBuiltin<"v", "uvPCe", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_int4_quantize_e8m3",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_int4_quantize_e8m3 : RVVBuiltin<"v", "uvPCe", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_vappend",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_vappend : RVVBuiltin<"", "0PCe", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_store_transposed",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_store_transposed : RVVBuiltin<"", "0KzPCe", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_matrix_multiply_drain",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_matrix_multiply_drain : RVVBuiltin<"", "0uuuu", "i">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_vexp2diff_fx",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_vexp2diff_fx : RVVBuiltin<"v", "Uvvv", "f">;

let RequiredFeatures = ["xmemorable"], IRName = "memorable_cmul",
    HasMasked = false, HasVL = false, Log2LMUL = [0], HasBuiltinAlias = false in
  def mv_cmul : RVVBuiltin<"", "uuu", "i">;
