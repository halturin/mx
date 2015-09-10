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
%%
%% 1. Брокер работает на gproc. В качестве хранилища используется Mnesia. Лидер кластера испльзует
%%    модель disk_copy, остальные - ram_copy. Перевыборы лидера должны происходить раз в сутки (час?).
%%    После переизбрания новый лидер должен перейти на модель disk_copy. Алгоритм выбора лидера - очередь.
%%
%% 2. Структура брокера
%%    Брокер не работает с конечными отправителями и получателями. Он работает с бекэндами, которые
%%    работаеют непосредственно на последней миле. В случае платформы - последние мили обслуживают
%%    horn (websocket, email, sms) и synapse(llp/llsn)
%%
%% 3. Клиенты (отправители/получатели) хранятся в Mnesia. Управление оными произходит через соответствующий
%%    API брокера
%%         mx:client(MX, register, Client)
%%         mx:client(MX, set, ClientKey, Opts)
%%         mx:client(MX, unregister, ClientKey)
%%         mx:client(MX, info, Client)
%%         mx:client(MX, subscribe, ClientKey, ChannelName)
%%         mx:client(MX, unsubscribe, ClientKey, ChannelName)
%%         mx:client(MX, join, ClientKey, PoolName)
%%         mx:client(MX, leave, ClientKey, PoolName)
%%
%%         mx:channel(MX, register, ChannelName, Client) - returns ChannelKey
%%         mx:channel(MX, set, ChannelKey, Opts) - set options for the Channel ('skip offline': true/false. sms/email aren't required the receiver being online state)
%%         mx:channel(MX, unregister, ChannelKey)
%%         mx:channel(MX, info, ChannelName)
%%
%%
%%         mx:pool(MX, register, PoolName, Client) - return PoolKey
%%         mx:pool(MX, set, PoolKey, Opts) - set options for the Pool
%%         mx:pool(MX, unregister, PoolKey)
%%         mx:pool(MX, info, PoolName)
%%
%%         mx:send(MX, ClientKey, ClientTo, Message) - unicast message
%%             returns: ok
%%                      offline - client is offline
%%                      unknown - client is not registered
%%
%%         mx:send(MX, ChannelKey, Message) - muilticast
%%             returns: ok
%%                      nobody  - channel has no subscribers
%%                      offline - backend are served this channel is off.
%%                      unknown - channel is not registered
%%
%%         mx:send(MX, PoolKey, Message) - pooled unicast message
%%             returns: ok
%%
%%                      offline - all the clients are offlined.
%%                      unknown - pool is not registered
%%
%%         mx:control(MX, ControlKey, Cmd)

%%      Ключ для Client/Channel - это бинарный md5 + префикс
%%          ClientKey  = <<$*, ClientHash/binary>>
%%          ChannelKey = <<$#, ChannelHash/binary>>
%%          PoolKey    = <<$@, PoolHash/binary>>

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
         client/3,
         channel/2,
         channel/3,
         pool/2,
         pool/3,
         send/2,
         control/2
        ]).

%% records
-record(state, {config :: list()}).

%% includes
-include_lib("include/log.hrl").
-include_lib("include/mx.hrl").

%%% API
%%%===================================================================
client(register, Client) when is_integer(Client)->
    client(register, integer_to_binary(Client));

client(register, Client) when is_list(Client)->
    client(register, list_to_binary(Client));

client(register, Client) when is_binary(Client)->
    call({register_client, Client});

client(unregister, <<$*,_/binary>> = ClientKey) ->
    call({unregister_client, ClientKey});

client(info, <<$*, _/binary>> = ClientKey) ->
    call({info_client, ClientKey}).

client(set, <<$*, _/binary>> = ClientKey, Opts) ->
    ok;

% for channels
client(subscribe, <<$*, _/binary>> = ClientKey, ChannelName) when is_list(ChannelName)->
    client(subscribe, ClientKey, list_to_binary(ChannelName));
client(subscribe, <<$*, _/binary>> = ClientKey, ChannelName) ->
    call({subscribe, ClientKey, ChannelName});

client(unsubscribe, <<$*, _/binary>> = ClientKey, ChannelName) when is_list(ChannelName)->
    client(unsubscribe, ClientKey, list_to_binary(ChannelName));
client(unsubscribe, <<$*, _/binary>> = ClientKey, ChannelName) when is_binary(ChannelName)->
    call({unsubscribe, ClientKey, ChannelName});

% for pools
client(join, ClientKey, PoolName) ->
    ok;

client(leave, ClientKey, PoolName) ->
    ok.


channel(register, {ChannelName, Opts}, ClientKey) when is_list(ChannelName) ->
    channel(register, {list_to_binary(ChannelName), Opts}, ClientKey);
channel(register, ChannelName, ClientKey) when is_list(ChannelName) ->
    channel(register, {list_to_binary(ChannelName),[]}, ClientKey);
channel(register, {ChannelName, Opts}, ClientKey) when is_binary(ChannelName)->
    call({register_channel, {ChannelName, Opts}, ClientKey});
channel(register, ChannelName, ClientKey) when is_binary(ChannelName)->
    call({register_channel, ChannelName, ClientKey});

channel(set, ChannelKey, Opts) ->
    ok.

channel(unregister, <<$#,_/binary>> = ChannelKey) ->
    call({unregister_channel, ChannelKey});

channel(info, <<$#,_/binary>> = ChannelKey) ->
    call({info_channel, ChannelKey}).


pool(register, PoolName, Client) ->
    ok;

pool(set, PoolKey, Opts) ->
    ok.

pool(unregister, PoolKey) ->
    ok;

pool(info, PoolName) ->
    ok.


send(<<$*, _/binary>> = ClientKeyTo, Message) ->
    case mnesia:dirty_read(mx_table_client, ClientKeyTo) of
        [] ->
            unknown_client;
        [ClientTo|_] ->
            cast({send, ClientTo, Message})
    end;

send(<<$#, _/binary>> = ChannelKeyTo, Message) ->
    case mnesia:dirty_read(mx_table_channel, ChannelKeyTo) of
        [] ->
            unknown_channel;
        [ChannelTo|_] ->
            cast({send, ChannelTo, Message})
    end;

send(<<$@, _/binary>> = PoolKeyTo, Message) ->
    case mnesia:dirty_read(mx_table_pool, PoolKeyTo) of
        [] ->
            unknown_pool;
        [PoolTo|_] ->
            cast({send, PoolTo, Message})
    end.


control(ControlKey, Cmd) ->
    ok.

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
