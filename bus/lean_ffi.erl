-module(lean_ffi).
-include("worm.hrl").

%% The transition verifier. On bbqbaddie this module is the
%% Erlang face of the Lean 4 transition proof: verify_transition
%% is backed by the C ABI extracted from the Lean formalization
%% (worm/Transition.lean in this repo), reached through the C
%% node. In this workspace the same checks run natively —
%% identical byte layouts, identical gate order:
%%
%%   1. sequence gate: seq must be tail_seq + 1 (the oracle-side
%%      mirror of JetStream's Nats-Expected-Last-Sequence: two
%%      appends racing at the same expected sequence cannot
%%      both pass, so the chain cannot fork);
%%   2. chain: prev_hash must equal the current tail seal;
%%   3. signature: the node's Ed25519 signature over the seal,
%%      checked against the registered node key.
%%
%% The seal itself is SHA-256 over the 116-byte preimage
%% PrevHash || NodeId || TaskHash || PayloadHash || EnergyLE —
%% the same bytes the Rust WormBlock.compute_seal hashes and
%% the C node (bus/cnode) computes.

-export([verify_transition/1, compute_seal/1,
         encode_payload/1, decode_payload/1, block_binary/1]).

compute_seal(#block{prev_hash = P, node_id = N, task_hash = T,
                    payload_hash = H, energy = E}) ->
    crypto:hash(sha256, <<P/binary, N/binary, T/binary, H/binary,
                          E:32/float-little>>);
compute_seal(BlockBin) when is_binary(BlockBin), byte_size(BlockBin) =:= 180 ->
    crypto:hash(sha256, binary:part(BlockBin, 0, 116)).

block_binary(#block{prev_hash = P, node_id = N, task_hash = T,
                    payload_hash = H, energy = E, signature = S}) ->
    <<P/binary, N/binary, T/binary, H/binary, E:32/float-little, S/binary>>.

encode_payload(#block{subject = Subj, seq = Seq, msg_id = MsgId} = Block) ->
    B = block_binary(Block),
    <<(byte_size(Subj)):16, Subj/binary, Seq:64, (byte_size(MsgId)):16,
      MsgId/binary, B/binary>>.

decode_payload(<<SubjLen:16, Rest/binary>>) ->
    <<Subj:SubjLen/binary, Seq:64, MsgIdLen:16, Rest2/binary>> = Rest,
    <<MsgId:MsgIdLen/binary, B:180/binary>> = Rest2,
    <<P:32/binary, N:16/binary, T:32/binary, H:32/binary,
      E:32/float-little, S:64/binary>> = B,
    #block{subject = Subj, seq = Seq, msg_id = MsgId, prev_hash = P,
           node_id = N, task_hash = T, payload_hash = H, energy = E,
           signature = S}.

verify_transition(#block{subject = Subj, seq = Seq, prev_hash = Prev,
                         node_id = NodeId, signature = Sig} = Block) ->
    {TailSeq, TailSeal} = worm_db:tail(Subj),
    if Seq =/= TailSeq + 1 -> {error, sequence_gate};
       Prev =/= TailSeal -> {error, fork_detected};
       true ->
            case worm_db:node_key(NodeId) of
                undefined -> {error, unknown_node};
                PubKey ->
                    Seal = compute_seal(Block),
                    case crypto:verify(eddsa, none, Seal, Sig, [PubKey, ed25519]) of
                        true -> ok;
                        false -> {error, bad_signature}
                    end
            end
    end.
