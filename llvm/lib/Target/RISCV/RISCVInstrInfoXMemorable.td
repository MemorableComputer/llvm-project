//===-- RISCVInstrInfoXMemorable.td --------------------------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file describes the Memorable decode-engine custom vector extension
// (Xmemorable). It is the single home for all Xmemorable instruction, operand,
// and pattern definitions added in later tasks.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Encoding classes
//===----------------------------------------------------------------------===//

// CUSTOM1V (isa/vector.yaml): custom-1 vector-engine ops, funct3=0b001,
// funct6 in Inst{31-26}, mode bit in Inst{25}. asm map vd->[11:7],
// va(vs1)->[19:15], vb(vs2)->[24:20].
class XMVCustom1V<bits<6> funct6, bits<1> mode, dag outs, dag ins,
                  string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR> {
  bits<5> vs2;  bits<5> vs1;  bits<5> vd;
  let Inst{31-26} = funct6;
  let Inst{25}    = mode;
  let Inst{24-20} = vs2;
  let Inst{19-15} = vs1;
  let Inst{14-12} = 0b001;
  let Inst{11-7}  = vd;
  let Inst{6-0}   = 0b0101011;
}

// CUSTOM1 (isa/vector.yaml): custom-1 scalar-operand ops (e.g. tile.load),
// funct3=0b000, funct7 in Inst{31-25}, rs2 field Inst{24-20} = 0 (unused),
// rs1->[19:15], vd->[11:7]. Distinct from XMVCustom1V above (funct3=0b001,
// vector vs1/vs2 operands) — Task 8 reuses this class.
class XMVCustom1<bits<7> funct7, dag outs, dag ins,
                 string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR> {
  bits<5> rs1;  bits<5> vd;
  let Inst{31-25} = funct7;
  let Inst{24-20} = 0b00000;
  let Inst{19-15} = rs1;
  let Inst{14-12} = 0b000;
  let Inst{11-7}  = vd;
  let Inst{6-0}   = 0b0101011;
}

// CUSTOM1R4 (isa/matrix.yaml): custom-1 matrix multiply-family ops,
// funct3=0b010, R4-type (four register fields), funct2 in Inst{26-25}
// selects the family member. rd is a SOURCE (the descriptor), never
// written -- asm map: rd=desc, rs1=rsA, rs2=rsB, rs3=rsC (dest tile addr;
// reserved 0 on matrix.multiply, which has no rsC operand).
class XMVCustom1R4<bits<2> funct2, dag outs, dag ins,
                   string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR4> {
  bits<5> rs3;  bits<5> rs2;  bits<5> rs1;  bits<5> rd;
  let Inst{31-27} = rs3;
  let Inst{26-25} = funct2;
  let Inst{24-20} = rs2;
  let Inst{19-15} = rs1;
  let Inst{14-12} = 0b010;
  let Inst{11-7}  = rd;
  let Inst{6-0}   = 0b0101011;
}

// XMVCustom0R (isa/custom.yaml): custom-0 (0x0b) scalar R-type ops -- the
// one Xmemorable-backend op outside the custom-1 vector-engine block. Standard
// R-type GPR fields (rd/rs1/rs2); funct3 selects the family, funct7 the
// member within it (cmul today: funct3=0, funct7=0).
class XMVCustom0R<bits<3> funct3, bits<7> funct7, dag outs, dag ins,
                  string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR> {
  bits<5> rs2;  bits<5> rs1;  bits<5> rd;
  let Inst{31-25} = funct7;
  let Inst{24-20} = rs2;
  let Inst{19-15} = rs1;
  let Inst{14-12} = funct3;
  let Inst{11-7}  = rd;
  let Inst{6-0}   = 0b0001011;
}

//===----------------------------------------------------------------------===//
// Instructions
//===----------------------------------------------------------------------===//

