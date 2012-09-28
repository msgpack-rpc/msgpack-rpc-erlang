%%%-------------------------------------------------------------------
%%% @author UENISHI Kota <kuenishi@gmail.com>
%%% @copyright (C) 2012, UENISHI Kota
%%% @doc
%%%
%%% @end
%%% Created : 24 Jul 2012 by UENISHI Kota <kuenishi@gmail.com>
%%%-------------------------------------------------------------------
-module(msgpack_rpc_client).

-include("msgpack_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([start_link/4, connect/4, close/1,
	 call/3, call_async/3, join/2, notify/3]).

-type type()   :: tcp. % | udp | sctp.
-type method() :: atom().
-type argv()   :: [msgpack:msgpack_term()].
-type callid() :: non_neg_integer().

-spec start_link(type(), inet:ip_address(), inet:port_number(), [proplists:property()]) -> {ok, pid()} | {error, any()}.
start_link(tcp, IP, Port, Opts)->
    msgpack_rpc_connection:start_link([{transport, ranch_tcp}, {ipaddr, IP}, {port, Port}] ++ Opts);
    % cowboy_tcp_transport:connect(IP, Port, Opts);
start_link(_Type, _IP, _Port, _Opts)->
    {error, no_transport}.

-spec connect(type(), inet:ip_address(), inet:port_number(), [proplists:property()]) -> {ok, pid()} | {error, any()}.
connect(Type, IP, Port, Opts)->
    start_link(Type, IP, Port, Opts).

-spec close(pid())-> ok.
close(Pid)->
    gen_server:call(Pid, close).

-spec call(pid(), method(), argv()) -> {ok, msgpack:msgpack_term()} | {error, any()}.
call(Pid, Method, Argv)->
    case call_async(Pid, Method, Argv) of
	{ok, CallID} -> join(Pid, CallID);
	Error -> Error
    end.

-spec call_async(pid(), method(), argv()) -> {ok, callid()} | {error, any()}.
call_async(Pid, Method, Argv)->
    BinMethod = atom_to_binary(Method, latin1),
    gen_server:call(Pid, {call_async, BinMethod, Argv}).

-spec join(pid(), callid()) -> {ok, msgpack:msgpack_term()} | {error, any()}.
join(Pid, CallID)->
    gen_server:call(Pid, {join, CallID}).

-spec notify(pid(), method(), argv()) -> ok. % never fails
notify(Pid, Method, Argv)->
    BinMethod = atom_to_binary(Method, latin1),
    gen_server:cast(Pid, {notify, BinMethod, Argv}).
