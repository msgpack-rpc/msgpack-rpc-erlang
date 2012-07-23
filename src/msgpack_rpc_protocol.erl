%%%-------------------------------------------------------------------
%%% @author UENISHI Kota <kuenishi@gmail.com>
%%% @copyright (C) 2012, UENISHI Kota
%%% @doc
%%%
%%% @end
%%% Created : 22 Jul 2012 by UENISHI Kota <kuenishi@gmail.com>
%%%-------------------------------------------------------------------
-module(msgpack_rpc_protocol).
-behaviour(cowboy_protocol).

-export([start_link/4]). %% API.
-export([init/4, parse_request/1]). %% FSM.

-include("msgpack_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

-record(state, {
	  listener :: pid(),
	  socket :: inet:socket(),
	  transport :: module(),
	  %% dispatch :: cowboy_dispatcher:dispatch_rules(),
	  handler :: {module(), any()},
	  %% onrequest :: undefined | fun((#http_req{}) -> #http_req{}),
	  %% onresponse = undefined :: undefined | fun((cowboy_http:status(),
	  %% 					     cowboy_http:headers(), #http_req{}) -> #http_req{}),
	  %% urldecode :: {fun((binary(), T) -> binary()), T},
	  req_keepalive = 1 :: integer(),
	  max_keepalive :: integer(),
	  max_line_length :: integer(),
	  timeout :: timeout(),
	  buffer = <<>> :: binary(),
	  hibernate = false :: boolean(),
	  loop_timeout = infinity :: timeout(),
	  loop_timeout_ref :: undefined | reference(),
	  module = undefined :: module()
	 }).

-spec start_link(pid(), inet:socket(), module(), any()) -> {ok, pid()}.
start_link(ListenerPid, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [ListenerPid, Socket, Transport, Opts]),
    {ok, Pid}.

%% @private
-spec init(pid(), inet:socket(), module(), any()) -> ok.
init(ListenerPid, Socket, Transport, Opts) ->
    MaxKeepalive = proplists:get_value(max_keepalive, Opts, infinity),
    MaxLineLength = proplists:get_value(max_line_length, Opts, 4096),
    Timeout = proplists:get_value(timeout, Opts, 5000),
    case proplists:get_value(module, Opts) of
	undefined -> {error, no_module_defined};
	Module ->
	    ok = cowboy:accept_ack(ListenerPid),
    	    ok = Transport:controlling_process(Socket, self()),
	    wait_request(#state{listener=ListenerPid, socket=Socket, transport=Transport,
				max_keepalive=MaxKeepalive, max_line_length=MaxLineLength,
				timeout=Timeout, module=Module })
    end.

-spec wait_request(#state{}) -> ok.
wait_request(State=#state{socket=Socket, transport=Transport,
			  timeout=T, buffer=Buffer}) ->
    ok = Transport:setopts(Socket, [{active, once}]),
    receive
	{tcp, Socket, Data} ->
	    parse_request(State#state{buffer= << Buffer/binary, Data/binary >>});
	{tcp_error, Socket, _Reason} ->
	    terminate(State);
	{reply, Binary} ->
	    Transport:send(Socket, Binary),
	    wait_request(State)
    after T->
	    terminate(State)
    end.

%% @private
parse_request(State=#state{buffer=Buffer, module=Module}) ->
    case msgpack:unpack(Buffer) of
	{[?MP_TYPE_NOTIFY,M,Argv], Remain} ->
	    spawn_notify_handler(Module, M, Argv),
	    parse_request(State#state{buffer=Remain});
	{[?MP_TYPE_REQUEST,CallID,M,Argv], Remain} ->
	    spawn_request_handler(CallID, Module, M, Argv),
	    parse_request(State#state{buffer=Remain});
	{error, incomplete} ->
	    wait_request(State);
	{error, Reason} ->
	    error_logger:error_msg("error: ~p~n", [Reason]),
	    terminate(State)
    end.

spawn_notify_handler(Module, M, Argv)->
    spawn(fun()->
		  Method = binary_to_existing_atom(M, latin1),
		  erlang:apply(Module, Method, Argv)
	  end).

spawn_request_handler(CallID, Module, M, Argv)->
    Pid = self(),
    F = fun()->
		Method = binary_to_existing_atom(M, latin1),
		Prefix = [?MP_TYPE_RESPONSE, CallID],
		try erlang:apply(Module,Method,Argv) of
		    Result -> Pid ! {reply, msgpack:pack(Prefix ++ [nil, Result])}
		catch
		    Throw  -> Pid ! {reply, msgpack:pack(Prefix ++ [Throw, nil])}
		end
	end,
    spawn(F).


%% -spec handler_init(#http_req{}, #state{}) -> ok.
%% handler_init(Req, State=#state{transport=Transport,
%% 		handler={Handler, Opts}}) ->
%% 	try Handler:init({Transport:name(), http}, Req, Opts) of
%% 		{ok, Req2, HandlerState} ->
%% 			handler_handle(HandlerState, Req2, State);
%% 		{loop, Req2, HandlerState} ->
%% 			handler_before_loop(HandlerState, Req2, State);
%% 		{loop, Req2, HandlerState, hibernate} ->
%% 			handler_before_loop(HandlerState, Req2,
%% 				State#state{hibernate=true});
%% 		{loop, Req2, HandlerState, Timeout} ->
%% 			handler_before_loop(HandlerState, Req2,
%% 				State#state{loop_timeout=Timeout});
%% 		{loop, Req2, HandlerState, Timeout, hibernate} ->
%% 			handler_before_loop(HandlerState, Req2,
%% 				State#state{hibernate=true, loop_timeout=Timeout});
%% 		{shutdown, Req2, HandlerState} ->
%% 			handler_terminate(HandlerState, Req2, State);
%% 		%% @todo {upgrade, transport, Module}
%% 		{upgrade, protocol, Module} ->
%% 			upgrade_protocol(Req, State, Module)
%% 	catch Class:Reason ->
%% 		error_terminate(500, State),
%% 		PLReq = lists:zip(record_info(fields, http_req), tl(tuple_to_list(Req))),
%% 		error_logger:error_msg(
%% 			"** Handler ~p terminating in init/3~n"
%% 			"   for the reason ~p:~p~n"
%% 			"** Options were ~p~n"
%% 			"** Request was ~p~n** Stacktrace: ~p~n~n",
%% 			[Handler, Class, Reason, Opts, PLReq, erlang:get_stacktrace()])
%% 	end.

%% -spec upgrade_protocol(#http_req{}, #state{}, atom()) -> ok.
%% upgrade_protocol(Req, State=#state{listener=ListenerPid,
%% 		handler={Handler, Opts}}, Module) ->
%% 	case Module:upgrade(ListenerPid, Handler, Opts, Req) of
%% 		{UpgradeRes, Req2} -> next_request(Req2, State, UpgradeRes);
%% 		_Any -> terminate(State)
%% 	end.

%% -spec handler_handle(any(), #http_req{}, #state{}) -> ok.
%% handler_handle(HandlerState, Req, State=#state{handler={Handler, Opts}}) ->
%% 	try Handler:handle(Req, HandlerState) of
%% 		{ok, Req2, HandlerState2} ->
%% 			terminate_request(HandlerState2, Req2, State)
%% 	catch Class:Reason ->
%% 		PLReq = lists:zip(record_info(fields, http_req), tl(tuple_to_list(Req))),
%% 		error_logger:error_msg(
%% 			"** Handler ~p terminating in handle/2~n"
%% 			"   for the reason ~p:~p~n"
%% 			"** Options were ~p~n** Handler state was ~p~n"
%% 			"** Request was ~p~n** Stacktrace: ~p~n~n",
%% 			[Handler, Class, Reason, Opts,
%% 			 HandlerState, PLReq, erlang:get_stacktrace()]),
%% 		handler_terminate(HandlerState, Req, State),
%% 		error_terminate(500, State)
%% 	end.

%% %% We don't listen for Transport closes because that would force us
%% %% to receive data and buffer it indefinitely.
%% -spec handler_before_loop(any(), #http_req{}, #state{}) -> ok.
%% handler_before_loop(HandlerState, Req, State=#state{hibernate=true}) ->
%% 	State2 = handler_loop_timeout(State),
%% 	catch erlang:hibernate(?MODULE, handler_loop,
%% 		[HandlerState, Req, State2#state{hibernate=false}]),
%% 	ok;
%% handler_before_loop(HandlerState, Req, State) ->
%% 	State2 = handler_loop_timeout(State),
%% 	handler_loop(HandlerState, Req, State2).

%% %% Almost the same code can be found in cowboy_http_websocket.
%% -spec handler_loop_timeout(#state{}) -> #state{}.
%% handler_loop_timeout(State=#state{loop_timeout=infinity}) ->
%% 	State#state{loop_timeout_ref=undefined};
%% handler_loop_timeout(State=#state{loop_timeout=Timeout,
%% 		loop_timeout_ref=PrevRef}) ->
%% 	_ = case PrevRef of undefined -> ignore; PrevRef ->
%% 		erlang:cancel_timer(PrevRef) end,
%% 	TRef = erlang:start_timer(Timeout, self(), ?MODULE),
%% 	State#state{loop_timeout_ref=TRef}.

%% -spec handler_loop(any(), #http_req{}, #state{}) -> ok.
%% handler_loop(HandlerState, Req, State=#state{loop_timeout_ref=TRef}) ->
%% 	receive
%% 		{timeout, TRef, ?MODULE} ->
%% 			terminate_request(HandlerState, Req, State);
%% 		{timeout, OlderTRef, ?MODULE} when is_reference(OlderTRef) ->
%% 			handler_loop(HandlerState, Req, State);
%% 		Message ->
%% 			handler_call(HandlerState, Req, State, Message)
%% 	end.

%% -spec handler_call(any(), #http_req{}, #state{}, any()) -> ok.
%% handler_call(HandlerState, Req, State=#state{handler={Handler, Opts}},
%% 		Message) ->
%% 	try Handler:info(Message, Req, HandlerState) of
%% 		{ok, Req2, HandlerState2} ->
%% 			terminate_request(HandlerState2, Req2, State);
%% 		{loop, Req2, HandlerState2} ->
%% 			handler_before_loop(HandlerState2, Req2, State);
%% 		{loop, Req2, HandlerState2, hibernate} ->
%% 			handler_before_loop(HandlerState2, Req2,
%% 				State#state{hibernate=true})
%% 	catch Class:Reason ->
%% 		PLReq = lists:zip(record_info(fields, http_req), tl(tuple_to_list(Req))),
%% 		error_logger:error_msg(
%% 			"** Handler ~p terminating in info/3~n"
%% 			"   for the reason ~p:~p~n"
%% 			"** Options were ~p~n** Handler state was ~p~n"
%% 			"** Request was ~p~n** Stacktrace: ~p~n~n",
%% 			[Handler, Class, Reason, Opts,
%% 			 HandlerState, PLReq, erlang:get_stacktrace()]),
%% 		handler_terminate(HandlerState, Req, State),
%% 		error_terminate(500, State)
%% 	end.

%% -spec handler_terminate(any(), #http_req{}, #state{}) -> ok.
%% handler_terminate(HandlerState, Req, #state{handler={Handler, Opts}}) ->
%% 	try
%% 		Handler:terminate(Req#http_req{resp_state=locked}, HandlerState)
%% 	catch Class:Reason ->
%% 		PLReq = lists:zip(record_info(fields, http_req), tl(tuple_to_list(Req))),
%% 		error_logger:error_msg(
%% 			"** Handler ~p terminating in terminate/2~n"
%% 			"   for the reason ~p:~p~n"
%% 			"** Options were ~p~n** Handler state was ~p~n"
%% 			"** Request was ~p~n** Stacktrace: ~p~n~n",
%% 			[Handler, Class, Reason, Opts,
%% 			 HandlerState, PLReq, erlang:get_stacktrace()])
%% 	end.

%% -spec terminate_request(any(), #http_req{}, #state{}) -> ok.
%% terminate_request(HandlerState, Req, State) ->
%% 	HandlerRes = handler_terminate(HandlerState, Req, State),
%% 	next_request(Req, State, HandlerRes).

%% -spec next_request(#http_req{}, #state{}, any()) -> ok.
%% next_request(Req=#http_req{connection=Conn}, State=#state{
%% 		req_keepalive=Keepalive}, HandlerRes) ->
%% 	RespRes = ensure_response(Req),
%% 	{BodyRes, Buffer} = ensure_body_processed(Req),
%% 	%% Flush the resp_sent message before moving on.
%% 	receive {cowboy_http_req, resp_sent} -> ok after 0 -> ok end,
%% 	case {HandlerRes, BodyRes, RespRes, Conn} of
%% 		{ok, ok, ok, keepalive} ->
%% 			?MODULE:parse_request(State#state{
%% 				buffer=Buffer, req_empty_lines=0,
%% 				req_keepalive=Keepalive + 1});
%% 		_Closed ->
%% 			terminate(State)
%% 	end.

%% -spec ensure_body_processed(#http_req{}) -> {ok | close, binary()}.
%% ensure_body_processed(#http_req{body_state=done, buffer=Buffer}) ->
%% 	{ok, Buffer};
%% ensure_body_processed(Req=#http_req{body_state=waiting}) ->
%% 	case cowboy_http_req:skip_body(Req) of
%% 		{ok, Req2} -> {ok, Req2#http_req.buffer};
%% 		{error, _Reason} -> {close, <<>>}
%% 	end;
%% ensure_body_processed(Req=#http_req{body_state={multipart, _, _}}) ->
%% 	{ok, Req2} = cowboy_http_req:multipart_skip(Req),
%% 	ensure_body_processed(Req2).

%% -spec ensure_response(#http_req{}) -> ok.
%% %% The handler has already fully replied to the client.
%% ensure_response(#http_req{resp_state=done}) ->
%% 	ok;
%% %% No response has been sent but everything apparently went fine.
%% %% Reply with 204 No Content to indicate this.
%% ensure_response(Req=#http_req{resp_state=waiting}) ->
%% 	_ = cowboy_http_req:reply(204, [], [], Req),
%% 	ok;
%% %% Terminate the chunked body for HTTP/1.1 only.
%% ensure_response(#http_req{method='HEAD', resp_state=chunks}) ->
%% 	ok;
%% ensure_response(#http_req{version={1, 0}, resp_state=chunks}) ->
%% 	ok;
%% ensure_response(#http_req{socket=Socket, transport=Transport,
%% 		resp_state=chunks}) ->
%% 	Transport:send(Socket, <<"0\r\n\r\n">>),
%% 	ok.

%% %% Only send an error reply if there is no resp_sent message.
%% -spec error_terminate(cowboy_http:status(), #state{}) -> ok.
%% error_terminate(Code, State=#state{socket=Socket, transport=Transport,
%% 		onresponse=OnResponse}) ->
%% 	receive
%% 		{cowboy_http_req, resp_sent} -> ok
%% 	after 0 ->
%% 		_ = cowboy_http_req:reply(Code, #http_req{
%% 			socket=Socket, transport=Transport, onresponse=OnResponse,
%% 			connection=close, pid=self(), resp_state=waiting}),
%% 		ok
%% 	end,
%% 	terminate(State).

-spec terminate(#state{}) -> ok.
terminate(#state{socket=Socket, transport=Transport}) ->
	Transport:close(Socket),
	ok.

%% Internal.

-ifdef(TEST).

start_stop_test()->
    ok = application:start(cowboy),
    {ok, _} = cowboy:start_listener(testlistener, 3,
				    cowboy_tcp_transport, [{port, 9199}],
				    msgpack_rpc_protocol, [{module, dummy}]),
    ok = cowboy:stop_listener(testlistener),
    ok = application:stop(cowboy).

-endif.
