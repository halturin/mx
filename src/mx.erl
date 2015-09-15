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
%%         mx:client(register, Client)
%%         mx:client(set, ClientKey, Opts)
%%         mx:client(unregister, ClientKey)
%%         mx:client(info, ClientKey)
%%         mx:client(subscribe, ClientKey, ChannelName)
%%         mx:client(unsubscribe, ClientKey, ChannelName)
%%         mx:client(join, ClientKey, PoolName)
%%         mx:client(leave, ClientKey, PoolName)
%%
%%         mx:channel(register, ChannelName, ClientKey) - returns ChannelKey
%%         mx:channel(set, ChannelKey, Opts)
%%         mx:channel(unregister, ChannelKey)
%%         mx:channel(info, ChannelKey)
%%
%%
%%         mx:pool(register, PoolName, ClientKey) - return PoolKey
%%         mx:pool(set, PoolKey, Opts) - set options for the Pool
%%         mx:pool(unregister, PoolKey)
%%         mx:pool(info, PoolKey)
%%
%%         mx:send(ClientKey, ClientTo, Message)    - unicast message
%%         mx:send(ChannelKey, Message)             - muilticast
%%         mx:send(PoolKey, Message)                - pooled unicast message
%%
%%         Prefixes:
%%              ClientKey  = <<$*, ClientHash/binary>>
%%              ChannelKey = <<$#, ChannelHash/binary>>
%%              PoolKey    = <<$@, PoolHash/binary>>

-module(mx).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([client/2,
         channel/2,
         channel/3,
         pool/2,
         pool/3,
         send/2,
         send/3
        ]).

%% records
-record(state, {config :: list()}).

%% includes
-include_lib("include/log.hrl").
-include_lib("include/mx.hrl").

%%% API
%%%===================================================================
client(register, {Client, Opts}) when is_list(Client)->
    client(register, {list_to_binary(Client), Opts});
client(register, {Client, Opts}) when is_binary(Client)->
    call({register_client, Client, Opts});
client(register, Client) ->
    client(register, {Client, []});

client(set, {<<$*, _/binary>> = ClientKey, Opts}) ->
    {fixme, ClientKey, Opts};

client(unregister, <<$*,_/binary>> = ClientKey) ->
    call({unregister, ClientKey});

client(info, <<$*, _/binary>> = ClientKey) ->
    call({info_client, ClientKey}).



channel(register, {ChannelName, Opts}, <<$*, _/binary>> = ClientKey) when is_list(ChannelName) ->
    channel(register, {list_to_binary(ChannelName), Opts}, ClientKey);
channel(register, {ChannelName, Opts}, <<$*, _/binary>> = ClientKey) when is_binary(ChannelName) ->
    call({register_channel, {ChannelName, Opts}, ClientKey});
channel(register, ChannelName, <<$*, _/binary>> = ClientKey) ->
    call({register_channel, {ChannelName,[]}, ClientKey});

channel(set, ChannelKey, Opts) ->
    {fixme, ChannelKey, Opts}.

