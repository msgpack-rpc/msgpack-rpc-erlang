-module(msgpack_rpc_test).

-include_lib("eunit/include/eunit.hrl").

-export([hello/1, add/2]).

hello(Argv)->
    [<<"ok">>, Argv].

add(A, B)-> A+B.
    

start_stop_test()->
    ok = application:start(cowboy),
    {ok, _} = cowboy:start_listener(testlistener, 3,
				    cowboy_tcp_transport, [{port, 9199}],
				    msgpack_rpc_protocol, [{module, msgpack_rpc_test}]),

    ok = mprc:start(),
    {ok,S} = mprc:connect(localhost,9199,[]),

    {Ret, MPRC0} = mprc:call(S, hello, [<<"hello">>]), 
    % TODO: fix
    ?assertEqual({ok, [<<"ok">>,<<"hello">>]}, Ret),

    mprc:notify(MPRC0, hello, [hoge]),

    {Ret0, MPRC1} = mprc:call(MPRC0, add, [230,4]),
    ?assertEqual({ok, 234}, Ret0),

    {Ret1, _} = mprc:call(MPRC1, no_method, []),

    ?debugVal(Ret1),
    ?assertEqual(ok, mprc:close(S)),
    ok = mprc:stop(),


    ok = cowboy:stop_listener(testlistener),
    ?debugHere,
    ok = application:stop(cowboy).
