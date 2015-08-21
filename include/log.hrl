-ifndef(LOG_HRL).
-define(LOG_HRL, true).

-define(CURRENT_FUN_NAME, element(2, element(2, process_info(self(), current_function)))).
-define(CURRENT_FUN_NAME_STR, atom_to_list(?CURRENT_FUN_NAME)).

-ifdef(debug).

-define(DBG(Format),                lager:log(debug, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(DBG(Format, Data),          lager:log(debug, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-else.

-define(DBG(Format),                ok).
-define(DBG(Format, Data),          ok).

-endif. % debug

-define(INFO(Format),               lager:log(info, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(INFO(Format, Data),         lager:log(info, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).
-define(LOG(Format),                lager:log(info, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(LOG(Format, Data),          lager:log(info, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(NOTICE(Format),             lager:log(notice, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(NOTICE(Format, Data),       lager:log(notice, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(WRN(Format),                lager:log(warning, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(WRN(Format, Data),          lager:log(warning, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(ERR(Format),                lager:log(error, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(ERR(Format, Data),          lager:log(error, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(CRITICAL(Format),           lager:log(critical, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(CRITICAL(Format, Data),     lager:log(critical, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(ALERT(Format),              lager:log(alert, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(ALERT(Format, Data),        lager:log(alert, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(PANIC(Format),              lager:log(emergency, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE])).
-define(PANIC(Format, Data),        lager:log(emergency, self(), "~p:~p: " ++ Format, [?MODULE, ?LINE | Data])).

-define(LOG_STACK,                  ?LOG("Stack: ~p", [try throw(42) catch 42 -> erlang:get_stacktrace() end])).

-endif.