channel(unregister, <<$#,_/binary>> = ChannelKey) ->
    call({unregister, ChannelKey});

channel(info, <<$#,_/binary>> = ChannelKey) ->
    call({info_channel, ChannelKey}).

pool(register, {PoolName, Opts}, <<$*, _/binary>> = ClientKey) when is_list(PoolName) ->
    pool(register, {list_to_binary(PoolName), Opts}, ClientKey);
pool(register, PoolName, <<$*, _/binary>> = ClientKey) when is_list(PoolName) ->
    pool(register, {list_to_binary(PoolName), []}, ClientKey);
pool(register, {PoolName, Opts}, <<$*, _/binary>> = ClientKey) when is_binary(PoolName) ->
    call({register_pool, {PoolName, Opts}, ClientKey});
pool(register, PoolName, <<$*, _/binary>> = ClientKey) when is_binary(PoolName) ->
    call({register_pool, {PoolName,[]}, ClientKey});


pool(set, PoolKey, Opts) ->
    {fixme, PoolKey, Opts}.

pool(unregister, <<$@,_/binary>> = PoolKey) ->
    call({unregister, PoolKey});

pool(info, <<$@, _/binary>> = PoolKey) ->
    call({info_pool, PoolKey}).

subscribe(Key, To) when is_list(To) ->
    ToHash = erlang:md5(list_to_binary(To)),
    subscribe(Key, <<$#, ToHash/binary>>);

subscribe(Key, <<$#, _/binary>> = To) ->
    case mnesia:dirty_read(?MXCHANNEL, To) of
        [] ->
            unknown_channel;
        [Channel|_] ->
            action(subscribe, Key, Channel)
    end.

unsubscribe(Key, From) when is_list(From) ->
    FromHash = erlang:md5(list_to_binary(From)),
    subscribe(Key, <<$#, FromHash/binary>>);

unsubscribe(Key, <<$#, _/binary>> = From) ->
    case mnesia:dirty_read(?MXCHANNEL, From) of
        [] ->
            unknown_channel;
        [Channel|_] ->
            action(unsubscribe, Key, Channel)
    end.

join(Key, To) when is_list(To) ->
    ToHash = erlang:md5(list_to_binary(To)),
    join(Key, <<$@, ToHash/binary>>);

join(Key, <<$@, _/binary>> = To) ->
    case mnesia:dirty_read(?MXPOOL, To) of
        [] ->
            unknown_pool;
        [Pool|_] ->
            action(join, Key, Pool)
    end.

leave(Key, From) when is_list(From) ->
    FromHash = erlang:md5(list_to_binary(From)),
    leave(Key, <<$@, FromHash/binary>>);
leave(Key, <<$@, _/binary>> = From) ->
    case mnesia:dirty_read(?MXPOOL, From) of
        [] ->
            unknown_pool;
        [Pool|_] ->
            action(leave, Key, Pool)
    end.

send(To, Message) ->
    send(To, Message, []).

send(<<$*, _/binary>> = ClientKeyTo, Message, Opts) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKeyTo) of
        [] ->
            unknown_client;
        [ClientTo|_] ->
            cast({send, ClientTo, Message, Opts})
    end;

send(<<$#, _/binary>> = ChannelKeyTo, Message, Opts) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKeyTo) of
        [] ->
            unknown_channel;
        [ChannelTo|_] ->
            cast({send, ChannelTo, Message, Opts})
    end;

send(<<$@, _/binary>> = PoolKeyTo, Message, Opts) ->
    case mnesia:dirty_read(?MXPOOL, PoolKeyTo) of
        [] ->
            unknown_pool;
        [PoolTo|_] ->
            cast({send, PoolTo, Message, Opts})
    end;

send(_, _, _) ->
    unknown_receiver.

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
    ok = wait_for_mnesia(5000), % wait for mnesia 5 sec
    erlang:send_after(0, self(), {'$gen_cast', requeue}),
    {ok, #state{config = []}}.

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
handle_call({register_client, {Client, Opts}}, _From, State) ->
    R = client(register, {Client, Opts}),
    {reply, R, State};
handle_call({register_client, Client}, _From, State) ->
    R = client(register, Client),
    {reply, R, State};

handle_call({register_channel, {ChannelName, Opts}, ClientKey}, _From, State) ->
    R = channel(register, {ChannelName, Opts}, ClientKey),
    {reply, R, State};
handle_call({register_channel, ChannelName, ClientKey}, _From, State) ->
    R = channel(register, ChannelName, ClientKey),
    {reply, R, State};

handle_call({register_pool, {PoolName, Opts}, ClientKey}, _From, State) ->
    R = pool(register, {PoolName, Opts}, ClientKey),
    {reply, R, State};
handle_call({register_pool, PoolName, ClientKey}, _From, State) ->
    R = pool(register, PoolName, ClientKey),
    {reply, R, State};

handle_call({unregister, Key}, _From, State) ->
    R = call({unregister, Key}),
    {reply, R, State};

handle_call({subscribe, Client, To}, _From, State) ->
    R = subscribe(Client, To),
    {reply, R, State};

handle_call({unsubscribe, Client, From}, _From, State) ->
    R = unsubscribe(Client, From),
    {reply, R, State};

handle_call({join, Client, To}, _From, State) ->
    R = join(Client, To),
    {reply, R, State};

handle_call({leave, Client, From}, _From, State) ->
    R = leave(Client, From),
    {reply, R, State};

handle_call(nodes, _From, State) ->
    R = mx_mnesia:nodes(),
    {reply, R, State};

handle_call({send, To, Message}, _From, State) ->
    R = send(To, Message, []),
    {reply, R, State};

handle_call({send, To, Message, Opts}, _From, State) ->
    R = send(To, Message, Opts),
    {reply, R, State};

handle_call(Request, _From, State) ->
    ?ERR("unhandled call: ~p", [Request]),
    {reply, unknown_request, State}.
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
handle_cast(requeue, State) ->
    Timeout = requeue(),
    erlang:send_after(Timeout, self(), {'$gen_cast', requeue}),
    {noreply, State};

handle_cast(Message, State) ->
    ?ERR("unhandled cast: ~p", [Message]),
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
wait_for_mnesia(T) when T > 0 ->
    case gen_server:call(mx_mnesia, status) of
        running ->
            ok;
        X ->
            ?ERR("waiting ~p~n", [X]),
            timer:sleep(100),
            wait_for_mnesia(T - 100)
    end;

wait_for_mnesia(_T) ->
    timeout.

call(M) ->
    case gproc_pool:pick_worker(mx_pubsub) of
        false ->
            broker_unavailable;
        Pid ->
            gen_server:call(Pid, M)
    end.

cast(M) ->
    case gproc_pool:pick_worker(mx_pubsub) of
        false ->
            broker_unavailable;
        Pid ->
            gen_server:cast(Pid, M)
    end.

requeue(_, 0, HasDeferred) ->
    HasDeferred;
requeue(P, N, HasDeferred) ->
    % case mnesia:wread({?MXDEFER, }) of
    % end,
    % send(To, Message, [{priority, P}]),

    % mx_queue:len(Q)
    requeue(P, N - 1, HasDeferred).


requeue() ->
        case    lists:foldl(fun(P, HasDeferredAcc) ->
                    case requeue(P, 11 - P, false) of
                        true  ->
                            true;
                        false ->
                            HasDeferredAcc
                    end
                end, false, lists:seq(1, 10)) of
        true ->
            ?DBG("Queue have messages... cast 'dispatch' immediately"),
            0; % cast 'dispatch' immediately
        false ->
            ?DBG("Wait for deferred message..."),
            5000 % FIXME later. wait 50 ms before 'dispatch requeue'
    end.


    % модель такая же как и выборка из очереди. выгребаем 10 штук 1го приоритета... 1 шт 10го.
    % если еще есть данные, то возвращаем 0 для таймера cast.
    % еще надо учесть загруженность очередей, ежели они в перегрузке (>high_threshold) то пропускать.
    % lists:map(fun(M) ->
    % mnesia:wread({?MXDEFER, })

action(Action, <<$*, _/binary>> = ClientKey, Channel) ->
    case mnesia:dirty_read(?MXCLIENT, ClientKey) of
        [] ->
            unknown_client;
        [Client|_] ->
            call({Action, Client, Channel})
    end;

action(Action, <<$#, _/binary>> = ChannelKey, Channel) ->
    case mnesia:dirty_read(?MXCLIENT, ChannelKey) of
        [] ->
            unknown_channel_client;
        [ChannelClient|_] ->
            call({Action, ChannelClient, Channel})
    end;

action(Action, <<$@, _/binary>> = PoolKey, Channel) ->
    case mnesia:dirty_read(?MXPOOL, PoolKey) of
        [] ->
            unknown_pool;
        [Pool|_] ->
            call({Action, Pool, Channel})
    end.
