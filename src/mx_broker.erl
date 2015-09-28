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

-module(mx_broker).

-behaviour(gen_server).

-compile({no_auto_import,[unregister/1]}).

-export([start_link/2]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% records
-record(state, {
            id      :: non_neg_integer,
            config  :: list(),
            queues
        }).

%% includes
-include_lib("include/log.hrl").
-include_lib("include/mx.hrl").

%%% API
%%%===================================================================


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(I, Opts) ->
    gen_server:start_link(?MODULE, [I, Opts], []).

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
init([I, _Opts]) ->
    process_flag(trap_exit, true),
    gproc_pool:connect_worker(mx_pubsub, {mx_broker, I}),
    QueuesTable = list_to_atom("mx_broker_" ++ integer_to_list(I) ++ "_queues"),
    ets:new(QueuesTable, [named_table, ordered_set]),
    lists:map(fun(X) ->
        Q = mx_queue:new(X),
        ets:insert(QueuesTable,{X, Q})
    end, lists:seq(1, 10)),
    State = #state{
                id      = I,
                config  = [],
                queues  = QueuesTable
               },
    erlang:send_after(0, self(), {'$gen_cast', dispatch}),
    {ok, State}.

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

handle_call({register_client, Client, Opts}, {Pid, _}, State) ->
    ClientHash  = erlang:md5(Client),
    ClientKey   = <<$*, ClientHash/binary>>,
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            C = #?MXCLIENT{
                name     = Client,
                key      = ClientKey,
                related  = [],
                ownerof  = [],
                handler  = proplists:get_value(handler, Opts, Pid),
                async    = proplists:get_value(async, Opts, true),
                defer    = proplists:get_value(defer, Opts, false),
                monitor  = proplists:get_value(monitor, Opts, false),
                comment  = proplists:get_value(comment, Opts, "Client info")
            },

            case mnesia:transaction(fun() -> mnesia:write(C) end) of
                {aborted, E} ->
                    {reply, E, State};
                _ when C#?MXCLIENT.monitor =:= true ->
                    mx:send(?MXSYSTEM_CLIENTS_CHANNEL, {online, Client}),
                    {reply, {clientkey, ClientKey}, State};
                _ ->
                    {reply, {clientkey, ClientKey}, State}
            end;
        [_Client] ->
            {reply, {duplicate, ClientKey}, State}
    end;

handle_call({register_channel, Channel, ClientKey, Opts}, _From, State) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};

        [Client] ->
            ChannelHash = erlang:md5(Channel),
            ChannelKey  = <<$#, ChannelHash/binary>>,
            case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
                [] ->
                    Ch = #?MXCHANNEL{
                        key         = ChannelKey,
                        name        = Channel,
                        related     = [],
                        owners      = [ClientKey],
                        priority    = proplists:get_value(priority, Opts, ?MXQUEUE_PRIO_NORMAL),
                        defer       = proplists:get_value(defer, Opts, true),
                        comment     = proplists:get_value(comment, Opts, "Channel info")
                    },

                    Transaction = fun() ->
                        mnesia:write(Ch),
                        Cl = Client#?MXCLIENT{ownerof = [ChannelKey| Client#?MXCLIENT.ownerof]},
                        mnesia:write(Cl)
                    end,

                    case mnesia:transaction(Transaction) of
                        {aborted, E} ->
                            {reply, E, State};
                        _ ->
                            {reply, {channelkey, ChannelKey}, State}
                    end;

                [_Channel] ->
                    {reply, {duplicate, ChannelKey}, State}
            end
    end;

