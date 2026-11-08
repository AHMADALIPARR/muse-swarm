%% worm.hrl — shared records and the WormBlock wire format.
%%
%% Wire format of a ledger message payload (all integers big
%% endian except the energy, which is a little-endian float32
%% to match the Rust WormBlock's to_le_bytes seal input):
%%
%%   <<SubjLen:16, Subject/binary, Seq:64, MsgIdLen:16,
%%     MsgId/binary, PrevHash:32/binary, NodeId:16/binary,
%%     TaskHash:32/binary, PayloadHash:32/binary,
%%     Energy:32/float-little, Signature:64/binary>>
%%
%% The seal preimage is the 116 bytes
%% PrevHash || NodeId || TaskHash || PayloadHash || EnergyLE —
%% byte-identical in Rust (WormBlock.compute_seal), in Erlang
%% (lean_ffi:compute_seal/1), and in the C node. The node's
%% Ed25519 signature covers the seal.

-record(config, {subject :: binary(),
                 stream  :: binary()}).

-record(block, {subject     :: binary(),
                seq         :: non_neg_integer(),
                msg_id      :: binary(),
                prev_hash   :: binary(),
                node_id     :: binary(),
                task_hash   :: binary(),
                payload_hash :: binary(),
                energy      :: float(),
                signature   :: binary()}).
