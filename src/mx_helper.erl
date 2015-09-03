%% Copyright (C) 2015 Taras Halturin <halturin@gmail.com>
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%%


-module(mx_helper).

-export([reload/0]).

-export([start/0, stop/0]).

%% includes
-include_lib("include/log.hrl").

-define(APPS, [ syntax_tools, compiler, goldrush, lager, gproc, mx ]).


reload_m(M) ->
    code:purge(M),
    code:soft_purge(M),
    {module, M} = code:load_file(M),
    {ok, M}.


reload() ->
    Modules = [M || {M, P} <- code:all_loaded(), is_list(P) andalso string:str(P, "mx") > 0],
    [reload_m(M) || M <- Modules].


start() ->
    ?DBG("Start apps: ~p", [?APPS]),
    application:load(lager),
    application:set_env(lager, handlers,
        [
            {lager_console_backend, info},
            {lager_file_backend, [{file, "./log/run.log"}, {level, debug}]}
        ]
    ),
    ok = ensure_started(?APPS),

    ok = sync:go(),
    sync:growl(none),
    ok.

stop() ->
    sync:stop(),
    ok = stop_apps(lists:reverse(?APPS)),
    ok.


ensure_started([]) -> ok;
ensure_started([App | Apps]) ->
    case application:start(App) of
        ok -> ensure_started(Apps);
        {error, {already_started, App}} -> ensure_started(Apps)
    end.

stop_apps([]) -> ok;
stop_apps([App | Apps]) ->
    application:stop(App),
    stop_apps(Apps).