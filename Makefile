REBAR       = $(shell pwd)/rebar3
DIALYZER    ?= dialyzer

DIALYZER_WARNINGS = -Wunmatched_returns -Werror_handling \
                    -Wrace_conditions -Wunderspecs

.PHONY: deps compile

all: compile

compile: clean
	@$(REBAR) compile

test: compile
	@$(REBAR) as test eunit

ct:
	@$(REBAR) ct --setcookie devcook --name mxtest001@127.0.0.1

clean:
	@$(REBAR) clean

deps:
	@$(REBAR) deps

build-plt:
	@$(DIALYZER) --build_plt --output_plt .dialyzer_plt \
	    --apps kernel stdlib

dialyze: build-plt
	@$(DIALYZER) --src src --plt .dialyzer_plt $(DIALYZER_WARNINGS)

rel: compile
	$(REBAR) release

release: compile
	$(REBAR) as prod release -n mx

run: release
	$(REBAR) run

tar:
	$(REBAR) as prod tar release -n mx

demo_run: compile
	# only for demonstration purposes
	erl -name $(node_name) -pa _build/default/lib/mx/ebin \
		_build/default/lib/gproc/ebin \
		_build/default/lib/lager/ebin \
		_build/default/lib/goldrush/ebin \
	-config "conf/sys.config" \
	-eval "lists:map(fun(App) -> application:start(App) end, [gproc, syntax_tools, compiler, goldrush, lager])"

