-module(worm_registry).
-behaviour(gen_server).

%% Where C nodes announce themselves. A C node has no rex: the
%% Erlang side can only address it by pid, and the pid exists
%% only on the C node — so on connect (either direction) the
%% C node introduces itself: {cnode_up, Name, Pid} lands here,
%% and callers look the pid up by name. Dead pids are dropped
%% on their DOWN.

-export([start_link/0, pid/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {by_name = #{}, by_pid = #{}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

pid(Name) ->
    gen_server:call(?MODULE, {pid, Name}).

init([]) -> {ok, #state{}}.

handle_call({pid, Name}, _From, State) ->
    {reply, maps:get(Name, State#state.by_name, undefined), State};
handle_call(_Other, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Other, State) -> {noreply, State}.

handle_info({cnode_up, Name, Pid}, State) when is_pid(Pid) ->
    erlang:monitor(process, Pid),
    {noreply, State#state{
        by_name = maps:put(Name, Pid, State#state.by_name),
        by_pid = maps:put(Pid, Name, State#state.by_pid)}};
handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    case maps:get(Pid, State#state.by_pid, undefined) of
        undefined -> {noreply, State};
        Name -> {noreply, State#state{
            by_name = maps:remove(Name, State#state.by_name),
            by_pid = maps:remove(Pid, State#state.by_pid)}}
    end;
handle_info(_Other, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_Old, State, _Extra) -> {ok, State}.