handle_call({register_pool, Pool, ClientKey, Opts}, _From, State) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client] ->
            PoolHash = erlang:md5(Pool),
            PoolKey = <<$@, PoolHash/binary>>,
            case mnesia:dirty_read(?MXPOOL, PoolKey) of
                [] ->
                    Pl = #?MXPOOL{
                        key         = PoolKey,
                        name        = Pool,
                        related     = [],
                        owners      = [ClientKey],
                        balance     = proplists:get_value(balance, Opts, rr),
                        priority    = proplists:get_value(priority, Opts, ?MXQUEUE_PRIO_NORMAL),
                        defer       = proplists:get_value(defer, Opts, true),
                        comment     = proplists:get_value(comment, Opts, "Pool info")
                    },
                    Transaction = fun() ->
                        mnesia:write(Pl),
                        Cl = Client#?MXCLIENT{ownerof = [PoolKey| Client#?MXCLIENT.ownerof]},
                        mnesia:write(Cl)
                    end,

                    case mnesia:transaction(Transaction) of
                        {aborted, E} ->
                            {reply, E, State};
                        _ ->
                            {reply, {poolkey, PoolKey}, State}
                    end;

                [_Pool] ->
                    {reply, {duplicate, PoolKey}, State}

            end
    end;

handle_call({info, <<$*,_/binary>> = ClientKey}, _From, State) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client] ->
            R = lists:zip(record_info(fields, ?MXCLIENT), tl(tuple_to_list(Client))),
            {reply, R, State}
    end;

