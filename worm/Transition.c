// Lean compiler output
// Module: Transition
// Imports: Init
#include <lean/lean.h>
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wunused-label"
#elif defined(__GNUC__) && !defined(__CLANG__)
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#endif
#ifdef __cplusplus
extern "C" {
#endif
LEAN_EXPORT uint8_t lean_verify_transition(lean_object*, uint64_t, lean_object*);
lean_object* lean_mk_empty_array_with_capacity(lean_object*);
lean_object* lean_uint32_to_nat(uint32_t);
LEAN_EXPORT lean_object* l_Worm_admissible___boxed(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* l_Worm_instDecidableEqBlock___boxed(lean_object*, lean_object*);
uint32_t lean_uint8_to_uint32(uint8_t);
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____boxed(lean_object*, lean_object*);
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_chainValid_match__1_splitter___rarg___boxed(lean_object*, lean_object*, lean_object*);
lean_object* l_List_getD___rarg(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1___boxed(lean_object*, lean_object*);
LEAN_EXPORT lean_object* l_leanVerifyTransition___boxed(lean_object*, lean_object*, lean_object*);
lean_object* lean_uint64_to_nat(uint64_t);
LEAN_EXPORT uint8_t l_Worm_chainValid(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT uint8_t l_Worm_admissible(lean_object*, lean_object*, lean_object*);
lean_object* lean_array_to_list(lean_object*, lean_object*);
LEAN_EXPORT lean_object* l_Worm_blockOfWire(lean_object*);
LEAN_EXPORT uint8_t l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1(lean_object*, lean_object*);
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_chainValid_match__1_splitter___rarg(lean_object*, lean_object*, lean_object*);
lean_object* lean_byte_array_data(lean_object*);
uint8_t lean_nat_dec_eq(lean_object*, lean_object*);
lean_object* l_List_takeTR_go___rarg(lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_chainValid_match__1_splitter(lean_object*);
uint8_t lean_uint32_dec_eq(uint32_t, uint32_t);
uint32_t lean_uint32_shift_left(uint32_t, uint32_t);
LEAN_EXPORT uint8_t l_Worm_instDecidableEqBlock(lean_object*, lean_object*);
static lean_object* l_Worm_blockOfWire___closed__1;
uint32_t lean_uint32_add(uint32_t, uint32_t);
uint8_t lean_nat_dec_le(lean_object*, lean_object*);
LEAN_EXPORT uint8_t l___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24_(lean_object*, lean_object*);
lean_object* lean_byte_array_size(lean_object*);
uint8_t lean_uint8_dec_eq(uint8_t, uint8_t);
LEAN_EXPORT lean_object* l_Worm_chainValid___boxed(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT uint8_t l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1(lean_object* x_1, lean_object* x_2) {
_start:
{
if (lean_obj_tag(x_1) == 0)
{
if (lean_obj_tag(x_2) == 0)
{
uint8_t x_3; 
x_3 = 1;
return x_3;
}
else
{
uint8_t x_4; 
lean_dec(x_2);
x_4 = 0;
return x_4;
}
}
else
{
if (lean_obj_tag(x_2) == 0)
{
uint8_t x_5; 
lean_dec(x_1);
x_5 = 0;
return x_5;
}
else
{
lean_object* x_6; lean_object* x_7; lean_object* x_8; lean_object* x_9; uint8_t x_10; uint8_t x_11; uint8_t x_12; 
x_6 = lean_ctor_get(x_1, 0);
lean_inc(x_6);
x_7 = lean_ctor_get(x_1, 1);
lean_inc(x_7);
lean_dec(x_1);
x_8 = lean_ctor_get(x_2, 0);
lean_inc(x_8);
x_9 = lean_ctor_get(x_2, 1);
lean_inc(x_9);
lean_dec(x_2);
x_10 = lean_unbox(x_6);
lean_dec(x_6);
x_11 = lean_unbox(x_8);
lean_dec(x_8);
x_12 = lean_uint8_dec_eq(x_10, x_11);
if (x_12 == 0)
{
uint8_t x_13; 
lean_dec(x_9);
lean_dec(x_7);
x_13 = 0;
return x_13;
}
else
{
x_1 = x_7;
x_2 = x_9;
goto _start;
}
}
}
}
}
LEAN_EXPORT uint8_t l___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24_(lean_object* x_1, lean_object* x_2) {
_start:
{
lean_object* x_3; uint32_t x_4; lean_object* x_5; uint32_t x_6; uint8_t x_7; 
x_3 = lean_ctor_get(x_1, 0);
lean_inc(x_3);
x_4 = lean_ctor_get_uint32(x_1, sizeof(void*)*1);
lean_dec(x_1);
x_5 = lean_ctor_get(x_2, 0);
lean_inc(x_5);
x_6 = lean_ctor_get_uint32(x_2, sizeof(void*)*1);
lean_dec(x_2);
x_7 = l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1(x_3, x_5);
if (x_7 == 0)
{
uint8_t x_8; 
x_8 = 0;
return x_8;
}
else
{
uint8_t x_9; 
x_9 = lean_uint32_dec_eq(x_4, x_6);
return x_9;
}
}
}
LEAN_EXPORT lean_object* l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1___boxed(lean_object* x_1, lean_object* x_2) {
_start:
{
uint8_t x_3; lean_object* x_4; 
x_3 = l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1(x_1, x_2);
x_4 = lean_box(x_3);
return x_4;
}
}
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____boxed(lean_object* x_1, lean_object* x_2) {
_start:
{
uint8_t x_3; lean_object* x_4; 
x_3 = l___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24_(x_1, x_2);
x_4 = lean_box(x_3);
return x_4;
}
}
LEAN_EXPORT uint8_t l_Worm_instDecidableEqBlock(lean_object* x_1, lean_object* x_2) {
_start:
{
uint8_t x_3; 
x_3 = l___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24_(x_1, x_2);
return x_3;
}
}
LEAN_EXPORT lean_object* l_Worm_instDecidableEqBlock___boxed(lean_object* x_1, lean_object* x_2) {
_start:
{
uint8_t x_3; lean_object* x_4; 
x_3 = l_Worm_instDecidableEqBlock(x_1, x_2);
x_4 = lean_box(x_3);
return x_4;
}
}
LEAN_EXPORT uint8_t l_Worm_admissible(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
lean_object* x_4; uint8_t x_5; 
x_4 = lean_ctor_get(x_3, 0);
lean_inc(x_4);
x_5 = l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1(x_4, x_1);
if (x_5 == 0)
{
uint8_t x_6; 
lean_dec(x_3);
x_6 = 0;
return x_6;
}
else
{
uint32_t x_7; lean_object* x_8; uint8_t x_9; 
x_7 = lean_ctor_get_uint32(x_3, sizeof(void*)*1);
lean_dec(x_3);
x_8 = lean_uint32_to_nat(x_7);
x_9 = lean_nat_dec_le(x_8, x_2);
lean_dec(x_8);
return x_9;
}
}
}
LEAN_EXPORT lean_object* l_Worm_admissible___boxed(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
uint8_t x_4; lean_object* x_5; 
x_4 = l_Worm_admissible(x_1, x_2, x_3);
lean_dec(x_2);
x_5 = lean_box(x_4);
return x_5;
}
}
LEAN_EXPORT uint8_t l_Worm_chainValid(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
if (lean_obj_tag(x_3) == 0)
{
uint8_t x_4; 
lean_dec(x_2);
lean_dec(x_1);
x_4 = 1;
return x_4;
}
else
{
lean_object* x_5; lean_object* x_6; lean_object* x_7; uint8_t x_8; 
x_5 = lean_ctor_get(x_3, 0);
lean_inc(x_5);
x_6 = lean_ctor_get(x_3, 1);
lean_inc(x_6);
lean_dec(x_3);
x_7 = lean_ctor_get(x_5, 0);
lean_inc(x_7);
x_8 = l_List_hasDecEq___at___private_Transition_0__Worm_decEqBlock____x40_Transition___hyg_24____spec__1(x_7, x_2);
if (x_8 == 0)
{
uint8_t x_9; 
lean_dec(x_6);
lean_dec(x_5);
lean_dec(x_1);
x_9 = 0;
return x_9;
}
else
{
lean_object* x_10; 
lean_inc(x_1);
x_10 = lean_apply_1(x_1, x_5);
x_2 = x_10;
x_3 = x_6;
goto _start;
}
}
}
}
LEAN_EXPORT lean_object* l_Worm_chainValid___boxed(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
uint8_t x_4; lean_object* x_5; 
x_4 = l_Worm_chainValid(x_1, x_2, x_3);
x_5 = lean_box(x_4);
return x_5;
}
}
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_chainValid_match__1_splitter___rarg(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
if (lean_obj_tag(x_1) == 0)
{
lean_dec(x_3);
lean_inc(x_2);
return x_2;
}
else
{
lean_object* x_4; lean_object* x_5; lean_object* x_6; 
x_4 = lean_ctor_get(x_1, 0);
lean_inc(x_4);
x_5 = lean_ctor_get(x_1, 1);
lean_inc(x_5);
lean_dec(x_1);
x_6 = lean_apply_2(x_3, x_4, x_5);
return x_6;
}
}
}
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_chainValid_match__1_splitter(lean_object* x_1) {
_start:
{
lean_object* x_2; 
x_2 = lean_alloc_closure((void*)(l___private_Transition_0__Worm_chainValid_match__1_splitter___rarg___boxed), 3, 0);
return x_2;
}
}
LEAN_EXPORT lean_object* l___private_Transition_0__Worm_chainValid_match__1_splitter___rarg___boxed(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
lean_object* x_4; 
x_4 = l___private_Transition_0__Worm_chainValid_match__1_splitter___rarg(x_1, x_2, x_3);
lean_dec(x_2);
return x_4;
}
}
static lean_object* _init_l_Worm_blockOfWire___closed__1() {
_start:
{
lean_object* x_1; lean_object* x_2; 
x_1 = lean_unsigned_to_nat(0u);
x_2 = lean_mk_empty_array_with_capacity(x_1);
return x_2;
}
}
LEAN_EXPORT lean_object* l_Worm_blockOfWire(lean_object* x_1) {
_start:
{
lean_object* x_2; lean_object* x_3; lean_object* x_4; lean_object* x_5; lean_object* x_6; uint8_t x_7; lean_object* x_8; lean_object* x_9; lean_object* x_10; uint8_t x_11; uint32_t x_12; lean_object* x_13; lean_object* x_14; lean_object* x_15; uint8_t x_16; uint32_t x_17; uint32_t x_18; uint32_t x_19; uint32_t x_20; lean_object* x_21; lean_object* x_22; lean_object* x_23; uint8_t x_24; uint32_t x_25; uint32_t x_26; uint32_t x_27; uint32_t x_28; lean_object* x_29; lean_object* x_30; lean_object* x_31; uint8_t x_32; uint32_t x_33; uint32_t x_34; uint32_t x_35; uint32_t x_36; lean_object* x_37; 
x_2 = lean_byte_array_data(x_1);
x_3 = lean_array_to_list(lean_box(0), x_2);
x_4 = lean_unsigned_to_nat(32u);
x_5 = l_Worm_blockOfWire___closed__1;
lean_inc(x_3);
x_6 = l_List_takeTR_go___rarg(x_3, x_3, x_4, x_5);
x_7 = 0;
x_8 = lean_unsigned_to_nat(112u);
x_9 = lean_box(x_7);
x_10 = l_List_getD___rarg(x_3, x_8, x_9);
lean_dec(x_9);
x_11 = lean_unbox(x_10);
lean_dec(x_10);
x_12 = lean_uint8_to_uint32(x_11);
x_13 = lean_unsigned_to_nat(113u);
x_14 = lean_box(x_7);
x_15 = l_List_getD___rarg(x_3, x_13, x_14);
lean_dec(x_14);
x_16 = lean_unbox(x_15);
lean_dec(x_15);
x_17 = lean_uint8_to_uint32(x_16);
x_18 = 8;
x_19 = lean_uint32_shift_left(x_17, x_18);
x_20 = lean_uint32_add(x_12, x_19);
x_21 = lean_unsigned_to_nat(114u);
x_22 = lean_box(x_7);
x_23 = l_List_getD___rarg(x_3, x_21, x_22);
lean_dec(x_22);
x_24 = lean_unbox(x_23);
lean_dec(x_23);
x_25 = lean_uint8_to_uint32(x_24);
x_26 = 16;
x_27 = lean_uint32_shift_left(x_25, x_26);
x_28 = lean_uint32_add(x_20, x_27);
x_29 = lean_unsigned_to_nat(115u);
x_30 = lean_box(x_7);
x_31 = l_List_getD___rarg(x_3, x_29, x_30);
lean_dec(x_30);
lean_dec(x_3);
x_32 = lean_unbox(x_31);
lean_dec(x_31);
x_33 = lean_uint8_to_uint32(x_32);
x_34 = 24;
x_35 = lean_uint32_shift_left(x_33, x_34);
x_36 = lean_uint32_add(x_28, x_35);
x_37 = lean_alloc_ctor(0, 1, 4);
lean_ctor_set(x_37, 0, x_6);
lean_ctor_set_uint32(x_37, sizeof(void*)*1, x_36);
return x_37;
}
}
LEAN_EXPORT uint8_t lean_verify_transition(lean_object* x_1, uint64_t x_2, lean_object* x_3) {
_start:
{
lean_object* x_4; lean_object* x_5; uint8_t x_6; 
x_4 = lean_byte_array_size(x_3);
x_5 = lean_unsigned_to_nat(180u);
x_6 = lean_nat_dec_eq(x_4, x_5);
lean_dec(x_4);
if (x_6 == 0)
{
uint8_t x_7; 
lean_dec(x_3);
lean_dec(x_1);
x_7 = 0;
return x_7;
}
else
{
lean_object* x_8; lean_object* x_9; lean_object* x_10; lean_object* x_11; uint8_t x_12; 
x_8 = lean_byte_array_data(x_1);
x_9 = lean_array_to_list(lean_box(0), x_8);
x_10 = lean_uint64_to_nat(x_2);
x_11 = l_Worm_blockOfWire(x_3);
x_12 = l_Worm_admissible(x_9, x_10, x_11);
lean_dec(x_10);
if (x_12 == 0)
{
uint8_t x_13; 
x_13 = 0;
return x_13;
}
else
{
uint8_t x_14; 
x_14 = 1;
return x_14;
}
}
}
}
LEAN_EXPORT lean_object* l_leanVerifyTransition___boxed(lean_object* x_1, lean_object* x_2, lean_object* x_3) {
_start:
{
uint64_t x_4; uint8_t x_5; lean_object* x_6; 
x_4 = lean_unbox_uint64(x_2);
lean_dec(x_2);
x_5 = lean_verify_transition(x_1, x_4, x_3);
x_6 = lean_box(x_5);
return x_6;
}
}
lean_object* initialize_Init(uint8_t builtin, lean_object*);
static bool _G_initialized = false;
LEAN_EXPORT lean_object* initialize_Transition(uint8_t builtin, lean_object* w) {
lean_object * res;
if (_G_initialized) return lean_io_result_mk_ok(lean_box(0));
_G_initialized = true;
res = initialize_Init(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
l_Worm_blockOfWire___closed__1 = _init_l_Worm_blockOfWire___closed__1();
lean_mark_persistent(l_Worm_blockOfWire___closed__1);
return lean_io_result_mk_ok(lean_box(0));
}
#ifdef __cplusplus
}
#endif
