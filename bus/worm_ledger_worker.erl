-module(worm_ledger_worker).
-behaviour(gen_server).
-include("worm.hrl").

%% One JetStream consumer: replays from the last verified
%% sequence, verifies every proposed block across the FFI
%% boundary, commits what verifies, ACKs what commits — and
%% crashes on an invalid transition so the supervisor restarts
%% it purged, per the owner's design (the init and handle_info
%% clauses are his, verbatim; the glue around them is the
%% completion).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {subject, current_seq}).

start_link(StreamConfig) ->
    gen_server:start_link(?MODULE, [StreamConfig], []).

init([StreamConfig]) ->
    %% 1. Query the local WORM database for the last known good state
    LastVerifiedSeq = db_get_highest_sequence(StreamConfig#config.subject),
    
    %% 2. Construct the JetStream subscription request
    %% We explicitly request NATS to start replaying from LastVerifiedSeq + 1
    SubMsg = build_sub_proto(StreamConfig, LastVerifiedSeq + 1),
    
    %% 3. Send subscription over the primary connection manager
    worm_nats_conn:send(SubMsg),
    
    {ok, #state{
        subject = StreamConfig#config.subject,
        current_seq = LastVerifiedSeq
    }}.

handle_info({nats_msg, Payload}, State) ->
    Block = decode_payload(Payload),
    
    %% 4. Cross the FFI boundary to Lean 4 to formally verify the transition
    case lean_ffi:verify_transition(Block) of
        ok ->
            %% Proof successful. Commit to local Postgres disk.
            db_commit_block(Block),
            
            %% Send JetStream ACK back to the NATS bus so the Jetson Orin knows 
            %% the state is locked and it can free its VRAM.
            worm_nats_conn:ack(Block#block.msg_id),
            
            {noreply, State#state{current_seq = Block#block.seq}};
        {error, _Reason} ->
            %% The block is invalid, hallucinatory, or maliciously constructed.
            %% DO NOT ACK. Let the NATS JetStream redelivery timeout handle it.
            %% Crash this worker to purge state, the supervisor will cleanly restart it.
            exit(invalid_state_transition)
    end;
handle_info(_Other, State) ->
    {noreply, State}.

handle_call(_Other, _From, State) -> {reply, {error, unknown_call}, State}.
handle_cast(_Other, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Old, State, _Extra) -> {ok, State}.

%% --- glue (completion) ---

db_get_highest_sequence(Subject) ->
    worm_db:highest_sequence(Subject).

db_commit_block(Block) ->
    Payload = lean_ffi:encode_payload(Block),
    {ok, _Seal} = worm_db:commit(Block#block.subject, Payload),
    ok.

decode_payload(Payload) ->
    lean_ffi:decode_payload(Payload).

%% The subscription is a JetStream consumer-create request
%% carrying the owner's consumer config (bus/
%% SOVEREIGN_LEDGER.consumer.json): deliver by start sequence,
%% explicit acks, 30s ack wait, instant replay. The start
%% sequence is LastVerifiedSeq + 1, exactly the opt_start_seq
%% of the config — a restarted worker resumes after the last
%% block it verified, never before it.
build_sub_proto(StreamConfig, StartSeq) ->
    Subject = StreamConfig#config.subject,
    Stream = StreamConfig#config.stream,
    Json = io_lib:format(
        "{\"stream_name\":\"~s\",\"config\":{\"deliver_policy\":\"by_start_sequence\",\"opt_start_seq\":~B,\"ack_policy\":\"explicit\",\"ack_wait\":30000000000,\"max_deliver\":-1,\"filter_subject\":\"~s\",\"replay_policy\":\"instant\",\"max_waiting\":512,\"max_ack_pending\":1024}}",
        [Stream, StartSeq, Subject]),
    iolist_to_binary(["PUB $JS.API.CONSUMER.CREATE.", Stream,
                      ".worm-ledger-oracle ", Json, "\r\n"]).
