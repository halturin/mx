REBAR       ?= ./rebar
DIALYZER    ?= dialyzer
ERL         ?= erl +A 4 +K true


DIALYZER_WARNINGS = -Wunmatched_returns -Werror_handling \
                    -Wrace_conditions -Wunderspecs

.PHONY: all compile test qc clean get-deps build-plt dialyze

all: compile

compile:
	@$(REBAR) compile

test: compile
	@$(REBAR) eunit skip_deps=true

qc: compile
	@$(REBAR) qc skip_deps=true

clean:
	@$(REBAR) clean

get-deps:
	@$(REBAR) get-deps

.dialyzer_plt:
	@$(DIALYZER) --build_plt --output_plt .dialyzer_plt \
	    --apps kernel stdlib

build-plt: .dialyzer_plt

dialyze: build-plt
	@$(DIALYZER) --src src --plt .dialyzer_plt $(DIALYZER_WARNINGS)

run: compile
	@echo "[ Run (debug mode)... ]"
	@$(ERL) -name mxnode01@127.0.0.1\
                -pa ebin deps/*/ebin  ../deps/*/ebin ../*/ebin\
                -s mx_helper\
                -setcookie devcook -Ddebug=true
run2: compile
	@echo "[ Run (debug mode)... ]"
	@$(ERL) -name mxnode02@127.0.0.1\
                -pa ebin deps/*/ebin  ../deps/*/ebin ../*/ebin\
                -s mx_helper\
                -setcookie devcook -Ddebug=true
