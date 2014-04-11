.PHONY: compile xref eunit clean doc check make deps test

all: compile xref
test: eunit

# for busy typos
m: all
ma: all
mak: all
make: all

deps:
	@./rebar get-deps
	@./rebar check-deps

compile: deps
	@./rebar compile

xref: compile
	@./rebar xref

test: eunit
eunit: compile
	@./rebar skip_deps=true eunit

clean:
	@./rebar clean

doc:
	@./rebar doc

check: compile
#	@echo "you need ./rebar build-plt before make check"
#	@./rebar build-plt
	@./rebar check-plt
	@./rebar dialyze

crosslang:
	@echo "do ERL_LIBS=../ before you make crosslang or fail"
	cd test && make crosslang
