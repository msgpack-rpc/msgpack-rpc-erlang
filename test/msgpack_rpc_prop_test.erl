-module(msgpack_rpc_prop_test).

-import(msgpack, [pack/1, unpack/1]).

-define(TESTPORT, 65123).

-include_lib("eunit/include/eunit.hrl").

% this module is also a test server
-export([add/2, id/1]).

%% msgpack_rpc_props_test_() ->
%%     {timeout,10000, ?_assertEqual([],proper:module(msgpack_rpc_props))}.

add(A, B)->  A+B.

id(X) -> X.

setup()->
%    ?debugVal(setup),
    ok = application:start(ranch),
    {ok, _} = ranch:start_listener(testlistener, 3,
				   ranch_tcp, [{port, ?TESTPORT}],
				   msgpack_rpc_protocol, [{module, ?MODULE}]),
    ok.

teardown(_)->
%    ?debugVal(teardown),
    ok = ranch:stop_listener(testlistener),
    ok = application:stop(ranch).

generate_id_data()->
    [true, false, nil,
     0, 1, 2, 123, 512, 1230, 678908, 16#FFFFFFFFFF,
     -1, -23, -512, -1230, -567898, -16#FFFFFFFFFF,
     -16#80000001,
     123.123, -234.4355, 1.0e-34, 1.0e64,
     [23, 234, 0.23],
     <<"hogehoge">>, <<"243546rf7g68h798j", 0, 23, 255>>,
     <<"hoasfdafdas][">>,
     [0,42, <<"sum">>, [1,2]], [1,42, nil, [3]],
     -234, -40000, -16#10000000, -16#100000000,
     42
    ].

msgpack_rpc_server_test_()->
    {timeout, 10000,
     {setup, fun setup/0, fun teardown/1,
      [
       {"RPC add",
	{setup,
	 fun()-> msgpack_rpc_client:connect(tcp, "localhost", ?TESTPORT, []) end,
	 fun({ok, Conn})-> ok = msgpack_rpc_client:close(Conn) end,
	 fun({ok, Conn})->
		 [ ?_assertEqual({ok, X}, msgpack_rpc_client:call(Conn, id, [X]))
		   || X <- generate_id_data() ]
		     ++
                 [
		  ?_assertEqual({ok, 23}, msgpack_rpc_client:call(Conn, add, [10, 13]))
		 ] end
	}},
       ?_assertEqual([],proper:module(msgpack_rpc_props))
      ]
     }}.
 
benchmark_test_()->
    {setup, fun setup/0, fun teardown/1,
     [
      {"benchmark in serial",
       fun()->
	       {ok, C} = msgpack_rpc_client:connect(tcp, "localhost", ?TESTPORT, []),
	       Data = generate_id_data(),
	       S = msgpack:pack(Data),
	       N = 1024,
	       ?debugTime("serial call",
			  [ {ok, _} = msgpack_rpc_client:call(C, id, [Data])
			    || _ <- lists:seq(0, N)]),
	       ?debugFmt(" for ~p RPCs of ~p B data.", [N, byte_size(S)]),
	       msgpack_rpc_client:close(C)
       end}
     ]
    }.

% 16 * 16 parallel
parallel_benchmark_test_()->
    {setup, fun setup/0, fun teardown/1,
     [{inparallel,
	[fun()->
		 {ok, C} = msgpack_rpc_client:connect(tcp, "localhost", ?TESTPORT, []),
		 Data = generate_id_data(),
		 N = 256,
		 BenchFun = fun()->
				    [{ok, _} = msgpack_rpc_client:call(C, id, [Data])
				     || _ <- lists:seq(0, N)]
			    end,
		 {Time, _} = timer:tc(BenchFun),
		 msgpack_rpc_client:close(C),
		 ?debugFmt("~p ms for ~p RPCs", [Time / 1000, N]),
		 ok
	 end
	 || _ <- lists:seq(0, 16) ]
      }]
    }.
