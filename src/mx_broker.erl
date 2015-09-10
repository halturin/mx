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
            queues       % list of queues ()
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
    % number of Queues is eq to the number of priorities
    Q = lists:map(fun(X) -> mx_queue:new(X) end, lists:seq(1, 10)),
    State = #state{
                id = I,
                config = [],
                queues = Q},
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
    C = #mx_table_client{
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
    ?INFO("ClientKey: ~p", [ClientKey]),
    case mnesia:dirty_read(mx_table_client, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client|_] ->
            [unsubscribe_client(Ch, Client) || Ch <- Client#mx_table_client.channels],
            [leave_client(P, Client) || P <- Client#mx_table_client.pools],
            [abandon(I, Client) || I <- Client#mx_table_client.ownerof],

            R = mnesia:transaction(fun() -> mnesia:delete({mx_table_client, ClientKey}) end),
            {reply, R, State}
    end;

handle_call({register_channel, {Channel, Opts}, ClientKey}, From, State) ->
    case mnesia:dirty_read(mx_table_client, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client|_] ->
            ChannelHash = erlang:md5(Channel),
            ChannelKey  = <<$#, ChannelHash/binary>>,
            Ch = #mx_table_channel{
                key         = ChannelKey,
                name        = Channel,
                owners      = [Client#mx_table_client.key],
                subscribers = [],
                handler     = From,
                length      = proplists:get_value(length, Opts, ?MXQUEUE_LENGTH_LIMIT),
                lt          = proplists:get_value(lt, Opts, ?MXQUEUE_LOW_THRESHOLD),
                ht          = proplists:get_value(ht, Opts, ?MXQUEUE_HIGH_THRESHOLD),
                priority    = proplists:get_value(priority, Opts, ?MXQUEUE_PRIO_NORMAL),
                defer       = proplists:get_value(defer, Opts, true)
            },

            Trn =   fun() ->
                mnesia:write(Ch),
                Cl = Client#mx_table_client{ownerof = [ChannelKey| Client#mx_table_client.ownerof]},
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
    case mnesia:dirty_read(mx_table_channel, ChannelKey) of
        [] ->
            {reply, unknown_channel , State};
        [Channel|_] ->
            % remove subscriptions
            lists:map(fun(ClientKey) ->
                mnesia:dirty_read(mx_table_client, ClientKey),
                ClientChannels = lists:delete(ChannelKey, Channel#mx_table_client.channels),
                UpdatedClient = Channel#mx_table_client{channels = ClientChannels},
                mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end)
            end, Channel#mx_table_channel.subscribers),
            % remove owning
            lists:map(fun(ClientKey) ->
                [Client|_] = mnesia:dirty_read(mx_table_client, ClientKey),
                ClientOwnerOf = lists:delete(ChannelKey, Client#mx_table_client.ownerof),
                UpdatedClient = Client#mx_table_client{ownerof = ClientOwnerOf},
                mnesia:transaction(fun() -> mnesia:write(UpdatedClient) end)
            end, Channel#mx_table_channel.owners),
            % remove channel itself
            mnesia:transaction(fun() -> mnesia:delete({mx_table_channel, ChannelKey}) end),
            {reply, ok , State}
    end;


handle_call({subscribe, ClientKey, ChanneName}, _From, State) ->
    {reply, ok, State};

handle_call({unsubscribe, ClientKey, ChanneName}, _From, State) ->
    {reply, ok, State};


handle_call({info_client, ClientKey}, _From, State) ->
    ?LOG("Broker: ~p", [State#state.id]),
    case mnesia:dirty_read(mx_table_client, ClientKey) of
        [] ->
            {reply, unknown_client, State};
        [Client|_] ->
            {reply, Client, State}
    end;

handle_call({info_channel, ChannelKey}, _From, State) ->
    ?LOG("Broker: ~p", [State#state.id]),
    case mnesia:dirty_read(mx_table_channel, ChannelKey) of
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
unsubscribe_client(ChannelKey, Client) when is_record(Client, mx_table_client) ->
    case mnesia:dirty_read(mx_table_channel, ChannelKey) of
        [] ->
            ok;
        [Channel|_] ->
            Subs = lists:delete(Client#mx_table_client.key, Channel#mx_table_channel.subscribers),
            UpdatedChannel = Channel#mx_table_channel{subscribers = Subs},
            mnesia:transaction(fun() -> mnesia:write(UpdatedChannel) end),
            ok
    end.

leave_client(PoolKey, Client) when is_record(Client, mx_table_client) ->
    ?ERR("unimplemented leave_client function"),
    ok.

abandon(<<$@,_/binary>> = PoolKey, Client) when is_record(Client, mx_table_client) ->
    ?ERR("unimplemented abandon pool function"),
    ok;

abandon(<<$#,_/binary>> = ChannelKey, Client) when is_record(Client, mx_table_client) ->
    case mnesia:dirty_read(mx_table_channel, ChannelKey) of
        [] ->
            ok;
        [Channel|_] ->
            case lists:delete(Client#mx_table_client.key, Channel#mx_table_channel.owners) of
                [] ->
                    mnesia:transaction(fun() -> mnesia:delete({mx_table_channel, ChannelKey}) end),
                    ok;
                Owners ->
                    UpdatedChannel = Channel#mx_table_channel{owners = Owners},
                    mnesia:transaction(fun() ->mnesia:write(UpdatedChannel) end),
                    ok
            end
    end.