// NOTE: deliberately NOT wrapped in `let DecoderNamespace = "XMemorable"`.
// Tried it (per the XCV/XAndes/XSpacemiT/Xqci custom-1 convention) and it
// broke the vexp2diff.vv disassembler round-trip (llvm-objdump printed
// `<unknown>` instead of the mnemonic): a new DecoderNamespace needs a new
// entry in the C++ table-dispatch array in RISCVDisassembler.cpp (see
// e.g. DecoderTableXCV32/XqciFeatureGroup there) — .td alone can't wire
// it up. Per task instructions, reverted rather than add C++; instructions
// stay in the default namespace, same as before this task.
// cmul (isa/custom.yaml): custom-0 (0x0b) scalar op, R-type, funct3=0,
// funct7=0 -- rd = complex-multiply(rs1, rs2), a pure GPR-to-GPR function
// (IntrNoMem). The only Xmemorable-backend op outside the custom-1
// vector-engine block; VL/VTYPE are irrelevant to it (see the Uses
// computation above).
let Predicates = [HasVendorXMemorable],
    hasSideEffects = 0, mayLoad = 0, mayStore = 0 in
def XMV_CMUL : XMVCustom0R<0x0, 0x0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
      "cmul", "$rd, $rs1, $rs2">;

// Hidden-state ops (task 8, findings §6 as revised by PR #21): these are
// the accepted-wall ops -- side-effecting by design, no MMO path, state
// (TBUF/MACC) the compiler cannot otherwise see. Instruction-side flags
// measured to be required by TableGen's consistency check for an
// [IntrHasSideEffects] intrinsic with no MMO-bearing Pat: hasSideEffects=1,
// mayLoad=1, mayStore=1 on all three ops (see NOTES.md for the trace).

// vappend (isa/vector.yaml): rs1 only, rd/vs2 fields unused (hardcoded 0).
// Reads mem BUT writes TBUF -- exactly the op where IntrReadMem would look
// right on the intrinsic side and silently miscompile (see the intrinsic
// comment); mirrored here by NOT giving this instruction a load Pat/MMO.
let Predicates = [HasVendorXMemorable], Defs = [TBUF], Uses = [TBUF, VL, VTYPE],
    hasSideEffects = 1, mayLoad = 1, mayStore = 1 in
def XMV_VAPPEND : XMVCustom1V<0x00, 0, (outs), (ins GPR:$vs1),
      "vappend", "$vs1"> {
  let vs2 = 0;
  let vd  = 0;
}

// store.transposed (isa/vector.yaml): "vs, rs1" with vs (the transpose-
// buffer column index, a plain immediate -- not a vector register) riding
// the vd field per the yaml asm map; vs2 unused (hardcoded 0).
let Predicates = [HasVendorXMemorable], Defs = [TBUF], Uses = [TBUF, VL, VTYPE],
    hasSideEffects = 1, mayLoad = 1, mayStore = 1 in
def XMV_STORE_TRANSPOSED : XMVCustom1V<0x01, 0,
      (outs), (ins uimm5:$vd, GPR:$vs1),
      "store.transposed", "$vd, $vs1"> {
  let vs2 = 0;
}

// store.int4.e8m0 (isa/vector.yaml): compute-fused store only -- legal
// solely as the stored value of an addrspace(2) store (see store_databank
// + the Pat below); the quantize intrinsic itself is [IntrNoMem] and has
// no standalone lowering. vd field carries the SOURCE vreg per the yaml
// asm map (vs->[11:7]); vs1/vs2 carry the data addr / scale-bank addr.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1 in
def XMV_STORE_INT4_E8M0 : XMVCustom1V<0x02, 0,
      (outs), (ins VR:$vd, GPR:$vs1, GPR:$vs2),
      "store.int4.e8m0", "$vd, $vs1, $vs2">;

// store.int4.e4m3 (isa/vector.yaml): same fused-store shape as
// store.int4.e8m0 above (data_bank + scale_bank via the shared
// store_databank PatFrag), E4M3 block-scale variant.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1 in
def XMV_STORE_INT4_E4M3 : XMVCustom1V<0x03, 0,
      (outs), (ins VR:$vd, GPR:$vs1, GPR:$vs2),
      "store.int4.e4m3", "$vd, $vs1, $vs2">;

// store.int4.e8m3 (isa/vector.yaml): same fused-store shape as
// store.int4.e8m0 above (data_bank + scale_bank via the shared
// store_databank PatFrag), E8M3 block-scale variant.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1 in
def XMV_STORE_INT4_E8M3 : XMVCustom1V<0x04, 0,
      (outs), (ins VR:$vd, GPR:$vs1, GPR:$vs2),
      "store.int4.e8m3", "$vd, $vs1, $vs2">;

