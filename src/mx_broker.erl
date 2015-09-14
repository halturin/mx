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
init([I, Opts]) ->
    process_flag(trap_exit, true),
    gproc_pool:connect_worker(mx_pubsub, {mx_broker, I}),
    QueuesTable = list_to_atom("mx_broker_" ++ integer_to_list(I) ++ "_queues"),
    ets:new(QueuesTable, [named_table, ordered_set]),
    lists:map(fun(X) ->
        Q = mx_queue:new(X),
        ets:insert(QueuesTable,{X, Q})
    end, lists:seq(1, 10)),
    State = #state{
                id = I,
                config = [],
                queues = QueuesTable
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

handle_call({register_client, Client}, From, State) ->
    ClientHash  = erlang:md5(Client),
    ClientKey   = <<$*, ClientHash/binary>>,
    C = #?MXCLIENT{
            name     = Client,
            key      = ClientKey,
            channels = [],
            ownerof  = [],
            pools    = [],
            handler  = From
        },

    Trn =   fun() ->
                mnesia:write(C)
            end,

    case mnesia:transaction(Trn) of
        {aborted, E} ->
            {reply, E, State};
        _ ->
            {reply, {clientkey, ClientKey}, State}
    end;

handle_call({unregister_client, ClientKey}, _From, State) ->
    R = unregister_client(ClientKey),
    {reply, R, State};

handle_call({register_channel, {Channel, Opts}, ClientKey}, From, State) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client|_] ->
            ChannelHash = erlang:md5(Channel),
            ChannelKey  = <<$#, ChannelHash/binary>>,
            Ch = #?MXCHANNEL{
                key         = ChannelKey,
                name        = Channel,
                owners      = [Client#?MXCLIENT.key],
                subscribers = [],
                handler     = From,
                priority    = proplists:get_value(priority, Opts, ?MXQUEUE_PRIO_NORMAL),
                defer       = proplists:get_value(defer, Opts, true)
            },

            Trn =   fun() ->
                mnesia:write(Ch),
                Cl = Client#?MXCLIENT{ownerof = [ChannelKey| Client#?MXCLIENT.ownerof]},
                mnesia:write(Cl)
            end,

            case mnesia:transaction(Trn) of
                {aborted, E} ->
                    {reply, E, State};
                _ ->
                    {reply, {channelkey, ChannelKey}, State}
            end
    end;

handle_call({unregister_channel, ChannelKey}, From, State) ->
    R = unregister_channel(ChannelKey),
    {reply, R, State};


handle_call({subscribe, ClientKey, ChanneName}, _From, State) ->
    {reply, ok, State};

handle_call({unsubscribe, ClientKey, ChanneName}, _From, State) ->
    {reply, ok, State};


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
    % peering message priority is 1 (soft realtime)
    [{1,Q}|_] = ets:lookup(QueuesTable, 1),
    case mx_queue:put({Key, {To, Message}}, Q) of
        {defer, Q1} ->
            defer(1, Key, Message);
        Q1 ->
            pass
    end,
    ets:insert(QueuesTable, {1, Q1}),
    {noreply, State};

handle_cast({send, To, Message, Opts}, State) when is_record(To, ?MXCHANNEL) ->
    ?DBG("Send to channel: ~p", [To]),
    #state{queues = QueuesTable}    = State,
    #?MXCHANNEL{key = Key, priority = ChannelP} = To,
    P = proplists:get_value(priotiry, Opts, ChannelP),
    [{P,Q}|_] = ets:lookup(QueuesTable, P),
    case mx_queue:put({Key, {To, Message}}, Q) of
        {defer, Q1} when P == 1 ->
            defer(P, Key, Message);
        {defer, Q1} when P > 1 ->
            defer(P - 1, Key, Message);
        Q1 ->
            pass
    end,
    ets:insert(QueuesTable, {P, Q1}),
    {noreply, State};

