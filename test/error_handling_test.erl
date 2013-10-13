-module(error_handling_test).

-include_lib("eunit/include/eunit.hrl").

-export([block/1]).

block(Pid0)->
    Pid = erlang:list_to_pid(Pid0),
    receive {'DOWN', Ref, process, Parent,noproc} when is_reference(Ref)
                                                       andalso is_pid(Parent) ->
            Pid ! 'test ok! boom!!!',
            <<"boom!!!">>
    after 1024 ->
            <<"error">>
    end.


start_stop_test()->
    ok = application:start(ranch),
    {ok, _} = msgpack_rpc_server:start(testlistener, 3, tcp, error_handling_test, [{port, 9199}]),
    
    {ok, Pid} = msgpack_rpc_client:connect(tcp, "localhost", 9199, []),
    Self = self(),
    
    {ok, CallID} = msgpack_rpc_client:call_async(Pid, block, [erlang:pid_to_list(Self)]),
    
    %% simulate that connection has been accidentally lost
    ok = msgpack_rpc_client:close(Pid),

    receive Msg ->
            ?assertEqual('test ok! boom!!!', Msg)
    after 1024 ->
            ?assert(false)
    end,
    ?assertException(exit, _, msgpack_rpc_client:join(Pid, CallID)),

    %% ok = msgpack_rpc_client:notify(Pid, hello, [23]),

    %% {ok, CallID0} = msgpack_rpc_client:call_async(Pid, add, [-23, 23]),
    %% ?assertEqual({ok, 0}, msgpack_rpc_client:join(Pid, CallID0)),

    %% {ok, CallID1} = msgpack_rpc_client:call_async(Pid, add, [-23, 46]),
    %% ?assertEqual({ok, 23}, msgpack_rpc_client:join(Pid, CallID1)),

    %% % wrong arity, wrong function
    %% {error, undef} = msgpack_rpc_client:call(Pid, add, [-23]),
    %% {error, undef} = msgpack_rpc_client:call(Pid, imaginary, []),

    %% ok = msgpack_rpc_client:close(Pid),

    ok = msgpack_rpc_server:stop(testlistener),
    ok = application:stop(ranch).
