-module(worm_db).
-include("worm.hrl").
-behaviour(gen_server).

%% The ledger store: per-subject append-only block log on disk
%% plus the in-memory tail (sequence + seal) the verifier gates
%% against, and the node key registry (node_id -> Ed25519 public
%% key) the signature check reads.
%%
%% Log file per subject under the data dir ($WORM_DATA or
%% ./worm-data): <<Seq:64, Seal:32/binary, Block:180/binary>>
%% records appended in order. Nothing is ever rewritten.

-export([start_link/0, register_node/2, node_key/1,
         highest_sequence/1, tail/1, commit/2, chain/1, data_dir/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {tails = #{}, keys = #{}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_node(NodeId, PubKey) ->
    gen_server:call(?MODULE, {register_node, NodeId, PubKey}).

node_key(NodeId) ->
    gen_server:call(?MODULE, {node_key, NodeId}).

highest_sequence(Subject) ->
    {Seq, _} = tail(Subject),
    Seq.

tail(Subject) ->
    gen_server:call(?MODULE, {tail, Subject}).

%% Append a verified block. The caller has already verified it
%% (lean_ffi:verify_transition/1); commit is the write itself.
commit(Subject, Payload) ->
    gen_server:call(?MODULE, {commit, Subject, Payload}).

%% The full stored chain for a subject: [{Seq, Seal, BlockBin}].
chain(Subject) ->
    Path = log_path(Subject),
    case file:read_file(Path) of
        {ok, Bin} -> parse_log(Bin, []);
        {error, enoent} -> []
    end.

data_dir() ->
    case os:getenv("WORM_DATA") of
        false -> "worm-data";
        Dir -> Dir
    end.

log_path(Subject) ->
    Safe = binary:replace(Subject, <<".">>, <<"_">>, [global]),
    filename:join(data_dir(), binary_to_list(Safe) ++ ".wormlog").

parse_log(<<>>, Acc) -> lists:reverse(Acc);
parse_log(<<Seq:64, Seal:32/binary, Block:180/binary, Rest/binary>>, Acc) ->
    parse_log(Rest, [{Seq, Seal, Block} | Acc]).

init([]) ->
    ok = filelib:ensure_dir(filename:join(data_dir(), "keep")),
    %% rebuild tails from whatever is already sealed on disk
    {ok, #state{}}.

handle_call({register_node, NodeId, PubKey}, _From, State) ->
    {reply, ok, State#state{keys = maps:put(NodeId, PubKey, State#state.keys)}};
handle_call({node_key, NodeId}, _From, State) ->
    {reply, maps:get(NodeId, State#state.keys, undefined), State};
handle_call({tail, Subject}, _From, State) ->
    Tail = case maps:get(Subject, State#state.tails, undefined) of
        undefined -> disk_tail(Subject);
        T -> T
    end,
    {reply, Tail, State#state{tails = maps:put(Subject, Tail, State#state.tails)}};
handle_call({commit, Subject, Payload}, _From, State) ->
    Block = lean_ffi:decode_payload(Payload),
    Seal = lean_ffi:compute_seal(Block),
    Seq = Block#block.seq,
    Entry = <<Seq:64, Seal:32/binary, (lean_ffi:block_binary(Block)):180/binary>>,
    ok = file:write_file(log_path(Subject), Entry, [append]),
    NewTails = maps:put(Subject, {Seq, Seal}, State#state.tails),
    {reply, {ok, Seal}, State#state{tails = NewTails}};
handle_call(_Other, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Other, State) -> {noreply, State}.
handle_info(_Other, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Old, State, _Extra) -> {ok, State}.

disk_tail(Subject) ->
    case chain(Subject) of
        [] -> {0, <<0:256>>};
        Entries ->
            {Seq, Seal, _} = lists:last(Entries),
            {Seq, Seal}
    end.