handle_cast({send, To, Message, Opts}, State) when is_record(To, ?MXPOOL) ->
    ?DBG("Send to pool: ~p", [To]),
    #state{queues = QueuesTable}    = State,
    #?MXPOOL{key = Key, priority = PoolP} = To,
    P = proplists:get_value(priotiry, Opts, PoolP),
    [{P,Q}|_] = ets:lookup(QueuesTable, P),
    case mx_queue:put({Key, {To, Message}}, Q) of
        {defer, Q1} when P == 1 ->
            defer(P, Key, Message);
        {defer, Q1} when P > 1 ->
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
unregister_client(ClientKey) ->
        case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            unknown_client;
        [Client|_] ->
            [unsubscribe_client(Ch, Client) || Ch <- Client#?MXCLIENT.channels],
            [leave_client(P, Client) || P <- Client#?MXCLIENT.pools],
            [abandon(I, Client) || I <- Client#?MXCLIENT.ownerof],
            mnesia:transaction(fun() -> mnesia:delete({?MXCLIENT, ClientKey}) end),
            ok
    end.

unregister_channel(ChannelKey) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            unknown_channel;
        [Channel|_] ->
            % remove subscriptions
            lists:map(fun(ClientKey) ->
                mnesia:dirty_read(?MXCLIENT, ClientKey),
                ClientChannels = lists:delete(ChannelKey, Channel#?MXCLIENT.channels),
                UpdatedClient = Channel#?MXCLIENT{channels = ClientChannels},
                mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end)
            end, Channel#?MXCHANNEL.subscribers),
            % remove owning
            lists:map(fun(ClientKey) ->
                [Client|_] = mnesia:dirty_read(?MXCLIENT, ClientKey),
                ClientOwnerOf = lists:delete(ChannelKey, Client#?MXCLIENT.ownerof),
                UpdatedClient = Client#?MXCLIENT{ownerof = ClientOwnerOf},
                mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end)
            end, Channel#?MXCHANNEL.owners),
            % remove channel itself
            mnesia:transaction(fun() -> mnesia:delete({?MXCHANNEL, ChannelKey}) end),
            ok
    end.

unsubscribe_client(ChannelKey, Client) when is_record(Client, ?MXCLIENT) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            ok;
        [Channel|_] ->
            Subs = lists:delete(Client#?MXCLIENT.key, Channel#?MXCHANNEL.subscribers),
            UpdatedChannel = Channel#?MXCHANNEL{subscribers = Subs},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok
    end.

leave_client(PoolKey, Client) when is_record(Client, ?MXCLIENT) ->
    ?ERR("unimplemented leave_client function"),
    ok.

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
                    unregister_channel(ChannelKey);
                Owners ->
                    UpdatedChannel = Channel#?MXCHANNEL{owners = Owners},
                    mnesia:transaction(fun() ->mnesia:write(UpdatedChannel) end),
                    ok
            end
    end.

dispatch(Q, 0, HasMessages) ->
    {Q, HasMessages};
dispatch(Q, N, HasMessages) ->
    % если не можем доставить откладываем в defer с понижением приоритета + 3
    % defer(P + 3, To, Message)
    %
    case mx_queue:get(Q) of
        {empty, Q1} ->
            {Q1, HasMessages};
        {{value, {Key, {To, Message}}}, Q1} when is_record(To, ?MXCLIENT) ->
            ?DBG("Dispatch to the client: ~p [MESSAGE: ~p]", [To, Message]),

            dispatch(Q1, N - 1, true);
        {{value, {Key, {To, Message}}}, Q1} when is_record(To, ?MXCHANNEL) ->
            ?DBG("Dispatch to channel subscribers: ~p [MESSAGE: ~p]", [To, Message]),
            dispatch(Q1, N - 1, true);

        {{value, {Key, {To, Message}}}, Q1} when is_record(To, ?MXPOOL) ->
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
                    {Q1, false} ->
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


