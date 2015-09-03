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

-module(mx_mnesia).

-export([start/0, start/1, stop/0]).

-include_lib("include/mx.hrl").
-include_lib("include/log.hrl").

start() ->
    start(master).

start(master) ->
    case mnesia:create_schema([node()]) of
        ok ->
            ok;
        {error, {_, {already_exists, _}}} ->
            ok;
        {error, E} ->
            ?ERR("failed to create Mnesia schema: ~p", [E])
    end,
    ok = mnesia:start(),
    [create_table(T,A) || {T,A} <- ?MXMNESIA_TABLES],
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    ok;

% start as slave
start(MasterNode) ->
    ok = stop(),
    ok = mnesia:delete_schema([node()]),
    ok = mnesia:start(),
    case mnesia:change_config(extra_db_nodes, [MasterNode]) of
        [] ->
            throw({error, "failed to start Mnesia in slave mode"});
        {ok, Cluster} ->
            % FIXME.
            ?DBG("Mnesia cluster: ~p", [Cluster]),
            ok
    end,
    [copy_table(T) || T <- ?MXMNESIA_TABLES],
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    ok.

stop() ->
    mnesia:stop(),
    wait(10). % 10 sec

wait(N) ->
    case mnesia:system_info(is_running) of
        no ->
            ok;
        stopping when N == 0 ->
            lager:error("Can not stop Mnesia"),
            cantstop;

        stopping ->
            timer:sleep(1000),
            wait(N - 1);
        X ->
            ?ERR("unhandled mnesia state: ~p", [X]),
            error
    end.

create_table(T, A) ->
    case mnesia:create_table(T, A) of
        {atomic, ok}                    -> ok;
        {aborted, {already_exists, _}}  -> ok;
        Error                           -> Error
    end.

copy_table(T) ->
    case mnesia:add_table_copy(T, node(), ram_copies) of
        {atomic, ok}                        -> ok;
        {aborted, {already_exists, _, _}}   -> ok;
        Error                               -> Error
    end.
