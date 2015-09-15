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

handle_call({register_client, Client, Opts}, From, State) ->
    ClientHash  = erlang:md5(Client),
    ClientKey   = <<$*, ClientHash/binary>>,
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            C = #?MXCLIENT{
                name     = Client,
                key      = ClientKey,
                related  = [],
                ownerof  = [],
                handler  = proplists:get_value(handler, Opts, From),
                comment  = proplists:get_value(comment, Opts, "Client info")
            },

            case mnesia:transaction(fun() -> mnesia:write(C) end) of
                {aborted, E} ->
                    {reply, E, State};
                _ ->
                    {reply, {clientkey, ClientKey}, State}
            end;
        [_Client | _] ->
            {reply, {duplicate, ClientKey}, State}
    end;

handle_call({register_channel, {Channel, Opts}, ClientKey}, From, State) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};

        [Client|_] ->
            ChannelHash = erlang:md5(Channel),
            ChannelKey  = <<$#, ChannelHash/binary>>,
            case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
                [] ->
                    Ch = #?MXCHANNEL{
                        key         = ChannelKey,
                        name        = Channel,
                        related     = [],
                        owners      = [Client#?MXCLIENT.key],
                        handler     = proplists:get_value(handler, Opts, From),
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

                [_Channel|_] ->
                    {reply, {duplicate, ChannelKey}, State}
            end
    end;

handle_call({info_client, ClientKey}, _From, State) ->
    ?LOG("Broker:~p", [State#state.id]),
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client|_] ->
            {reply, Client, State}
    end;

handle_call({info_channel, ChannelKey}, _From, State) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            {reply, unknown_channel, State};
        [Channel|_] ->
            {reply, Channel, State}
    end;

handle_call({subscribe, Client, Channel}, _From, State) ->
    {reply, ok, State};

handle_call({unsubscribe, Client, Channel}, _From, State) ->
    {reply, ok, State};

handle_call({join, Client, Pool}, _From, State) ->
    {reply, ok, State};

handle_call({leave, Client, Pool}, _From, State) ->
    {reply, ok, State};

handle_call({unregister, Key}, _From, State) ->
    R = unregister(Key),
    {reply, R, State};


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
        [Client|_] ->
            [unrelate(Ch, ClientKey) || Ch <- Client#?MXCLIENT.related],
            [abandon(I, Client) || I <- Client#?MXCLIENT.ownerof],
            mnesia:transaction(fun() -> mnesia:delete({?MXCLIENT, ClientKey}) end),
            ok
    end;

unregister(<<$#, _/binary>> = Key) -> % channel
    case mnesia:dirty_read(?MXCHANNEL, Key) of
        [] ->
            unknown_channel;
        [R|_] ->
            remove_relations(R#?MXCHANNEL.related),
            remove_owning(R#?MXCHANNEL.owners),
            mnesia:transaction(fun() -> mnesia:delete({?MXCHANNEL, Key}) end)
    end;

unregister(<<$@, _/binary>> = Key) -> % channel
    case mnesia:dirty_read(?MXPOOL, Key) of
        [] ->
            unknown_pool;
        [R|_] ->
            remove_relations(R#?MXPOOL.related),
            remove_owning(R#?MXPOOL.owners),
            mnesia:transaction(fun() -> mnesia:delete({?MXPOOL, Key}) end)
    end;

unregister(_Key) ->
    unknown_key.

unrelate(<<X:8/binary, _/binary>> = RelatedToKey, Key) when X =:= <<$@>>;
                                                            X =:= <<$#>> ->
    case mnesia:dirty_read(?MXRELATION, RelatedToKey) of
        [] ->
            ok;
        [Relation|_] ->
            Related = lists:delete(Key, Relation#?MXRELATION.related),
            UpdatedRelation = Relation#?MXRELATION{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedRelation) end),
            ok
    end.

relate(<<X:8/binary, _/binary>> = RelateToKey, Key) when X =:= <<$@>>;
                                                         X =:= <<$#>> ->
    case mnesia:dirty_read(?MXRELATION, RelateToKey) of
        [] ->
            ok;
        [Relation|_] ->
            Related = [Key | Relation#?MXRELATION.related],
            UpdatedRelation = Relation#?MXRELATION{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedRelation) end),
            ok
    end.

remove_relations(Relations) ->
    ?DBG("REMOVE RELATIONS: ~p", [Relations]),
    lists:foldl(
        fun(<<$*,_/binary>> = RelationKey, _) ->
            % client relation
            [Client|_]      = mnesia:dirty_read(?MXCLIENT, RelationKey),
            Related         = lists:delete(RelationKey, Client#?MXCLIENT.related),
            UpdatedClient   = Client#?MXCLIENT{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end),
            ok;

           (<<$#,_/binary>> = RelationKey, _) ->
           % channel relation
            [Channel|_]      = mnesia:dirty_read(?MXCHANNEL, RelationKey),
            Related          = lists:delete(RelationKey, Channel#?MXCHANNEL.related),
            UpdatedChannel   = Channel#?MXCHANNEL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok;

            (<<$@,_/binary>> = RelationKey, _) ->
           % pool relation
            [Channel|_]      = mnesia:dirty_read(?MXCHANNEL, RelationKey),
            Related          = lists:delete(RelationKey, Channel#?MXCHANNEL.related),
            UpdatedChannel   = Channel#?MXCHANNEL{related = Related},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok
    end, ok, Relations).

remove_owning(Owners) ->
    lists:foldl(fun(Key, _) ->
                [Client|_] = mnesia:dirty_read(?MXCLIENT, Key),
                ClientOwnerOf = lists:delete(Key, Client#?MXCLIENT.ownerof),
                UpdatedClient = Client#?MXCLIENT{ownerof = ClientOwnerOf},
                mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end),
                ok
            end, ok, Owners).

abandon(<<$@,_/binary>> = PoolKey, Client) when is_record(Client, ?MXCLIENT) ->
    ?ERR("unimplemented abandon pool function"),
    ok;

abandon(<<$#,_/binary>> = ChannelKey, Client) when is_record(Client, ?MXCLIENT) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            ok;
        [Channel|_] ->
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
        {empty, Q1} ->
            {Q1, HasMessages};
        {{value, {_, {To, Message}}}, Q1} when is_record(To, ?MXCLIENT) ->
            ?DBG("Dispatch to the client: ~p [MESSAGE: ~p]", [To, Message]),

            dispatch(Q1, N - 1, true);
        {{value, {_, {To, Message}}}, Q1} when is_record(To, ?MXCHANNEL) ->
            ?DBG("Dispatch to channel subscribers: ~p [MESSAGE: ~p]", [To, Message]),

            dispatch(Q1, N - 1, true);

        {{value, {_, {To, Message}}}, Q1} when is_record(To, ?MXPOOL) ->
            ?DBG("Dispatch to the pool: ~p [MESSAGE: ~p]", [To, Message]),

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
                        HasMessagesAcc
                end
            end, false, lists:seq(1, 10)) of
        true ->
            ?DBG("Queue have messages... cast 'dispatch' immediately"),
            0; % cast 'dispatch' immediately
        false ->
            ?DBG("Wait for new message..."),
            5000 % FIXME later. wait 50 ms before 'dispatch casting'
    end.


defer(Priority, To, Message) ->
    Defer = #?MXDEFER{
        to          = To,
        message     = Message,
        priority    = case Priority =:= 1 of
                        true -> Priority;
                        false -> Priority
                      end
    },
    mnesia:transaction(fun() -> mnesia:write(Defer) end).


