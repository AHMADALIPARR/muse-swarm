/*
 * worm_verifier.h — the C node's header.
 *
 * How a node header works here: it is the contract between the
 * three sides of the verifier — the Erlang oracle that sends
 * requests, the C node that carries them, and the Lean 4 proof
 * library that answers. Anything all three must agree on lives
 * in this file and nowhere else: node identity, the wire
 * layout of the block, the message shapes, and the FFI
 * prototype. Change the protocol, you change the header, and
 * every side recompiles against the new contract.
 *
 *   gcc -O2 -I<erl_interface>/include -I<lean>/include \
 *       lean_verifier_node.c Transition.c \
 *       -L<erl_interface>/lib -lei -L<lean>/lib/lean -lleanshared
 */
#ifndef WORM_VERIFIER_H
#define WORM_VERIFIER_H

#include <stdint.h>
#include <stddef.h>
#include "ei.h"
#include "lean/lean.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ----------------------------------------------------------------
 * 1. Node identity.
 *
 * The short name the distribution knows this process by and the
 * name Erlang addresses on it. The COOKIE VALUE is never in
 * source: the skeleton's "secret_worm_cookie" is the test
 * cookie; production reads ~/.erlang.cookie, exactly like every
 * other Erlang node.
 * ---------------------------------------------------------------- */
#define WORM_VERIFIER_NODE_NAME   "lean_verifier"
#define WORM_VERIFIER_COOKIE_ENV  "WORM_COOKIE"   /* env override, tests only */

/* ----------------------------------------------------------------
 * 2. The WormBlock wire layout (180 bytes, shared with the Rust
 * runtime and the Erlang lean_ffi module — bus/worm.hrl).
 * ---------------------------------------------------------------- */
#define WORM_BLOCK_SIZE        180
#define WORM_PREV_HASH_OFF       0    /* 32 bytes: prev seal      */
#define WORM_NODE_ID_OFF        32    /* 16 bytes: node id        */
#define WORM_TASK_HASH_OFF      48    /* 32 bytes                 */
#define WORM_PAYLOAD_HASH_OFF   80    /* 32 bytes                 */
#define WORM_ENERGY_OFF        112    /* 4 bytes: f32 LE bits     */
#define WORM_SIGNATURE_OFF     116    /* 64 bytes: Ed25519        */
#define WORM_TAIL_SIZE          32

/* ----------------------------------------------------------------
 * 3. The request/reply protocol (Erlang external term format).
 *
 *   request : {Pid, ExpectedTail :: binary(32),
 *              ExpectedEnergy :: integer,
 *              Block :: binary(180)}
 *   reply   : {proof_result, Bool}
 *
 * ExpectedEnergy is the energy ceiling of the transition: the
 * block's energy bit pattern must not exceed it (the
 * Hamiltonian only descends).
 * ---------------------------------------------------------------- */
#define WORM_REQ_ARITY      4
#define WORM_REPLY_ATOM     "proof_result"

/* ----------------------------------------------------------------
 * 4. The FFI exported from the Lean 4 proofs.
 *
 * worm/Transition.lean marks leanVerifyTransition with
 * @[export lean_verify_transition]. Lean's export ABI passes
 * ByteArrays as lean_object*, so this is the true prototype —
 * raw pointers would compile in C and corrupt the call.
 *
 *   uint8 lean_verify_transition(tail, energy_ceiling, block)
 *     tail           : lean_object*  ByteArray, 32 bytes
 *     energy_ceiling : uint64_t      (see the ceiling note in
 *                                     Transition.lean: energies
 *                                     are non-negative, so the
 *                                     int64 on the wire maps
 *                                     losslessly; the node
 *                                     refuses a negative ceiling
 *                                     before calling)
 *     block          : lean_object*  ByteArray, 180 bytes
 *     returns        : 1 iff admissible, else 0
 * ---------------------------------------------------------------- */
uint8_t lean_verify_transition(lean_object *expected_tail,
                               uint64_t expected_energy,
                               lean_object *block);

/* The raw-pointer wrapper the node itself calls — the shape the
 * skeleton declared, under its own name. It builds the Lean
 * ByteArrays, crosses the boundary, and releases them. */
uint8_t worm_verify_transition_bytes(const uint8_t *expected_tail,
                                     int64_t expected_energy,
                                     const uint8_t *block);

#ifdef __cplusplus
}
#endif

#endif /* WORM_VERIFIER_H */
