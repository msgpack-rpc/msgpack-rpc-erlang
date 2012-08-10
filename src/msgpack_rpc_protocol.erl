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
	undefined ->
	    error_logger:error_msg("no module defined"),
	    {error, no_module_defined};
	Module ->
	    ok = cowboy:accept_ack(ListenerPid),
    	    ok = Transport:controlling_process(Socket, self()),
	    % ok = Transport:setopts(Socket, [{active, once}]),

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
	{tcp_closed, Socket} ->
	    terminate(State);

	{reply, Binary}->
	    ok = Transport:send(Socket, Binary),
	    wait_request(State);

	Other ->
	    ?debugVal(Other),
	    wait_request(State)

    after T ->
	    case byte_size(Buffer) > 0 of
		true -> % there's something incomplete
		    terminate(State);
		false ->
		    wait_request(State)
	    end
    end.

parse_request(State=#state{buffer=Buffer, module=Module}) ->
    case msgpack:unpack(Buffer) of
	{[?MP_TYPE_REQUEST,CallID,M,Argv], Remain} ->
	    spawn_request_handler(CallID, Module, M, Argv),
	    parse_request(State#state{buffer=Remain});
	{[?MP_TYPE_NOTIFY,M,Argv], Remain} ->
	    spawn_notify_handler(Module, M, Argv),
	    parse_request(State#state{buffer=Remain});
	{error, incomplete} ->
	    wait_request(State);
	{error, Reason} ->
	    ?debugVal(Reason),
	    error_logger:error_msg("error: ~p~n", [Reason]),
	    terminate(State)
    end.

spawn_notify_handler(Module, M, Argv)->
    spawn(fun()->
		  Method = binary_to_existing_atom(M, latin1),
		  try
		      erlang:apply(Module, Method, Argv)
		  catch
		      Class:Throw ->
			  ?debugVal({Method, Throw}),
			  error_logger:error_msg("~p ~p:~p", [?LINE, Class, Throw])
		  end
	  end).

spawn_request_handler(CallID, Module, M, Argv)->
    Pid = self(),
    F = fun()->
		Method = binary_to_existing_atom(M, latin1),
		Prefix = [?MP_TYPE_RESPONSE, CallID],
		try
		    Result = erlang:apply(Module,Method,Argv),
		    %% ?debugVal({Method, Argv}),
		    %% ?debugVal(Result),
		    Pid ! {reply, msgpack:pack(Prefix ++ [nil, Result])}
		catch
		    Class:Throw ->
			Error = lists:flatten(io_lib:format("~p:~p", [Class, Throw])),
			error_logger:error_msg("(~p)~p", [self(), Error]),
			case msgpack:pack(Prefix ++ [Error, nil]) of
			    {error, Reason} -> 
				?debugVal(Reason),
				Pid ! {reply, ["internal error", nil]};
			    Binary when is_binary(Binary) ->
				Pid ! {reply, Binary}
			end
		end
	end,
    spawn(F).

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
