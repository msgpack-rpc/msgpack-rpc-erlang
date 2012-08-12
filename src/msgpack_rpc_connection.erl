%%%-------------------------------------------------------------------
%%% @author UENISHI Kota <kuenishi@gmail.com>
%%% @copyright (C) 2012, UENISHI Kota
%%% @doc
%%%
%%% @end
%%% Created : 25 Jul 2012 by UENISHI Kota <kuenishi@gmail.com>
%%%-------------------------------------------------------------------
-module(msgpack_rpc_connection).

-behaviour(gen_server).

%% API
-export([start_link/1]).

-include_lib("eunit/include/eunit.hrl").
-include("msgpack_rpc.hrl").
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state,
	{
	  connection :: pid() | inet:socket(),
	  transport  :: atom(),
	  counter = 0 :: non_neg_integer(),
	  session = [] :: [ {non_neg_integer(), none|{result,msgpack:msgpack_term()}|{waiting,term()}} ],
	  buffer = <<>> :: binary()
	 }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Argv) ->
    gen_server:start_link(?MODULE, Argv, [{debug, [log,trace]}]).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init(Argv) ->
    Transport = proplists:get_value(transport, Argv, cowboy_tcp_transport),
    IP   = proplists:get_value(ipaddr, Argv, localhost),
    Port = proplists:get_value(port,   Argv, 9199),
    Opts = proplists:get_value(opts,   Argv, [binary,{packet,raw},{active,once}]),
    {ok, Socket} = Transport:connect(IP, Port, Opts),
    ok = Transport:controlling_process(Socket, self()),
    {ok, #state{connection=Socket, transport=Transport}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({call_async, Method, Argv}, _From,
	    State = #state{connection=Socket, transport=Transport, session=Sessions, counter=Count}) ->
    CallID = Count,
    Binary = msgpack:pack([?MP_TYPE_REQUEST, CallID, Method, Argv]),
    ok=Transport:send(Socket, Binary),
    ok=Transport:setopts(Socket, [{active,once}]),
    {reply, {ok, CallID}, State#state{counter=Count+1, session=[{CallID,none}|Sessions]}};

handle_call({join, CallID}, From, State = #state{session=Sessions0}) ->
    case lists:keytake(CallID, 1, Sessions0) of
	false -> {reply, {error, norequest}, State}; % unknown CallID

	{value, {CallID, none}, Sessions} -> % do receive
	    {noreply, State#state{session=[{CallID,{waiting,From}}|Sessions]}};

	{value, {CallID, {result, Term}}, Sessions} ->
	    {reply, Term, State#state{session=Sessions}};

	{value, {CallID, {waiting, From}}, _} ->
	    {reply, {error, waiting}, State};
	    
	{value, {CallID, {waiting, From1}}, Sessions1} -> % overwrite
	    {noreply, State#state{session=[{CallID, {wairing, From1}}|Sessions1]}};

	_ -> % unexpected error
	    {noreply, State}
    end;

handle_call(close, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, badevent}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({notify, Method, Argv}, State = #state{connection=Socket, transport=Transport}) ->

    Binary = msgpack:pack([?MP_TYPE_NOTIFY, Method, Argv]),
    ok=Transport:send(Socket, Binary),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

    % when transport=cowboy_tcp_transport, other 
handle_info({tcp, Socket, Binary}, State = #state{transport=Transport,session=Sessions0, buffer=Buf}) ->
    NewBuffer = <<Buf/binary, Binary/binary>>,
    ok=Transport:setopts(Socket, [{active,once}]),

    case msgpack:unpack(NewBuffer) of
	{error, incomplete} ->
	    {noreply, State#state{buffer=NewBuffer}};
	{error, {badarg, Reason}} ->
	    {stop, {error, Reason}, State};
	{error, Reason} ->
	    ?debugVal({error, Reason}),
	    {noreply, State#state{buffer=NewBuffer}};
	{Term, Remain} ->
	    [?MP_TYPE_RESPONSE, CallID, ResCode, Result] = Term,
	    Retval = case ResCode of nil ->   {ok, Result};
                                     Error -> {error, Error} end,

	    case lists:keytake(CallID, 1, Sessions0) of
		false -> {noreply, State};
		{value, {CallID, none}, Sessions} ->
		    {noreply, State#state{session=[{CallID, {result, Retval}}|Sessions],
					  buffer=Remain}};
		{value, {CallID, {waiting, From}}, Sessions} ->
		    gen_server:reply(From, Retval),
		    {noreply, State#state{session=Sessions, buffer=Remain}}
	    end
    end;

handle_info(_Info, State = #state{connection=Socket,transport=Transport}) ->
    ?debugVal(_Info),
    ok=Transport:setopts(Socket, [{active,once}]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State = #state{connection=Socket, transport=Transport}) ->
    Transport:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
