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

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([nodes/0,
         status/0,
         clear_all_tables/0]).

-include_lib("include/mx.hrl").
-include_lib("include/log.hrl").

-record(state, {
          status   :: starting | running
         }).

%%%===================================================================
%%% API
%%%===================================================================

nodes() ->
    gen_server:call(?MODULE, nodes).

status() ->
    gen_server:call(?MODULE, status).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    process_flag(trap_exit, true),

    case application:get_env(mx, mnesia_base_dir, undefined) of
        Dir when Dir == ""; Dir == undefined ->
            pass;
        MnesiaBaseDir when is_list(MnesiaBaseDir) ->
            NodeDir = MnesiaBaseDir ++ node(),
            ok = filelib:ensure_dir(NodeDir),
            application:set_env(mnesia, dir, NodeDir)
    end,

    case application:get_env(mx, master, undefined) of
        X when X == ""; X == undefined ->
            run_as_master();
        Master when is_atom(Master); is_list(Master) ->
            run_as_slave(Master)
    end,

    {ok, #state{status = running}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(status, _, #state{status = S} = State) ->
    {reply, S, State};

handle_call(nodes, _From, State) ->
    Nodes = mnesia:system_info(running_db_nodes),
    {reply, Nodes, State};

handle_call(Request, _From, State) ->
    ?ERR("unhandled call: ~p", [Request]),
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(Msg, State) ->
    ?ERR("unhandled cast: ~p", [Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_info(Info, State) ->
    ?ERR("unhandled info: ~p", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
run_as_master() ->
    ?DBG("Run mnesia as MASTER on [~p]", [node()]),
    case mnesia:create_schema([node()]) of
        ok ->
            ok;
        {error, {_, {already_exists, _}}} ->
            ok;
        {error, E} ->
            ?ERR("failed to create Mnesia schema: ~p", [E])
    end,
    ok = mnesia:start(),

    [create_table(T,A) || {T,A} <- ?MXTABLES],
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    clear_all_tables().

run_as_slave(Master) when is_list(Master) ->
    run_as_slave(list_to_atom(Master));

run_as_slave(Master) when is_atom(Master) ->
    ?DBG("Run mnesia as SLAVE on [~p] and link to the master [~p]", [node(), Master]),
    ok = stop(),
    ok = mnesia:delete_schema([node()]),
    ok = mnesia:start(),

    case mnesia:change_config(extra_db_nodes, [Master]) of
        [] ->
            throw({error, "failed to start Mnesia in slave mode"});
        {ok, Cluster} ->
            % FIXME.
            ?DBG("Mnesia cluster: ~p", [Cluster]),
            ok
    end,

    %% there is no clear_all_tables() call, because in that case slave
    %% can clear all masters tables
    [copy_table(Table) || {Table, _Attrs} <- ?MXTABLES],
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity).


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
        Error                           ->
            ?ERR("Got error on create table: ~p", [Error]),
            Error
    end.

copy_table(T) ->
    case mnesia:add_table_copy(T, node(), ram_copies) of
        {atomic, ok}                        -> ok;
        {aborted, {already_exists, _, _}}   -> ok;
        Error                               ->
            ?ERR("Got error on copy table: ~p", [Error]),
            Error
    end.

clear_all_tables() ->
    [mnesia:clear_table(Table) || {Table, _Attts} <- ?MXTABLES].