handle_call({info, <<$#, _/binary>> = ChannelKey}, _From, State) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            {reply, unknown_channel, State};
        [Channel] ->
            R = lists:zip(record_info(fields, ?MXCHANNEL), tl(tuple_to_list(Channel))),
            {reply, R, State}
    end;

handle_call({info, <<$@, _/binary>> = PoolKey}, _From, State) ->
    case mnesia:dirty_read(?MXPOOL, PoolKey) of
        [] ->
            {reply, unknown_pool, State};
        [Pool] ->
            R = lists:zip(record_info(fields, ?MXPOOL), tl(tuple_to_list(Pool))),
            {reply, R, State}
    end;

handle_call({relate, Key, To}, _From, State) ->
    R = action(relate, Key, To),
    {reply, R, State};

handle_call({unrelate, Key, From}, _From, State) ->
    R = action(unrelate, Key, From),
    {reply, R, State};

handle_call({unregister, Key}, _From, State) ->
    R = unregister(Key),
    {reply, R, State};

handle_call({set, <<$*, _/binary>> = ClientKey, Opts}, _From, State) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client] ->
            Client1 = Client#?MXCLIENT{
                handler = proplists:get_value(handler, Opts, Client#?MXCLIENT.handler),
                async   = proplists:get_value(async, Opts, Client#?MXCLIENT.async),
                defer   = proplists:get_value(defer, Opts, Client#?MXCLIENT.defer),
                monitor = proplists:get_value(monitor, Opts, Client#?MXCLIENT.monitor),
                comment = proplists:get_value(comment, Opts, Client#?MXCLIENT.comment)
            },
            mnesia:transaction(fun() -> mnesia:write(Client1) end),
            {reply, ok, State}
    end;

handle_call({set, <<$#, _/binary>> = ChannelKey, Opts}, _From, State) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            {reply, unknown_channel, State};
        [Channel] ->
            Channel1 = Channel#?MXCHANNEL{
                defer    = proplists:get_value(defer, Opts, Channel#?MXCHANNEL.defer),
                priority = proplists:get_value(priority, Opts, Channel#?MXCHANNEL.priority),
                comment  = proplists:get_value(comment, Opts, Channel#?MXCHANNEL.comment)
            },
            mnesia:transaction(fun() -> mnesia:write(Channel1) end),
            {reply, ok, State}
    end;

handle_call({set, <<$@, _/binary>> = PoolKey, Opts}, _From, State) ->
    case mnesia:dirty_read(?MXPOOL, PoolKey) of
        [] ->
            {reply, unknown_pool, State};
        [Pool] ->
            Pool1 = Pool#?MXPOOL{
                balance  = proplists:get_value(balance, Opts, Pool#?MXPOOL.balance),
                defer    = proplists:get_value(defer, Opts, Pool#?MXPOOL.defer),
                priority = proplists:get_value(priority, Opts, Pool#?MXPOOL.priority),
                comment  = proplists:get_value(comment, Opts, Pool#?MXPOOL.comment)
            },
            mnesia:transaction(fun() -> mnesia:write(Pool1) end),
            {reply, ok, State}
    end;

handle_call({set, <<$#, _/binary>> = ChannelKey, Opts}, _From, State) ->
    {reply, ok, State};

handle_call({set, <<$@, _/binary>> = PoolKey, Opts}, _From, State) ->
    {reply, ok, State};

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
handle_cast({send, To, Message, Opts}, State) when is_record(To, ?MXCLIENT) ->
    ?DBG("Send to client: ~p", [To]),
    #state{queues = QueuesTable} = State,
    #?MXCLIENT{key = Key} = To,
    % peering message priority is 1, but can be overrided via options
    P = proplists:get_value(priority, Opts, 1),
    [{P,Q}|_] = ets:lookup(QueuesTable, P),
    case mx_queue:put({Key, {To, Message}}, Q) of
        {defer, Q1} ->
            defer(1, Key, Message);
        Q1 ->
            pass
    end,
    ets:insert(QueuesTable, {P, Q1}),
    {noreply, State};

handle_cast({send, To, Message, Opts}, State) when is_record(To, ?MXCHANNEL) ->
    ?DBG("Send to channel: ~p", [To]),
    #state{queues = QueuesTable}    = State,
    #?MXCHANNEL{key = Key, priority = ChannelP, defer = Deferrable} = To,
    P = proplists:get_value(priority, Opts, ChannelP),
    [{P,Q}|_] = ets:lookup(QueuesTable, P),
    case mx_queue:put({Key, {To, Message}}, Q) of
        {defer, Q1} when P =:= 1, Deferrable =:= true ->
            defer(P, Key, Message);
        {defer, Q1} when P > 1, Deferrable =:= true ->
            defer(P - 1, Key, Message);
        Q1 ->
            pass
    end,
    ets:insert(QueuesTable, {P, Q1}),
    {noreply, State};

handle_cast({send, To, Message, Opts}, State) when is_record(To, ?MXPOOL) ->
    ?DBG("Send to pool: ~p", [To]),
    #state{queues = QueuesTable}    = State,
    #?MXPOOL{key = Key, priority = PoolP,  defer = Deferrable} = To,
    P = proplists:get_value(priority, Opts, PoolP),
    [{P,Q}|_] = ets:lookup(QueuesTable, P),
    case mx_queue:put({Key, {To, Message}}, Q) of
        {defer, Q1} when P =:= 1, Deferrable =:= true ->
            defer(P, Key, Message);
        {defer, Q1} when P > 1, Deferrable =:= true ->
            defer(P, Key, Message);
        Q1 ->
            pass
    end,
    ets:insert(QueuesTable, {P, Q1}),
    {noreply, State};

handle_cast(dispatch, State) ->
    #state{queues = QueuesTable}    = State,
    Timeout = dispatch(QueuesTable),
    erlang:send_after(Timeout, self(), {'$gen_cast', dispatch}),
    {noreply, State};

handle_cast({flush, Key}, State) ->
    mnesia:delete({?MXDEFER, Key}),
    {noreply, State};

handle_cast({offline, ClientKey}, State) ->
    client_offline(ClientKey),
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
terminate(_Reason, #state{id = ID}) ->
    gproc_pool:disconnect_worker(mx_pubsub, {mx_broker, ID}),
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
unregister(<<$*,_/binary>> = ClientKey) ->
        case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            unknown_client;
        [Client] when Client#?MXCLIENT.monitor =:= true ->
            [unrelate(ClientKey, Ch) || Ch <- Client#?MXCLIENT.related],
            [abandon(I, Client) || I <- Client#?MXCLIENT.ownerof],
            mnesia:transaction(fun() -> mnesia:delete({?MXCLIENT, ClientKey}) end),
            mx:send(?MXSYSTEM_CLIENTS_CHANNEL, {offline, Client}),
            ok;
        [Client] when Client#?MXCLIENT.monitor =:= true ->
            [unrelate(ClientKey, Ch) || Ch <- Client#?MXCLIENT.related],
            [abandon(I, Client) || I <- Client#?MXCLIENT.ownerof],
            mnesia:transaction(fun() -> mnesia:delete({?MXCLIENT, ClientKey}) end),
            ok
    end;

unregister(<<$#, _/binary>> = Key) -> % channel
    case mnesia:dirty_read(?MXCHANNEL, Key) of
        [] ->
            unknown_channel;
        [R] ->
            remove_relations(R#?MXCHANNEL.related),
            remove_owning(R#?MXCHANNEL.owners),
            mnesia:transaction(fun() -> mnesia:delete({?MXCHANNEL, Key}) end),
            ok
    end;

unregister(<<$@, _/binary>> = Key) -> % channel
    case mnesia:dirty_read(?MXPOOL, Key) of
        [] ->
            unknown_pool;
        [R] ->
            remove_relations(R#?MXPOOL.related),
            remove_owning(R#?MXPOOL.owners),
            mnesia:transaction(fun() ->
                mnesia:delete({?MXPOOL, Key}),
                mnesia:delete(?MXKV, {rrpool,Key})
            end),
            ok
    end;

unregister(_Key) ->
    unknown_key.

unrelate(Key, <<$#, _/binary>> = From) ->
    unrelate(Key, From, checked);

unrelate(Key, <<$@, _/binary>> = From) ->
    unrelate(Key, From, checked).

unrelate(Key, From, checked) ->
    case mnesia:dirty_read(?MXRELATION, From) of
        [] ->
            unknown_relation;
        [Relation] ->
            case lists:member(Key, Relation#?MXRELATION.related) of
                false ->
                    unknown_relation;
                true ->
                    Related = lists:delete(Key, Relation#?MXRELATION.related),
                    UpdatedRelation = Relation#?MXRELATION{related = Related},
                    mnesia:transaction(fun() -> mnesia:write(UpdatedRelation) end),
                    ok
            end
    end.

relate(Key, <<$#, _/binary>> = To) ->
    relate(Key, To, checked);

relate(Key, <<$@, _/binary>> = To) ->
    relate(Key, To, checked).

relate(Key, To, checked) ->
    case mnesia:dirty_read(?MXRELATION, To) of
        [] ->
            Relation = #?MXRELATION{
                key     = To,
                related = []
            };
        [Relation] ->
            ok
    end,
    case lists:member(Key, Relation#?MXRELATION.related) of
        false ->
            Related = [Key | Relation#?MXRELATION.related],
            UpdatedRelation = Relation#?MXRELATION{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedRelation) end),
            ok;
        true ->
            related
    end.

remove_relations(Relations) ->
    ?DBG("REMOVE RELATIONS: ~p", [Relations]),
    lists:foldl(
        fun(<<$*,_/binary>> = RelationKey, _) ->
            % client relation
            [Client]      = mnesia:dirty_read(?MXCLIENT, RelationKey),
            Related         = lists:delete(RelationKey, Client#?MXCLIENT.related),
            UpdatedClient   = Client#?MXCLIENT{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end),
            ok;

           (<<$#,_/binary>> = RelationKey, _) ->
           % channel relation
            [Channel]      = mnesia:dirty_read(?MXCHANNEL, RelationKey),
            Related          = lists:delete(RelationKey, Channel#?MXCHANNEL.related),
            UpdatedChannel   = Channel#?MXCHANNEL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok;

            (<<$@,_/binary>> = RelationKey, _) ->
           % pool relation
            [Channel]      = mnesia:dirty_read(?MXCHANNEL, RelationKey),
            Related          = lists:delete(RelationKey, Channel#?MXCHANNEL.related),
            UpdatedChannel   = Channel#?MXCHANNEL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok
    end, ok, Relations).

remove_owning(Owners) ->
    lists:foldl(fun(Key, _) ->
                [Client] = mnesia:dirty_read(?MXCLIENT, Key),
                ClientOwnerOf = lists:delete(Key, Client#?MXCLIENT.ownerof),
                UpdatedClient = Client#?MXCLIENT{ownerof = ClientOwnerOf},
                mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end),
                ok
            end, ok, Owners).

abandon(<<$@,_/binary>> = PoolKey, Client) when is_record(Client, ?MXCLIENT) ->
    case mnesia:dirty_read(?MXPOOL, PoolKey) of
        [] ->
            ok;
        [Pool] ->
            case lists:delete(Client#?MXCLIENT.key, Pool#?MXPOOL.owners) of
                [] ->
                    unregister(PoolKey);
                Owners ->
                    UpdatedPool = Pool#?MXPOOL{owners = Owners},
                    mnesia:transaction(fun() ->mnesia:write(UpdatedPool) end),
                    ok
            end
    end;

abandon(<<$#,_/binary>> = ChannelKey, Client) when is_record(Client, ?MXCLIENT) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            ok;
        [Channel] ->
            case lists:delete(Client#?MXCLIENT.key, Channel#?MXCHANNEL.owners) of
                [] ->
                    unregister(ChannelKey);
                Owners ->
                    UpdatedChannel = Channel#?MXCHANNEL{owners = Owners},
                    mnesia:transaction(fun() ->mnesia:write(UpdatedChannel) end),
                    ok
            end
    end.

dispatch(Q, 0, HasMessages) ->
    {Q, HasMessages};
dispatch(Q, N, HasMessages) ->
    case mx_queue:get(Q) of
        % has no message
        {empty, Q1} ->
            {Q1, HasMessages};
        % async dispatch
        {{value, {_, {To, Message}}}, Q1} when  is_record(To, ?MXCLIENT),
                                                is_pid(To#?MXCLIENT.handler),
                                                To#?MXCLIENT.async =:= true ->
            ?DBG("Dispatch (async) to the client: ~p [MESSAGE: ~p]", [To, Message]),
            To#?MXCLIENT.handler ! Message,
            dispatch(Q1, N - 1, true);

        % sync dispatch
        {{value, {_, {To, Message}}}, Q1} when  is_record(To, ?MXCLIENT),
                                                is_pid(To#?MXCLIENT.handler) ->
            ?DBG("Dispatch to (sync) the client: ~p [MESSAGE: ~p]", [To, Message]),
            Sync = fun() ->
                To#?MXCLIENT.handler ! Message,
                receive
                    ok -> pass
                after
                    ?MX_SEND_TIMEOUT ->
                        client_offline(To#?MXCLIENT.key),
                        case To#?MXCLIENT.defer of
                            true ->
                                P = mx_queue:name(Q1),
                                defer(P+1, To#?MXCLIENT.key, Message);
                            false ->
                                pass
                        end
                end
            end,
            erlang:spawn(Sync),
            dispatch(Q1, N - 1, true);

        % offline client with deferring
        {{value, {_, {To, Message}}}, Q1} when  is_record(To, ?MXCLIENT),
                                                 To#?MXCLIENT.defer == true ->
            ?DBG("Client is offline: ~p. Defer this message.", [To#?MXCLIENT.name]),
            defer(1, To#?MXCLIENT.key, Message),
            dispatch(Q1, N - 1, true);

        % offline client with disabled deferring (drop messages)
        {{value, {_, {To, _Message}}}, Q1} when  is_record(To, ?MXCLIENT) ->
            ?DBG("Client is offline [~p]. Deferring is disabled. Drop this message.", [To#?MXCLIENT.name]),
            dispatch(Q1, N - 1, true);

        % message for channel
        {{value, {_, {To, Message}}}, Q1} when is_record(To, ?MXCHANNEL) ->
            case mnesia:dirty_read(?MXRELATION, To#?MXCHANNEL.key) of
                [] ->
                    pass; % have no receivers
                [Relations] when Relations#?MXRELATION.related == [] ->
                    pass; % have no receivers
                [Relations] ->
                    ?DBG("Dispatch message to the channel [~p]. Send times [~p] ",
                        [To#?MXCHANNEL.name, length(Relations#?MXRELATION.related)]),
                    [mx:send(X, Message, [{priority, To#?MXCHANNEL.priority}]) || X <- Relations#?MXRELATION.related]
            end,
            dispatch(Q1, N - 1, true);

        % message for pool
        {{value, {_, {To, Message}}}, Q1} when is_record(To, ?MXPOOL) ->
            case mnesia:dirty_read(?MXRELATION, To#?MXPOOL.key) of
                [] ->
                    pass; % have no receivers
                [Relations] when Relations#?MXRELATION.related == [] ->
                    pass; % have no receivers
                [Relations] when To#?MXPOOL.balance == rr ->
                    mnesia:transaction(fun() ->
                        L = length(Relations#?MXRELATION.related),
                        case mnesia:wread({?MXKV, {rrpool, To#?MXPOOL.key}}) of
                            [#?MXKV{value = V}] when V < L ->
                                I = V + 1;
                            _ ->
                                I = 1
                        end,
                        KV = #?MXKV{key = {rrpool, To#?MXPOOL.key}, value = I},
                        mnesia:write(KV),
                        X = lists:nth(I, Relations#?MXRELATION.related),
                        ?DBG("Dispatch message to the pool [~p]. Send to [~p] of [~p] ",
                            [To#?MXPOOL.name, I, length(Relations#?MXRELATION.related)]),
                        mx:send(X, Message, [{priority, To#?MXPOOL.priority}])
                    end);

                [Relations] when To#?MXPOOL.balance == random ->
                    N = random:uniform(length(Relations#?MXRELATION.related)),
                    X = lists:nth(N, Relations#?MXRELATION.related),
                    ?DBG("Dispatch message to the pool [~p]. Send to [~p] of [~p] ",
                        [To#?MXPOOL.name, N, length(Relations#?MXRELATION.related)]),
                    mx:send(X, Message, [{priority, To#?MXPOOL.priority}]);
                [Relations] when To#?MXPOOL.balance == hash ->
                    N = erlang:phash(Message, length(Relations#?MXRELATION.related)),
                    X = lists:nth(N, Relations#?MXRELATION.related),
                    ?DBG("Dispatch message to the pool [~p]. Send to [~p] of [~p] ",
                        [To#?MXPOOL.name, N, length(Relations#?MXRELATION.related)]),
                    mx:send(X, Message, [{priority, To#?MXPOOL.priority}])
            end,
            dispatch(Q1, N - 1, true);
        {FIXME, Q1} ->
            ?DBG("FIXME: ~p", [FIXME]),
            dispatch(Q1, N - 1, true)
    end.

% queue name = 1  (priority 1)  - process 10 messages from queue
%              ...
%              10 (priority 10) - process 1 message
dispatch(QueuesTable) ->
    case    lists:foldl(fun(P, HasMessagesAcc) ->
                [{P,Q}|_] = ets:lookup(QueuesTable, P),
                case dispatch(Q, 11 - P, false) of
                    {Q1, true} ->
                        ets:insert(QueuesTable, {P, Q1}),
                        true;
                    {_, false} ->
                        HasMessagesAcc;

                    FIXME ->
                        ?DBG("FIXME: ~p", [FIXME]),
                        false
                end
            end, false, lists:seq(1, 10)) of
        true ->
            0; % cast 'dispatch' immediately
        false ->
            100 % FIXME later. wait 50 ms before 'dispatch casting'
    end.


defer(Priority, To, Message) ->
    Defer = #?MXDEFER{
        priority    = case Priority of
                        X when X < 1 -> 1;
                        X when X > 10 -> 10;
                        X -> X
                      end,
        to          = To,
        message     = Message
    },
    mnesia:transaction(fun() -> mnesia:write(Defer) end).

action(relate, Key, ToKey) ->
    case relate(Key, <<X:8,_/binary>> = ToKey) of
        related when X == 35 -> % '#' - channel
            {already_subscribed, Key};
        related ->
            {already_joined, Key};
        ok ->
            action(relate, Key, ToKey, related)
    end;

action(unrelate, Key, FromKey) ->
    case unrelate(Key, <<X:8,_/binary>> = FromKey) of
        unknown_relation when X == 35 -> % '#' - channel
            {not_subscribed, Key};
        unknown_relation ->
            {not_joined, Key};
        ok ->
            action(unrelate, Key, FromKey, unrelated)
    end.

action(relate, <<$*, _/binary>> = Key, ToKey, related) ->
    case mnesia:dirty_read(?MXCLIENT, Key) of
        [] ->
            unknown_client;
        [Client|_] ->
            Related = [ToKey | Client#?MXCLIENT.related],
            UpdatedClient = Client#?MXCLIENT{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end),
            ok
    end;

action(relate, <<$#, _/binary>> = Key, ToKey, related) ->
   case mnesia:dirty_read(?MXCHANNEL, Key) of
        [] ->
            unknown_channel_client;
        [Channel|_] ->
            Related = [ToKey | Channel#?MXCHANNEL.related],
            UpdatedChannel = Channel#?MXCHANNEL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok
    end;

action(relate, <<$@, _/binary>> = Key, ToKey, related) ->
    case mnesia:dirty_read(?MXPOOL, Key) of
        [] ->
            unknown_pool_client;
        [Pool|_] ->
            Related = [ToKey | Pool#?MXPOOL.related],
            UpdatedPool = Pool#?MXPOOL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedPool) end),
            ok
    end;

action(unrelate, <<$*, _/binary>> = Key, FromKey, unrelated) ->
    case mnesia:dirty_read(?MXCLIENT, Key) of
        [] ->
            unknown_client;
        [Client|_] ->
            Related = lists:delete(FromKey, Client#?MXCLIENT.related),
            UpdatedClient = Client#?MXCLIENT{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end),
            ok
    end;

action(unrelate, <<$#, _/binary>> = Key, FromKey, unrelated) ->
   case mnesia:dirty_read(?MXCHANNEL, Key) of
        [] ->
            unknown_channel_client;
        [Channel|_] ->
            Related = Related = lists:delete(FromKey, Channel#?MXCHANNEL.related),
            UpdatedChannel = Channel#?MXCHANNEL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok
    end;

action(unrelate, <<$@, _/binary>> = Key, FromKey, unrelated) ->
    case mnesia:dirty_read(?MXPOOL, Key) of
        [] ->
            unknown_pool_client;
        [Pool|_] ->
            Related = Related = lists:delete(FromKey, Pool#?MXPOOL.related),
            UpdatedPool = Pool#?MXPOOL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedPool) end),
            ok
    end.

client_offline(<<$*, _/binary>> = ClientKey) ->
    mnesia:transaction(fun() ->
        case mnesia:wread({?MXCLIENT, ClientKey}) of
            [] ->
                % unregistered client
                pass;
            [Client] when Client#?MXCLIENT.monitor =:= true ->
                mx:send(?MXSYSTEM_CLIENTS_CHANNEL, {offline, Client#?MXCLIENT.name}),
                C = Client#?MXCLIENT{handler = offline},
                mnesia:write(C);
            [Client] when Client#?MXCLIENT.monitor =:= false ->
                C = Client#?MXCLIENT{handler = offline},
                mnesia:write(C)
        end
    end).

