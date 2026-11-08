-module(worm_boot).

%% Boots the bus without an OTP application: the store, the
%% lock, and the owner's supervision tree. Idempotent — safe to
%% call from the shell, the tests, or a release start script.

-export([ensure_started/0]).

ensure_started() ->
    start(worm_registry),
    start(worm_db),
    start(lock_server),
    start(worm_root_sup),
    ok.

start(Mod) ->
    case whereis(Mod) of
        undefined ->
            case Mod:start_link() of
                {ok, _Pid} -> ok;
                {error, {already_started, _}} -> ok
            end;
        _Pid -> ok
    end.
