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
%%% API
%%%===================================================================
%%      register(client, Name),
%%      register(client, Name, Opts),
%%          Name - list or binary
%%          Opts - proplists
%%          returns: {clientkey, Key}
%%                   {duplicate, Key}
%%               Key - binary
%%
%%      register(channel, Name, ClientKey)
%%      register(channel, Name, ClientKey, Opts)
%%          Name - list or binary
%%          Opts - proplists
%%          ClientKey - binary
%%          returns: {channelkey, Key}
%%                   {duplicate, Key}
%%
%%      register(pool, Name, ClientKey)
%%      register(pool, Name, ClientKey, Opts)
%%          Name - list or binary
%%          Opts - proplists
%%          ClientKey - binary
%%          returns: {poolkey, Key}
%%                   {duplicate, Key}
%%
%%      subscribe(Key, Channel)
%%      unsubscribe(Key, Channel)
%%          Key - binary (ClientKey, ChannelKey, PoolKey)
%%          Channel - channel name or channel key
%%
%%      join(Key, Pool)
%%      leave(key, Pool)
%%          Key - binary (ClientKey, ChannelKey, PoolKey)
%%          Pool - pool name or pool key
%%
%%      set(Key, Opts)
%%          Key - binary (ClientKey, ChannelKey, PoolKey)
%%          Opts - proplists
%%
%%      info(Key)
%%          Key - binary (ClientKey, ChannelKey, PoolKey)
%%
%%      mx:send(ClientKey, Message)    - unicast message
%%      mx:send(ChannelKey, Message)   - muilticast
%%      mx:send(PoolKey, Message)      - pooled unicast message
%%
%%      Naming keys: prefix + md5(Name)
%%              ClientKey  = <<$*, ClientHash/binary>>
%%              ChannelKey = <<$#, ChannelHash/binary>>
%%              PoolKey    = <<$@, PoolHash/binary>>

-module(mx).

-behaviour(gen_server).

-compile({no_auto_import,[register/2]}).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([register/2,
         register/3,
         register/4,
         unregister/1,
         subscribe/2,
         unsubscribe/2,
         join/2,
         leave/2,
         send/2,
         send/3,
         info/1,
         set/2
        ]).

%% records
-record(state, {config :: list()}).

%% includes
-include_lib("include/log.hrl").
-include_lib("include/mx.hrl").

register(client, Client, Opts) when is_binary(Client) ->
    call({register_client, Client, Opts});
register(X, Y, Opts) when is_list(Y) ->
    register(X, list_to_binary(Y), Opts);

register(channel, X, <<$*,_/binary>> = Y) ->
    register(channel, X, Y, []);
register(pool, X, <<$*,_/binary>> = Y) ->
    register(pool, X, Y, []).

register(channel, Channel, <<$*,_/binary>> = ClientKey, Opts) when is_binary(Channel) ->
    call({register_channel, Channel, ClientKey, Opts});
register(pool, Pool, <<$*,_/binary>> = ClientKey, Opts) when is_binary(Pool) ->
    call({register_pool, Pool, ClientKey, Opts});
register(X, Y, <<$*,_/binary>> = Z, Opts) when is_list(Y) ->
    register(X, list_to_binary(Y), Z, Opts).

register(client, X) ->
    register(client, X, []).


unregister(Key) ->
    call({unregister, Key}).

subscribe(Key, Channel) when is_list(Channel) ->
    ChannelHash = erlang:md5(list_to_binary(Channel)),
    subscribe(Key, <<$#, ChannelHash/binary>>);

subscribe(Key, <<$#, _/binary>> = ChannelKey) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            unknown_channel;
        [_Ch|_] ->
            call({relate, Key, ChannelKey})
    end;

subscribe(Key, Channel) when is_binary(Channel) ->
    ChannelHash = erlang:md5(Channel),
    subscribe(Key, <<$#, ChannelHash/binary>>).

unsubscribe(Key, Channel) when is_list(Channel) ->
    ChannelHash = erlang:md5(list_to_binary(Channel)),
    unsubscribe(Key, <<$#, ChannelHash/binary>>);

unsubscribe(Key, <<$#, _/binary>> = ChannelKey) ->
    case mnesia:dirty_read(?MXCHANNEL, ChannelKey) of
        [] ->
            unknown_channel;
        [_Ch|_] ->
            call({unrelate, Key, ChannelKey})
    end;

unsubscribe(Key, Channel) when is_binary(Channel) ->
    ChannelHash = erlang:md5(Channel),
    unsubscribe(Key, <<$#, ChannelHash/binary>>).


join(Key, Pool) when is_list(Pool) ->
    PoolHash = erlang:md5(list_to_binary(Pool)),
    join(Key, <<$@, PoolHash/binary>>);

join(Key, <<$@, _/binary>> = PoolKey) ->
    case mnesia:dirty_read(?MXPOOL, PoolKey) of
        [] ->
            unknown_pool;
        [_P|_] ->
            call({relate, Key, PoolKey})
    end;

join(Key, Pool) when is_binary(Pool) ->
    PoolHash = erlang:md5(Pool),
    join(Key, <<$@, PoolHash/binary>>).

leave(Key, Pool) when is_list(Pool) ->
    PoolHash = erlang:md5(list_to_binary(Pool)),
    leave(Key, <<$@, PoolHash/binary>>);

leave(Key, <<$@, _/binary>> = PoolKey) ->
    case mnesia:dirty_read(?MXPOOL, PoolKey) of
        [] ->
            unknown_pool;
        [_P|_] ->
            call({unrelate, Key, PoolKey})
    end;

leave(Key, Pool) when is_binary(Pool) ->
    PoolHash = erlang:md5(Pool),
    leave(Key, <<$@, PoolHash/binary>>).

info(Key) ->
    call({info, Key}).

set(Key, Opts) ->
    call({set, Key, Opts}).

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
handle_call({register_client, Client, Opts}, _From, State) ->
    R = register(client, Client, Opts),
    {reply, R, State};
handle_call({register_client, Client}, _From, State) ->
    R = register(client, Client),
    {reply, R, State};

handle_call({register_channel, ChannelName, ClientKey, Opts}, _From, State) ->
    R = register(channel, ChannelName, ClientKey, Opts),
    {reply, R, State};
handle_call({register_channel, ChannelName, ClientKey}, _From, State) ->
    R = register(channel, ChannelName, ClientKey),
    {reply, R, State};

handle_call({register_pool, PoolName, ClientKey, Opts}, _From, State) ->
    R = register(pool, PoolName, ClientKey, Opts),
    {reply, R, State};
handle_call({register_pool, PoolName, ClientKey}, _From, State) ->
    R = register(pool, PoolName, ClientKey),
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

handle_call({info, Key}, _From, State) ->
    R = info(Key),
    {reply, R, State};

handle_call({set, Key, Opts}, _From, State) ->
    R = set(Key, Opts),
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
