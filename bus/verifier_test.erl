-module(verifier_test).

%% Drives the Lean verifier C node over distribution: an
%% admissible block (prev == tail, energy at the ceiling) must
%% come back {proof_result, true}; a forked prev and an energy
%% above the ceiling must come back false.

-export([main/0]).

main() ->
    Node = 'lean_verifier@127.0.0.1',
    {ok, _} = worm_registry:start_link(),
    %% The connect forces the C node's accept; the node then
    %% announces its pid to the registry, and that pid is the
    %% address for requests (a C node has no rex to resolve
    %% names). net_adm:ping is not used: C nodes do not answer
    %% Erlang-level pings even on a healthy connection.
    true = net_kernel:connect_node(Node),
    Pid = wait_pid(50),
    Tail = <<7:256>>,
    Ceiling = 1065353216,  %% 1.0f bit pattern
    Good = block(Tail, 1.0),
    Fork = block(<<9:256>>, 1.0),
    Hot = block(Tail, 2.0),
    Pid ! {self(), Tail, Ceiling, Good},
    Pid ! {self(), Tail, Ceiling, Fork},
    Pid ! {self(), Tail, Ceiling, Hot},
    R = [recv(), recv(), recv()],
    case R of
        [true, false, false] ->
            io:format("VERIFIER TESTS OK~n"), halt(0);
        Other ->
            io:format("VERIFIER TESTS FAIL ~p~n", [Other]), halt(1)
    end.

wait_pid(0) -> io:format("no verifier pid announced~n"), halt(1);
wait_pid(N) ->
    case worm_registry:pid(lean_verifier) of
        undefined -> timer:sleep(100), wait_pid(N - 1);
        Pid -> Pid
    end.

recv() ->
    receive {proof_result, B} -> B
    after 5000 -> timeout
    end.

block(Prev, Energy) ->
    <<Prev/binary, 1:128, 2:256, 3:256, Energy:32/float-little, 0:512>>.
