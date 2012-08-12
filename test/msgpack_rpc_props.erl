-module(msgpack_rpc_props).

-include_lib("proper/include/proper.hrl").

-import(msgpack_rpc_proper, [choose_type/0]).

prop_rpcs()->
    numtests(30,
	     ?FORALL(Term, msgpack_rpc_proper:choose_type(),
		     begin
			 {ok,Conn}=msgpack_rpc_client:connect(tcp, "localhost", 65123, []),
			 {ok,Term}=msgpack_rpc_client:call(Conn, id, [Term]),
			 ok = msgpack_rpc_client:close(Conn)
		     end)).
