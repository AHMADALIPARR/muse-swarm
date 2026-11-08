#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include "ei.h"
#include "lean/lean.h"
#include "worm_verifier.h"

// The module initializer generated from worm/Transition.lean
// (Lean 4.12 shape: builtin flag + world token, IO result back).
lean_object *initialize_Transition(uint8_t builtin, lean_object *w);

// Lean 4.12's runtime bootstrap (declared by every generated
// main the same way). This is the call the skeleton's
// lean_initialize() names — the current API spells it so.
void lean_initialize_runtime_module(void);

/* The raw-pointer wrapper (worm_verifier.h §4): builds the
 * Lean ByteArrays, crosses the boundary, releases them. */
uint8_t worm_verify_transition_bytes(const uint8_t *expected_tail,
                                     int64_t expected_energy,
                                     const uint8_t *block) {
    if (expected_energy < 0) {
        // No non-negative energy descends to a negative bound;
        // the predicate would refuse — refuse here instead.
        return 0;
    }
    lean_object *tail_obj = lean_alloc_sarray(1, WORM_TAIL_SIZE, WORM_TAIL_SIZE);
    memcpy(lean_sarray_cptr(tail_obj), expected_tail, WORM_TAIL_SIZE);
    lean_object *block_obj = lean_alloc_sarray(1, WORM_BLOCK_SIZE, WORM_BLOCK_SIZE);
    memcpy(lean_sarray_cptr(block_obj), block, WORM_BLOCK_SIZE);
    uint8_t result = lean_verify_transition(tail_obj, (uint64_t)expected_energy, block_obj);
    lean_dec_ref(tail_obj);
    lean_dec_ref(block_obj);
    return result;
}

int main() {
    // 1. Initialize the Lean 4 runtime natively.
    // The skeleton's lean_initialize() is Lean 4.12's
    // lean_initialize_runtime_module() plus the generated
    // module initializer: run both, check the IO result, then
    // close initialization.
    lean_initialize_runtime_module();
    lean_object *init_res = initialize_Transition(1, lean_io_mk_world());
    if (!lean_io_result_is_ok(init_res)) {
        fprintf(stderr, "lean_verifier: Transition module init failed\n");
        return 1;
    }
    lean_dec_ref(init_res);
    lean_io_mark_end_initialization();

    // 2. Initialize the Erlang C-Node
    ei_cnode ec;
    // Name: lean_verifier, Cookie: secret_worm_cookie
    // (the WORM_COOKIE env var overrides the test cookie; the
    // production cookie lives in ~/.erlang.cookie, never in code)
    const char *cookie = getenv("WORM_COOKIE");
    if (cookie == NULL) cookie = "secret_worm_cookie";
    // The node binds localhost (zero network exposure), so its
    // distribution name is lean_verifier@127.0.0.1: ei's plain
    // init would take the OS hostname for the host part, which
    // Erlang rejects when it is not a legal DNS name (this VM's
    // hostname contains an underscore), and passing the full
    // name to the plain init stores it as the alive name. The
    // xinit form takes hostname, alive name, and full node name
    // separately — exact names, no guessing. WORM_VERIFIER_HOST
    // overrides the host part on the fleet.
    const char *host = getenv("WORM_VERIFIER_HOST");
    if (host == NULL) host = "127.0.0.1";
    char node_name[256];
    snprintf(node_name, sizeof node_name, "lean_verifier@%s", host);
    if (ei_connect_xinit(&ec, host, "lean_verifier", node_name,
                         NULL, cookie, 0) < 0) {
        exit(1);
    }

    // 3. Bind to localhost (Zero network exposure)
    // ei_listen's port is an in/out parameter: 0 asks for an
    // ephemeral port, published through epmd under our name.
    int port = 0;
    int listen_fd = ei_listen(&ec, &port, 1);
    if (listen_fd < 0) {
        fprintf(stderr, "lean_verifier: ei_listen failed\n");
        return 1;
    }
    // In OTP's ei, listening and publishing are separate calls:
    // ei_publish registers our name + port with epmd so the
    // Erlang side can find and connect to us.
    if (ei_publish(&ec, port) < 0) {
        fprintf(stderr, "lean_verifier: ei_publish failed\n");
        return 1;
    }
    ErlConnect conn;
    int fd = ei_accept(&ec, listen_fd, &conn);
    if (fd < 0) {
        fprintf(stderr, "lean_verifier: ei_accept failed\n");
        return 1;
    }
    fprintf(stderr, "lean_verifier: connected to %s\n", conn.nodename);
    // Announce ourselves to the registry on the Erlang node:
    // a C node has no rex, so its pid is the only address the
    // Erlang side can use — and only we know it.
    {
        ei_x_buff intro;
        ei_x_new_with_version(&intro);
        ei_x_encode_tuple_header(&intro, 3);
        ei_x_encode_atom(&intro, "cnode_up");
        ei_x_encode_atom(&intro, "lean_verifier");
        ei_x_encode_pid(&intro, ei_self(&ec));
        ei_reg_send(&ec, fd, "worm_registry", intro.buff, intro.index);
        ei_x_free(&intro);
    }


    ei_x_buff buf;
    ei_x_new(&buf);
    erlang_msg msg;

    // 4. The Event Loop
    while (1) {
        int status = ei_xreceive_msg(fd, &msg, &buf);
        if (status == ERL_TICK) continue;
        if (status < 0) break; // Connection dropped, exit and let OTP respawn

        // Decode the incoming Erlang Tuple: {Pid, ExpectedTail, Energy, BlockBinary}
        int index = 0;
        int version;
        ei_decode_version(buf.buff, &index, &version);

        int arity;
        ei_decode_tuple_header(buf.buff, &index, &arity);
        if (arity != WORM_REQ_ARITY) continue;

        erlang_pid reply_pid;
        ei_decode_pid(buf.buff, &index, &reply_pid);

        // ExpectedTail: binary(32)
        int type = 0, size = 0;
        uint8_t expected_tail[WORM_TAIL_SIZE];
        if (ei_get_type(buf.buff, &index, &type, &size) < 0 || size != WORM_TAIL_SIZE) continue;
        long tail_len = 0;
        if (ei_decode_binary(buf.buff, &index, expected_tail, &tail_len) < 0) continue;

        // Energy: integer (the ceiling on the block's energy)
        long energy_long = 0;
        if (ei_decode_long(buf.buff, &index, &energy_long) < 0) continue;
        int64_t expected_energy = (int64_t)energy_long;

        // BlockBinary: binary(180)
        uint8_t block[WORM_BLOCK_SIZE];
        if (ei_get_type(buf.buff, &index, &type, &size) < 0 || size != WORM_BLOCK_SIZE) continue;
        long block_len = 0;
        if (ei_decode_binary(buf.buff, &index, block, &block_len) < 0) continue;

        // 5. Cross the boundary to Lean 4
        uint8_t proof_result = worm_verify_transition_bytes(expected_tail, expected_energy, block);

        // 6. Encode the boolean response back to Erlang BERT
        ei_x_buff res_buf;
        ei_x_new_with_version(&res_buf);
        ei_x_encode_tuple_header(&res_buf, 2);
        ei_x_encode_atom(&res_buf, WORM_REPLY_ATOM);
        ei_x_encode_boolean(&res_buf, proof_result);

        // 7. Send asynchronously back to BBQBADDIE
        ei_send(fd, &reply_pid, res_buf.buff, res_buf.index);
        ei_x_free(&res_buf);
    }

    return 0;
}
