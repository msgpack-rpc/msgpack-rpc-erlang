-module(msgpack_rpc_ssl_test).

-include_lib("eunit/include/eunit.hrl").

-export([hello/1, add/2]).

hello(_Argv)->
    <<"hello">>.

add(A, B)-> A+B.
    

start_stop_test()->
%    ok = application:start(crypto),
    ok = application:start(public_key),
    ok = application:start(ssl),

    ok = application:start(ranch),
    {ok, _Pid} = ranch:start_listener(testlistener2, 3,
				   ranch_ssl, [{port, 9200},
					       {certfile, "../priv/server_cert.pem"},
					       {keyfile, "../priv/server_key.pem"}
					      ],
				   msgpack_rpc_protocol, [{module, msgpack_rpc_ssl_test}]),
    
    %{ok, Socket} = ssl:connect("localhost", 9200,
    % 			       [{keepalive, true}, binary, {active, false}, {packet, raw},
    % 				{certfile, "../priv/server_cert.pem"},
    % 				{keyfile, "../priv/server_key.pem"}]),
    %ok = ssl:send(Socket, msgpack:pack(<<"SSL Ranch is working!">>),
    %% {ok, <<"SSL Ranch is working!">>} = ssl:recv(Socket, 21, 1000),
    %ok = ssl:close(Socket),

    {ok, Pid} = msgpack_rpc_client:connect(ssl, "localhost", 9200,
					   [{certfile, "../priv/server_cert.pem"},
					    {keyfile, "../priv/server_key.pem"}]),
    %Reply = msgpack_rpc_client:call(Pid, hello, [<<"hello">>]),
    %?assertEqual({ok, <<"hello">>}, Reply),

    %R = msgpack_rpc_client:call(Pid, add, [12, 23]),
    %?assertEqual({ok, 35}, R),

    %% ok = msgpack_rpc_client:notify(Pid, hello, [23]),

    %% {ok, CallID0} = msgpack_rpc_client:call_async(Pid, add, [-23, 23]),
    %% ?assertEqual({ok, 0}, msgpack_rpc_client:join(Pid, CallID0)),

    %% {ok, CallID1} = msgpack_rpc_client:call_async(Pid, add, [-23, 46]),
    %% ?assertEqual({ok, 23}, msgpack_rpc_client:join(Pid, CallID1)),

    %% % wrong arity, wrong function
    %% {error, undef} = msgpack_rpc_client:call(Pid, add, [-23]),
    %% {error, undef} = msgpack_rpc_client:call(Pid, imaginary, []),

    ok = msgpack_rpc_client:close(Pid),

    ok = ranch:stop_listener(testlistener2),
    ok = application:stop(ranch),

    ok = application:stop(ssl),
    ok = application:stop(public_key).
%    ok = application:stop(crypto).

