-module(worm_nats_conn).
-behaviour(gen_server).

%% The core NATS TCP connection manager. One socket, owned here;
%% every other bus process sends through this module. When the
%% socket is down (this workspace has no NATS server; a network
%% partition on the fleet looks the same from here), protocol
%% frames are routed to the locally registered sink instead of
%% being dropped — on the fleet the sink is never used because
%% the socket is live. The reconnect clauses below are the
%% owner's, verbatim.

-export([start_link/0, send/1, ack/1, publish_append/2, register_sink/1, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {host = "127.0.0.1",
                port = 4222,
                socket = undefined,
                status = disconnected,
                backoff = 1000,
                sink = undefined}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Send a protocol frame (subscription, publish, ack).
send(Frame) ->
    gen_server:cast(?MODULE, {send, Frame}).

%% Publish a ledger append with the optimistic-concurrency
%% gate, in the owner's exact frame shape:
%%
%%   HPUB sovereign.ledger.append <header-bytes> <total-bytes>
%%   NATS/1.0
%%   Nats-Expected-Last-Sequence: <N>
%%
%%   <binary_worm_block_payload>
%%
%% JetStream accepts the append only if the stream's current
%% last sequence is exactly N — a beaten append is rejected at
%% the network layer and the chain cannot fork.
publish_append(ExpectedSeq, Payload) ->
    Header = iolist_to_binary(
        io_lib:format("NATS/1.0\r\nNats-Expected-Last-Sequence: ~B\r\n\r\n",
                      [ExpectedSeq])),
    Total = byte_size(Header) + byte_size(Payload),
    Frame = iolist_to_binary(
        io_lib:format("HPUB sovereign.ledger.append ~B\r\n", [Total])),
    send(<<Frame/binary, Header/binary, Payload/binary, "\r\n">>).

%% JetStream ACK for a delivered message id.
ack(MsgId) ->
    send(<<"+ACK ", MsgId/binary, "\r\n">>).

%% Register the pid that receives frames while disconnected
%% (the local oracle/tests on this machine).
register_sink(Pid) ->
    gen_server:call(?MODULE, {register_sink, Pid}).

status() ->
    gen_server:call(?MODULE, status).

init([]) ->
    Host = application:get_env(muse_swarm, nats_host, "127.0.0.1"),
    Port = application:get_env(muse_swarm, nats_port, 4222),
    erlang:send_after(10, self(), attempt_reconnect),
    {ok, #state{host = Host, port = Port}}.

handle_call({register_sink, Pid}, _From, State) ->
    {reply, ok, State#state{sink = Pid}};
handle_call(status, _From, State) ->
    {reply, State#state.status, State};
handle_call(_Other, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({send, Frame}, #state{socket = Sock, status = connected} = State)
        when Sock =/= undefined ->
    _ = gen_tcp:send(Sock, Frame),
    {noreply, State};
handle_cast({send, Frame}, #state{sink = Sink} = State) when is_pid(Sink) ->
    Sink ! {nats_frame, Frame},
    {noreply, State};
handle_cast({send, _Frame}, State) ->
    %% disconnected and no sink: the frame is dropped, exactly
    %% as a dead bus would drop it; JetStream redelivery is the
    %% sender's recovery, per the worker's design.
    {noreply, State};
handle_cast(_Other, State) ->
    {noreply, State}.

handle_info({tcp_closed, _Socket}, State) ->
    %% Network partition detected.
    error_logger:warning_msg("NATS core connection lost. Entering exponential backoff."),
    erlang:send_after(1000, self(), attempt_reconnect),
    {noreply, State#state{status = disconnected}};

handle_info(attempt_reconnect, State) ->
    case gen_tcp:connect(State#state.host, State#state.port, [binary, {active, true}]) of
        {ok, Socket} ->
            %% Send NATS CONNECT protocol string
            ok = gen_tcp:send(Socket, build_connect_proto()),
            %% When this succeeds, the root supervisor allows the dynamic supervisor 
            %% to start spawning consumers again.
            {noreply, State#state{socket = Socket, status = connected}};
        {error, _Reason} ->
            %% Double the backoff delay (capped at 30s) and try again
            erlang:send_after(next_backoff(State), self(), attempt_reconnect),
            {noreply, State}
    end;
handle_info({tcp, _Socket, _Data}, State) ->
    %% Inbound bus traffic is dispatched by the ledger workers'
    %% own subscriptions on the fleet. Here frames are consumed
    %% so the socket never backs up.
    {noreply, State};
handle_info({tcp_error, _Socket, _Reason}, State) ->
    {noreply, State#state{socket = undefined, status = disconnected}};
handle_info(_Other, State) ->
    {noreply, State}.

terminate(_Reason, #state{socket = Sock}) ->
    case Sock of
        undefined -> ok;
        _ -> gen_tcp:close(Sock)
    end,
    ok.

code_change(_Old, State, _Extra) -> {ok, State}.

%% The NATS CONNECT protocol line.
build_connect_proto() ->
    <<"CONNECT {\"name\":\"worm-ledger\",\"lang\":\"erlang\",\"version\":\"1.0\",\"protocol\":1}\r\n">>.

%% Double the backoff delay (capped at 30s).
next_backoff(#state{backoff = B}) ->
    erlang:min(B * 2, 30000).
