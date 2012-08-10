MessagePack-RPC Erlang
======================

This code is in alpha-release. Synchronous RPC seems working.

- prequisites for runtime

Erlang runtime system (http://erlang.org/)

- prequisites for build and test

GNU Make, Erlang, (optional)MessagePack-RPC/C++


build
-----

::

  $ ./rebar get-deps
  $ ./rebar compile



client
------

::

  {ok, Pid} = msgpack_rpc_client:connect(tcp, localhost, 9199, []),
  {ok, Ret} = msgpack_rpc_client:call(Pid, hello, []),
  ok = msgpack_rpc_client:close(Pid).

server
------

Implement a module with functions exported. see ``test/msgpack_rpc_test.erl`` .

::

    ok = application:start(cowboy),
    {ok, _} = cowboy:start_listener(testlistener, 3,
                                    cowboy_tcp_transport, [{port, 9199}],
                                    msgpack_rpc_protocol, [{module, msgpack_rpc_test}]),


License
-------

Apache 2.0

TODO
----

- session TIMEOUTs for client and server
- error handling 
-- what if happens when badarg/noproc/bad_clause, and exceptions.
- crosslang test
- coverage 100%
- UDS transport
- SCTP/SSL/zip and more transport ...
- rewrite tutorial and README
- release handling (/release/*.appup)
- full-spec type/spec notation
- longrun test
