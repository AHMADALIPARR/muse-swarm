-module(worm_jetstream_sup).
-behaviour(supervisor).
-export([start_link/0, init/1, start_consumer/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_consumer(StreamConfig) ->
    %% API to dynamically attach a new listener to a specific NATS subject
    supervisor:start_child(?MODULE, [StreamConfig]).

init([]) ->
    %% simple_one_for_one means all children are of the exact same type, 
    %% but spawned dynamically with different arguments.
    SupFlags = #{strategy => simple_one_for_one, intensity => 20, period => 1},
    
    ChildSpec = #{
        id => worm_ledger_worker,
        start => {worm_ledger_worker, start_link, []},
        restart => transient, %% Only restart if the exit was abnormal (e.g., FFI crash)
        type => worker
    },
    
    {ok, {SupFlags, [ChildSpec]}}.