let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 0 in
def XMV_VEXP2DIFF_VV : XMVCustom1V<0x05, 0,
      (outs VR:$vd), (ins VR:$vs1, VR:$vs2),
      "vexp2diff.vv", "$vd, $vs1, $vs2">;

// vexp2diff.fx (isa/vector.yaml): same CUSTOM1V shape as vexp2diff.vv
// above (funct6=0x06), but its intrinsic RESULT is an unsigned Q16.16
// fixed-point value in an i32 lane, not FP32 -- llvm_nxv2i32_ty (see
// IntrinsicsRISCVXMemorable.td) types the intrinsic and this op's Pat; the
// register class (VR) and both operand types (nxv2f32) are unchanged.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 0 in
def XMV_VEXP2DIFF_FX : XMVCustom1V<0x06, 0,
      (outs VR:$vd), (ins VR:$vs1, VR:$vs2),
      "vexp2diff.fx", "$vd, $vs1, $vs2">;

let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 1, mayStore = 0 in
def XMV_TILE_LOAD : XMVCustom1<0x3, (outs VRM4:$vd), (ins GPR:$rs1),
                               "tile.load", "$vd, $rs1">;

// tile.store (isa/vector.yaml): "vs, rs1" with vs (the row-group SOURCE,
// not a destination) riding the vd field per the yaml asm map -- the
// store-direction twin of tile.load above (also no standalone intrinsic; a
// bare IR `store` of <vscale x 8 x float> to addrspace(1) selects this via
// the store_tile PatFrag in the Patterns section below).
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1 in
def XMV_TILE_STORE : XMVCustom1<0x4, (outs), (ins VRM4:$vd, GPR:$rs1),
                               "tile.store", "$vd, $rs1">;

// matrix.multiply_drain (isa/matrix.yaml): R4-type, all-GPR operands
// including rd (the descriptor, a SOURCE -- never written); opcode 0x2b,
// funct3=0b010, funct2=0x0 (match 0x0000202b).
let Predicates = [HasVendorXMemorable], Defs = [MACC], Uses = [MACC],
    hasSideEffects = 1, mayLoad = 1, mayStore = 1 in
def XMV_MATRIX_MULTIPLY_DRAIN : XMVCustom1R4<0x0,
      (outs), (ins GPR:$rd, GPR:$rs1, GPR:$rs2, GPR:$rs3),
      "matrix.multiply_drain", "$rd, $rs1, $rs2, $rs3">;

//===----------------------------------------------------------------------===//
// Patterns
//===----------------------------------------------------------------------===//

def : Pat<(i64 (int_riscv_memorable_cmul GPR:$rs1, GPR:$rs2)),
          (XMV_CMUL GPR:$rs1, GPR:$rs2)>;

// Hidden-state ops (task 8): straight intrinsic -> instruction Pats, no
// MMO/fusion involved -- these are the accepted-wall ops (findings §5).
def : Pat<(int_riscv_memorable_vappend GPR:$vs1), (XMV_VAPPEND GPR:$vs1)>;

// ImmArg lowers the column operand to ISD::TargetConstant (timm), not
// ISD::Constant (imm) -- uimm5 is an ImmLeaf (matches imm only), so a bare
// `uimm5:$vd` (or bare `timm:$vd`, which carries NO range predicate at
// all) on the LHS either fails to match altogether or -- the bare-`timm`
// case, measured -- silently accepts and truncates an out-of-range column
// (e.g. intrinsic column 35 compiled to `store.transposed 35, a0` in the
// asm printer's operand text but encoded 35 & 0x1f = 3 in the actual
// instruction word, no diagnostic at all; m1/store_transposed_oob.ll is
// the pinned regression test for this). `xmv_uimm5_timm` restores the
// range check on the timm path (mirrors uimm5's own `isUInt<5>` predicate,
// just against the timm node instead of imm). RHS also spelled with the
// same `xmv_uimm5_timm` class (not bare `uimm5`) -- retyping the RHS to a
// *different* operand-class record than the LHS crashed llvm-tblgen's
// GlobalISel emitter (segfault in
// CopyConstantAsImmRenderer::emitRenderOpcodes while auto-importing a
// LHS-timm/RHS-uimm5 Pat); using the identical class on both sides avoids
// the mismatch and does not reintroduce the crash (verified).
def xmv_uimm5_timm : TImmLeaf<i64, [{return isUInt<5>(Imm);}]>;
def : Pat<(int_riscv_memorable_store_transposed xmv_uimm5_timm:$vd, GPR:$vs1),
          (XMV_STORE_TRANSPOSED xmv_uimm5_timm:$vd, GPR:$vs1)>;

