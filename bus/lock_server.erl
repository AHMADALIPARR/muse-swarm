-module(lock_server).
-behaviour(gen_server).

%% The CLAIM lock (Deterministic Silence, part 4): an atomic
%% compare-and-swap on task claims. The first CLAIM for a task
%% hash takes the lock. A competing CLAIM wins only if its
%% Frustration Hamiltonian energy is strictly lower — the
%% cluster settles into its lowest energy state and the loser
%% is rejected with the holder's identity and energy, so it can
%% stay silent instead of retrying blindly.
%%
%% Also owns the NATS subject partitioning: task types map to
%% mkr.ticket.<type>, and a node subscribes only to the
%% subjects matching its pinned role.

-export([start_link/0, claim/3, release/1, holder/1, claims/0,
         subject_for/1, subjects_for_role/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {claims = #{}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% claim(NodeId, TaskHash, Energy) ->
%%   {ok, locked} | {error, {locked_by, Holder, HolderEnergy}}
claim(NodeId, TaskHash, Energy) ->
    gen_server:call(?MODULE, {claim, NodeId, TaskHash, Energy}).

release(TaskHash) ->
    gen_server:call(?MODULE, {release, TaskHash}).

holder(TaskHash) ->
    gen_server:call(?MODULE, {holder, TaskHash}).

claims() ->
    gen_server:call(?MODULE, claims).

subject_for(synthesis) -> <<"mkr.ticket.synthesis">>;
subject_for(critique) -> <<"mkr.ticket.critique">>;
subject_for(Other) when is_atom(Other) ->
    iolist_to_binary(["mkr.ticket.", atom_to_binary(Other, utf8)]);
subject_for(Other) when is_binary(Other) ->
    iolist_to_binary(["mkr.ticket.", Other]).

%% A node's subscription set is its pinned role, nothing else:
%% a generation node never even sees critique traffic.
subjects_for_role(generator) -> [subject_for(synthesis)];
subjects_for_role(verifier) -> [subject_for(critique)];
subjects_for_role(orchestrator) -> [subject_for(synthesis), subject_for(critique)].

init([]) -> {ok, #state{}}.

handle_call({claim, NodeId, TaskHash, Energy}, _From, State) ->
    case maps:get(TaskHash, State#state.claims, undefined) of
        undefined ->
            Claims = maps:put(TaskHash, {NodeId, Energy}, State#state.claims),
            {reply, {ok, locked}, State#state{claims = Claims}};
        {NodeId, _OldEnergy} ->
            {reply, {ok, already_yours}, State};
        {_Holder, HolderEnergy} when Energy < HolderEnergy ->
            %% lower energy displaces: the cluster's ground state wins
            Claims = maps:put(TaskHash, {NodeId, Energy}, State#state.claims),
            {reply, {ok, locked}, State#state{claims = Claims}};
        {Holder, HolderEnergy} ->
            {reply, {error, {locked_by, Holder, HolderEnergy}}, State}
    end;
handle_call(claims, _From, State) ->
    {reply, State#state.claims, State};
handle_call({release, TaskHash}, _From, State) ->
    {reply, ok, State#state{claims = maps:remove(TaskHash, State#state.claims)}};
handle_call({holder, TaskHash}, _From, State) ->
    {reply, maps:get(TaskHash, State#state.claims, undefined), State};
handle_call(_Other, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Other, State) -> {noreply, State}.
handle_info(_Other, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Old, State, _Extra) -> {ok, State}.
