REBAR       ?= ./rebar
DIALYZER    ?= dialyzer
ERL         ?= erl +A 4 +K true


DIALYZER_WARNINGS = -Wunmatched_returns -Werror_handling \
                    -Wrace_conditions -Wunderspecs

.PHONY: all compile test qc clean get-deps build-plt dialyze

all: compile

compile:
	@$(REBAR) compile

debug:
	@$(REBAR) compile -Ddebug

test: compile
	@$(REBAR) eunit skip_deps=true

qc: compile
	@$(REBAR) qc skip_deps=true

clean:
	@$(REBAR) clean

get-deps:
	@$(REBAR) get-deps

ct:
	@$(REBAR) skip_deps=true ct

.dialyzer_plt:
	@$(DIALYZER) --build_plt --output_plt .dialyzer_plt \
	    --apps kernel stdlib

build-plt: .dialyzer_plt

dialyze: build-plt
	@$(DIALYZER) --src src --plt .dialyzer_plt $(DIALYZER_WARNINGS)

run: debug
	@echo "[ Run (debug mode)... ]"
	@$(ERL) -name mxnode01@127.0.0.1\
                -pa ebin deps/*/ebin \
                -s mx_helper\
                -setcookie devcook -Ddebug=true

runnodeb: clean compile
	@echo "[ Run (debug mode)... ]"
	@$(ERL) -name mxnode01@127.0.0.1\
                -pa ebin deps/*/ebin \
                -s mx_helper\
                -setcookie devcook
run2: debug
	@echo "[ Run (debug mode)... ]"
	@$(ERL) -name mxnode02@127.0.0.1\
                -pa ebin deps/*/ebin \
                -s mx_helper\
                -mxmaster mxnode01@127.0.0.1\
                -setcookie devcook -Ddebug=true
