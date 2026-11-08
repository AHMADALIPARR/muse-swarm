-module(worm_tests).
-include("worm.hrl").

%% Self-contained bus suite (no eunit on this box): boot the
%% whole tree against a throwaway WORM_DATA, drive a consumer
%% through the dynamic supervisor, commit a valid block, watch
%% a fork and a sequence-gap crash the worker (the owner's
%% purge-on-invalid design) while the chain stays put, then
%% exercise the CLAIM lock and the subject partitioning.

-export([main/0]).

-define(SUBJ, <<"sovereign.ledger.append">>).

main() ->
    Dir = "/tmp/worm-bus-test-" ++ integer_to_list(erlang:system_time(microsecond)),
    os:putenv("WORM_DATA", Dir),
    try
        run(),
        io:format("BUS TESTS OK~n"),
        halt(0)
    catch
        Class:Reason:Stack ->
            io:format("BUS TEST FAIL ~p:~p ~p~n", [Class, Reason, hd(Stack)]),
            halt(1)
    end.

expect(Label, true) -> io:format("ok - ~s~n", [Label]);
expect(Label, false) -> throw({expect_failed, Label}).
expect(Label, Got, Want) ->
    case Got =:= Want of
        true -> io:format("ok - ~s~n", [Label]);
        false -> throw({expect_failed, Label, Got, Want})
    end.

wait_until(Fun, Label) -> wait_until(Fun, Label, 60).
wait_until(_Fun, Label, 0) -> throw({timeout, Label});
wait_until(Fun, Label, N) ->
    case Fun() of
        true -> ok;
        _ -> timer:sleep(100), wait_until(Fun, Label, N - 1)
    end.

worker_pid() ->
    case supervisor:which_children(worm_jetstream_sup) of
        [{undefined, Pid, worker, _}] when is_pid(Pid) -> Pid;
        _ -> undefined
    end.

