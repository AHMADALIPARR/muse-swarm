-module(worm_shell).
-include("worm.hrl").

%% The custom shell for the Worm ledger. A small REPL over the
%% bus: inspect the tail, verify the sealed chain from disk,
%% list claims, and compute a block seal — locally, and through
%% the C node when it is connected, so the two implementations
%% can be compared line by line.
%%
%%   erl -name worm@127.0.0.1 -setcookie <cookie> \
%%       -pa bus/ebin -s worm_shell start

-export([start/0]).

-define(DEFAULT_SUBJECT, <<"sovereign.ledger.append">>).

start() ->
    ok = worm_boot:ensure_started(),
    io:format("Worm ledger shell. Type 'help'.~n"),
    loop().

loop() ->
    case io:get_line("worm> ") of
        eof -> io:format("bye~n"), halt(0);
        Line ->
            case dispatch(string:trim(Line)) of
                quit -> io:format("bye~n"), halt(0);
                _ -> loop()
            end
    end.

dispatch("") -> ok;
dispatch("quit") -> quit;
dispatch("help") ->
    io:format("tail            current sequence + tail seal~n"
              "verify          recompute the sealed chain from disk~n"
              "locks           list task claims and energies~n"
              "seal <hex>      seal a 180-byte block (local + C node)~n"
              "quit            exit~n"),
    ok;
dispatch("tail") ->
    {Seq, Seal} = worm_db:tail(?DEFAULT_SUBJECT),
    io:format("seq ~B tail ~s~n", [Seq, hex(Seal)]),
    ok;
dispatch("verify") ->
    verify_chain(worm_db:chain(?DEFAULT_SUBJECT), 0, <<0:256>>),
    ok;
dispatch("locks") ->
    maps:foreach(fun (Task, {Node, Energy}) ->
        io:format("task ~s holder ~s energy ~.3f~n",
                  [hex(Task), hex(Node), Energy])
    end, lock_server:claims()),
    io:format("~B claim(s)~n", [maps:size(lock_server:claims())]),
    ok;
dispatch("seal " ++ Hex) ->
    case unhex(string:trim(Hex)) of
        {ok, Block} when byte_size(Block) =:= 180 ->
            Local = lean_ffi:compute_seal(Block),
            io:format("local: ~s~n", [hex(Local)]),
            case cnode_seal(Block) of
                {ok, Remote} -> io:format("cnode: ~s~n", [hex(Remote)]);
                unavailable -> io:format("cnode: unavailable~n")
            end;
        _ -> io:format("error: expected 360 hex chars (180 bytes)~n")
    end,
    ok;
dispatch(Other) ->
    io:format("unknown command: ~s (try help)~n", [Other]),
    ok.

verify_chain([], Seq, _Tail) ->
    io:format("chain VALID ~B block(s)~n", [Seq]);
verify_chain([{Seq, Seal, BlockBin} | Rest], PrevSeq, PrevSeal) ->
    Block = lean_ffi:decode_payload(wrap(Seq, BlockBin)),
    ExpectedSeal = lean_ffi:compute_seal(BlockBin),
    if Seq =/= PrevSeq + 1 ->
            io:format("chain BROKEN at seq ~B (gap)~n", [Seq]);
       Block#block.prev_hash =/= PrevSeal ->
            io:format("chain BROKEN at seq ~B (prev mismatch)~n", [Seq]);
       ExpectedSeal =/= Seal ->
            io:format("chain BROKEN at seq ~B (seal mismatch)~n", [Seq]);
       true ->
            verify_chain(Rest, Seq, Seal)
    end.

%% rebuild a payload around a stored block so decode can run
wrap(Seq, BlockBin) ->
    Subj = ?DEFAULT_SUBJECT,
    <<(byte_size(Subj)):16, Subj/binary, Seq:64, 2:16, "m0", BlockBin/binary>>.

cnode_seal(Block) ->
    %% The seal C node announces its pid to the registry when
    %% it connects; that pid is the only address it has.
    case worm_registry:pid(seal_server) of
        undefined -> unavailable;
        Pid ->
            Pid ! {call, self(), seal, Block},
            receive
                {seal_result, Seal} -> {ok, Seal}
            after 3000 -> unavailable
            end
    end.

hex(Bin) -> lists:flatten([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

unhex(Str) ->
    case length(Str) rem 2 of
        0 -> {ok, << <<(list_to_integer([A, B], 16))>> || <<A, B>> <= list_to_binary(Str) >>};
        _ -> error
    end.
