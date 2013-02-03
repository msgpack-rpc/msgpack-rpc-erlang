MessagePack-RPC Erlang
======================

.. image:: https://secure.travis-ci.org/msgpack-rpc/msgpack-rpc-erlang.png

- prequisites for runtime

Erlang runtime system (http://erlang.org/ ) >= R15B0x

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

    ok = application:start(ranch),
    {ok, _} = msgpack_rpc_server:start(testlistener, tcp, msgpack_rpc_test, [{port,9199}]),


Instead SSL is also available:

::

    ok = application:start(crypto),
    ok = application:start(ssl),
    ok = application:start(ranch),
    {ok, _} = msgpack_rpc_server:start(testlistener, ssl, msgpack_rpc_test,
                                       [{port,9199}, {certfile, "foo.pem"}, {keyfile, "bar.pem"}]),


License
-------

Apache 2.0

TODO
----

- session TIMEOUTs for client and server
- error handling -- what if happens when badarg/noproc/bad_clause, and exceptions.
- crosslang test
- UDS, SCTP/zip and more transport ...
- release handling (/release/*.appup)
- full-spec type/spec notation
- longrun test