run() ->
    ok = worm_boot:ensure_started(),
    expect("supervision tree is up", is_pid(whereis(worm_root_sup))),
    expect("connection manager is up", is_pid(whereis(worm_nats_conn))),
    ok = worm_nats_conn:register_sink(self()),

    %% a fleet node registers its key at boot
    {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
    NodeId = <<"orin-nx-01", 0:48>>,
    ok = worm_db:register_node(NodeId, Pub),

    %% consumer attaches through the dynamic supervisor
    {ok, _W0} = worm_jetstream_sup:start_consumer(
        #config{subject = ?SUBJ, stream = <<"WORM">>}),
    receive
        {nats_frame, SubFrame} ->
            expect("subscription requests replay from seq 1",
                   binary:match(SubFrame, list_to_binary("opt_start_seq" ++ [34] ++ ":1")) =/= nomatch)
    after 3000 -> throw(no_sub_frame)
    end,

    %% valid block seq 1 commits and ACKs
    B1 = build_block(1, <<0:256>>, NodeId, Priv, <<"payload-one">>),
    Seal1 = lean_ffi:compute_seal(B1),
    W1 = worker_pid(),
    W1 ! {nats_msg, lean_ffi:encode_payload(B1)},
    wait_until(fun() -> worm_db:tail(?SUBJ) =:= {1, Seal1} end, "block 1 committed"),
    receive
        {nats_frame, <<"+ACK ", _/binary>>} -> io:format("ok - commit ACKed on the bus~n")
    after 3000 -> throw(no_ack)
    end,

    %% a fork at seq 1: purge-on-invalid (worker exits, chain unmoved)
    Fork = build_block(1, <<0:256>>, NodeId, Priv, <<"payload-fork">>),
    expect_worker_crash(W1, Fork, "fork crashes the worker"),
    expect("chain unmoved after fork", worm_db:tail(?SUBJ), {1, Seal1}),

    %% a gap (seq 3 next) hits the sequence gate the same way
    Gap = build_block(3, Seal1, NodeId, Priv, <<"payload-gap">>),
    expect_worker_crash(worker_pid(), Gap, "sequence gap crashes the worker"),
    expect("chain unmoved after gap", worm_db:tail(?SUBJ), {1, Seal1}),

    %% the honest seq 2 commits on the restarted worker
    B2 = build_block(2, Seal1, NodeId, Priv, <<"payload-two">>),
    Seal2 = lean_ffi:compute_seal(B2),
    worker_pid() ! {nats_msg, lean_ffi:encode_payload(B2)},
    wait_until(fun() -> worm_db:tail(?SUBJ) =:= {2, Seal2} end, "block 2 committed"),
    expect("two sealed entries on disk", length(worm_db:chain(?SUBJ)), 2),

    frame_tests(),
    lock_tests(),
    partition_tests(),
    ok.

expect_worker_crash(Pid, Block, Label) ->
    Ref = erlang:monitor(process, Pid),
    Pid ! {nats_msg, lean_ffi:encode_payload(Block)},
    receive
        {'DOWN', Ref, process, Pid, invalid_state_transition} ->
            io:format("ok - ~s~n", [Label])
    after 4000 -> throw({no_crash, Label})
    end,
    wait_until(fun() ->
        case worker_pid() of
            undefined -> false;
            New -> New =/= Pid
        end
    end, Label ++ " (worker restarted)").

build_block(Seq, Prev, NodeId, Priv, Tag) ->
    B0 = #block{subject = ?SUBJ, seq = Seq, msg_id = <<"m", (integer_to_binary(Seq))/binary, Tag/binary>>,
                prev_hash = Prev, node_id = NodeId,
                task_hash = crypto:hash(sha256, <<"task:", Tag/binary>>),
                payload_hash = crypto:hash(sha256, Tag),
                energy = 1.5, signature = <<0:512>>},
    Seal = lean_ffi:compute_seal(B0),
    Sig = crypto:sign(eddsa, none, Seal, [Priv, ed25519]),
    B0#block{signature = Sig}.

frame_tests() ->
    Payload = <<1, 2, 3, 4>>,
    ok = worm_nats_conn:publish_append(42, Payload),
    Frame = recv_frame(<<"HPUB">>),
    if Frame =/= undefined ->
            Header = <<"NATS/1.0\r\nNats-Expected-Last-Sequence: 42\r\n\r\n">>,
            Total = byte_size(Header) + byte_size(Payload),
            Want = iolist_to_binary(
                io_lib:format("HPUB sovereign.ledger.append ~B\r\n", [Total])),
            expect("HPUB append frame carries the sequence gate",
                   binary:match(Frame, Want) =/= nomatch andalso
                   binary:match(Frame, Header) =/= nomatch andalso
                   binary:match(Frame, Payload) =/= nomatch);
       true -> throw(no_hpub_frame)
    end,
    ok.

%% the mailbox may hold earlier frames (commit ACKs): scan for
%% the one carrying the marker
recv_frame(Marker) -> recv_frame(Marker, 30).
recv_frame(_Marker, 0) -> undefined;
recv_frame(Marker, N) ->
    receive
        {nats_frame, F} ->
            case binary:match(F, Marker) of
                nomatch -> recv_frame(Marker, N - 1);
                _ -> F
            end
    after 200 -> undefined
    end.

lock_tests() ->
    Task = crypto:hash(sha256, "claim-task"),
    A = <<"node-a", 0:80>>, B = <<"node-b", 0:80>>,
    expect("first claim takes the lock", lock_server:claim(A, Task, 5.0), {ok, locked}),
    expect("higher energy is rejected", lock_server:claim(B, Task, 7.0),
           {error, {locked_by, A, 5.0}}),
    expect("same holder re-claims", element(1, lock_server:claim(A, Task, 9.0)), ok),
    expect("lower energy displaces (ground state wins)",
           lock_server:claim(B, Task, 3.0), {ok, locked}),
    expect("holder is the low-energy node", lock_server:holder(Task), {B, 3.0}),
    expect("release frees the task", lock_server:release(Task), ok),
    expect("task claimable after release", lock_server:claim(A, Task, 9.0), {ok, locked}),
    ok.

partition_tests() ->
    expect("synthesis subject", lock_server:subject_for(synthesis),
           <<"mkr.ticket.synthesis">>),
    expect("critique subject", lock_server:subject_for(critique),
           <<"mkr.ticket.critique">>),
    expect("generator sees only synthesis", lock_server:subjects_for_role(generator),
           [<<"mkr.ticket.synthesis">>]),
    expect("verifier sees only critique", lock_server:subjects_for_role(verifier),
           [<<"mkr.ticket.critique">>]),
    ok.
