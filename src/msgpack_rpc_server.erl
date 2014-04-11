%%% @author UENISHI Kota <kota@basho.com>
%%% @copyright (C) 2012, UENISHI Kota
%%% @doc
%%%
%%% @end
%%% Created : 29 Sep 2012 by UENISHI Kota <kota@basho.com>

-module(msgpack_rpc_server).

-export([start/4, start/5, stop/1]).

-spec start(atom(), tcp|ssl, atom(), proplists:proplists())
           -> {ok, pid()} | {error, term()}.
start(Name, Transport, Module, Opts)->
    start(Name, 4, Transport, Module, Opts).

start(Name, NumProc, ssl, Module, Opts)->
    ranch:start_listener(Name, NumProc, ranch_ssl, Opts,
                         msgpack_rpc_protocol, [{module, Module}]);
start(Name, NumProc, tcp, Module, Opts)->
    ranch:start_listener(Name, NumProc, ranch_tcp, Opts,
                         msgpack_rpc_protocol, [{module, Module}]).

-spec stop(atom()) -> ok.
stop(Name) ->
    ranch:stop_listener(Name).
