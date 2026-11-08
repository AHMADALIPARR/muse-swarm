-module(worm_root_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => rest_for_one,  %% If a child dies, kill all children started AFTER it, then restart
        intensity => 10,           %% Max 10 restarts
        period => 5                %% Within 5 seconds
    },

    ChildSpecs = [
        %% 1. The Core NATS TCP Connection Manager
        #{id => nats_conn_mgr,
          start => {worm_nats_conn, start_link, []},
          restart => permanent,
          type => worker},

        %% 2. The Dynamic Supervisor for JetStream Consumers
        #{id => jetstream_dyn_sup,
          start => {worm_jetstream_sup, start_link, []},
          restart => permanent,
          type => supervisor}
    ],

    {ok, {SupFlags, ChildSpecs}}.
