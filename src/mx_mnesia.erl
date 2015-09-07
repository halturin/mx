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

-include_lib("include/mx.hrl").
-include_lib("include/log.hrl").

-record(state, {status}).
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

    case application:get_env(?MODULE, master) of
        {ok, Master} when is_atom(Master) ->
            % run as slave
            gen_server:cast(self(), {master, Master});

        _ ->
            % run as master
            gen_server:cast(self(), master)
    end,

    {ok, #state{status = []}}.

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
handle_cast(master, State) ->
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
    [create_table(T,A) || {T,A} <- ?MXMNESIA_TABLES],
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    {noreply, State};


handle_cast({master, Master}, State) ->
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
    [copy_table(T) || T <- ?MXMNESIA_TABLES],
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),


    {noreply, State};


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
