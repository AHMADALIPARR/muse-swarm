// worm_seal_node.c — the Worm ledger's C node.
//
// A true Erlang C node (erl_interface / ei): it joins the
// distribution as a hidden node named wormseal@<host>, registers
// the name "seal_server", and answers {call, Pid, seal, Block}
// messages with {seal_result, Seal}, where Seal is the SHA-256
// of the block's 116-byte preimage — computed here, in C, over
// OpenSSL, byte-identical to the Rust WormBlock seal and the
// Erlang lean_ffi seal. Three implementations, one seal: that
// is the cross-check the custom shell displays.
//
// Build (on a machine with OTP's erl_interface + OpenSSL):
//   gcc -O2 -I<erl_interface>/include worm_seal_node.c
//       -L<erl_interface>/lib -lei -lcrypto -o worm_seal_node
// Run:
//   worm_seal_node <erlang-node> <cookie>
//   e.g. worm_seal_node worm@127.0.0.1 testcookie

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "ei.h"
#include <openssl/evp.h>

static void seal(const unsigned char *block180, unsigned char out[32]) {
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), NULL);
    EVP_DigestUpdate(ctx, block180, 116);   // the seal preimage
    unsigned int len = 0;
    EVP_DigestFinal_ex(ctx, out, &len);
    EVP_MD_CTX_free(ctx);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: worm_seal_node <erlang-node> <cookie>\n");
        return 2;
    }
    const char *erl_node = argv[1];
    const char *cookie = argv[2];

    // our own node name: wormseal@<same host part as the peer>
    const char *at = strchr(erl_node, '@');
    char my_node[256];
    snprintf(my_node, sizeof my_node, "wormseal@%s", at ? at + 1 : "127.0.0.1");

    ei_cnode ec;
    // xinit, not the plain init: the plain init mangles a full
    // "name@host" string on the wire (the peer closes before
    // sending handshake status — seen in the ei trace). xinit
    // takes host, alive name, and full node name separately.
    const char *host_part = at ? at + 1 : "127.0.0.1";
    if (ei_connect_xinit(&ec, host_part, "wormseal", my_node,
                         NULL, cookie, 0) < 0) {
        fprintf(stderr, "ei_connect_xinit failed\n");
        return 1;
    }
    int fd = ei_connect(&ec, (char *)erl_node);
    if (fd < 0) {
        fprintf(stderr, "ei_connect to %s failed (check epmd, node name, cookie)\n", erl_node);
        return 1;
    }
    // A C node has no rex: a REG_SEND addressed to the name
    // "seal_server" on this node arrives as ERL_REG_SEND with
    // msg.toname set — answering to that name is the whole
    // registration.
    fprintf(stderr, "worm_seal_node: connected as %s, answering to seal_server\n", my_node);
    // Announce ourselves to the registry on the Erlang node:
    // a C node has no rex, so its pid is the only address the
    // Erlang side can use — and only we know it.
    {
        ei_x_buff intro;
        ei_x_new_with_version(&intro);
        ei_x_encode_tuple_header(&intro, 3);
        ei_x_encode_atom(&intro, "cnode_up");
        ei_x_encode_atom(&intro, "seal_server");
        ei_x_encode_pid(&intro, ei_self(&ec));
        ei_reg_send(&ec, fd, "worm_registry", intro.buff, intro.index);
        ei_x_free(&intro);
    }


    ei_x_buff xbuf;
    ei_x_new(&xbuf);
    erlang_msg msg;
    for (;;) {
        int got = ei_xreceive_msg(fd, &msg, &xbuf);
        if (got == ERL_TICK) continue;
        if (got < 0) {
            fprintf(stderr, "ei_xreceive_msg failed\n");
            return 1;
        }
        if (msg.msgtype != ERL_REG_SEND && msg.msgtype != ERL_SEND) continue;
        if (msg.msgtype == ERL_REG_SEND && strcmp(msg.toname, "seal_server") != 0) continue;
        int index = 0, version = 0, arity = 0;
        char atom[256];
        erlang_pid pid;
        if (ei_decode_version(xbuf.buff, &index, &version) < 0) continue;
        if (ei_decode_tuple_header(xbuf.buff, &index, &arity) < 0 || arity != 4) continue;
        if (ei_decode_atom(xbuf.buff, &index, atom) < 0 || strcmp(atom, "call") != 0) continue;
        if (ei_decode_pid(xbuf.buff, &index, &pid) < 0) continue;
        if (ei_decode_atom(xbuf.buff, &index, atom) < 0 || strcmp(atom, "seal") != 0) continue;
        int type = 0, size = 0;
        if (ei_get_type(xbuf.buff, &index, &type, &size) < 0 || size != 180) continue;
        unsigned char block[180];
        long blen = 0;
        if (ei_decode_binary(xbuf.buff, &index, block, &blen) < 0 || blen != 180) continue;
        unsigned char digest[32];
        seal(block, digest);
        ei_x_buff reply;
        ei_x_new_with_version(&reply);
        ei_x_encode_tuple_header(&reply, 2);
        ei_x_encode_atom(&reply, "seal_result");
        ei_x_encode_binary(&reply, digest, 32);
        ei_send(fd, &pid, reply.buff, reply.index);
        ei_x_free(&reply);
    }
    return 0;
}