// store.int4.e8m0 fused pattern: the quantize intrinsic's result is legal
// ONLY as the stored value of an addrspace(2) store -- there is no bare
// Pat for the intrinsic alone, so a non-fused use fails isel loudly (see
// m1/store_int4_bare.ll, per spec Sec 3.1).
def store_databank : PatFrag<(ops node:$val, node:$ptr),
                             (store node:$val, node:$ptr)> {
  let IsStore = true;
  let AddressSpaces = [2];
}
// AddedComplexity: without it this loses the ISel table's complexity-sort
// race to the generic SD (store-doubleword, ComplexPat-addressed) pattern
// -- confirmed by byte-offset tracing RISCVGenDAGISel.inc's single
// MatcherTable: SD's entry precedes ours in the STORE opcode's Scope list,
// so SD matches first, leaving the quantize intrinsic node orphaned and
// unselectable. Same fix load_tile needed above (task 5) for the same
// reason: a plain scalar op can out-rank a fused custom pattern here.
let AddedComplexity = 20 in
def : Pat<(store_databank (i64 (int_riscv_memorable_int4_quantize_e8m0
                                  nxv2f32:$v, GPR:$scale)), GPR:$data),
          (XMV_STORE_INT4_E8M0 VR:$v, GPR:$data, GPR:$scale)>;

// store.int4.e4m3: reuses the store_databank PatFrag defined just above
// (store.int4.e8m0) -- same addrspace, same fused-store contract, only the
// quantize intrinsic and the destination instruction differ.
let AddedComplexity = 20 in
def : Pat<(store_databank (i64 (int_riscv_memorable_int4_quantize_e4m3
                                  nxv2f32:$v, GPR:$scale)), GPR:$data),
          (XMV_STORE_INT4_E4M3 VR:$v, GPR:$data, GPR:$scale)>;

// store.int4.e8m3: reuses the store_databank PatFrag defined above
// (store.int4.e8m0) -- same addrspace, same fused-store contract, only the
// quantize intrinsic and the destination instruction differ.
let AddedComplexity = 20 in
def : Pat<(store_databank (i64 (int_riscv_memorable_int4_quantize_e8m3
                                  nxv2f32:$v, GPR:$scale)), GPR:$data),
          (XMV_STORE_INT4_E8M3 VR:$v, GPR:$data, GPR:$scale)>;

def : Pat<(nxv2f32 (int_riscv_memorable_vexp2diff_vv nxv2f32:$va, nxv2f32:$vb)),
          (XMV_VEXP2DIFF_VV VR:$va, VR:$vb)>;

def : Pat<(nxv2i32 (int_riscv_memorable_vexp2diff_fx nxv2f32:$va, nxv2f32:$vb)),
          (XMV_VEXP2DIFF_FX VR:$va, VR:$vb)>;

def load_tile : PatFrag<(ops node:$ptr), (load node:$ptr)> {
  let IsLoad = true;
  let AddressSpaces = [1];
}
let AddedComplexity = 20 in
def : Pat<(nxv8f32 (load_tile GPR:$rs1)), (XMV_TILE_LOAD GPR:$rs1)>;

// tile.store: the store-direction twin of tile.load's load_tile PatFrag
// above -- same AddedComplexity race (a plain scalar/vector store pattern
// can out-rank a fused/custom one here; see store_databank below for the
// store.int4 family's instance of the identical race), same fix.
def store_tile : PatFrag<(ops node:$val, node:$ptr), (store node:$val, node:$ptr)> {
  let IsStore = true;
  let AddressSpaces = [1];
}
let AddedComplexity = 20 in
def : Pat<(store_tile (nxv8f32 VRM4:$vd), GPR:$rs1),
          (XMV_TILE_STORE VRM4:$vd, GPR:$rs1)>;

def : Pat<(int_riscv_memorable_matrix_multiply_drain
              GPR:$rd, GPR:$rs1, GPR:$rs2, GPR:$rs3),
          (XMV_MATRIX_MULTIPLY_DRAIN GPR:$rd, GPR:$rs1, GPR:$rs2, GPR:$rs3)>;
