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

-module(mx).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([client/3,
         client/4,
         channel/3,
         channel/4,
         pool/3,
         pool/4,
         send/3,
         send/4,
         control/3
        ]).

%% records
-record(state, {config :: list()}).

%% includes
-include_lib("include/log.hrl").

%%% API
%%%===================================================================

client(MX, register, Client) ->
    ok;

client(MX, unregister, ClientKey) ->
    ok;

client(MX, info, Client) ->
    ok.

client(MX, set, ClientKey, Opts) ->
    ok;

client(MX, subscribe, ClientKey, ChannelName) ->
    ok;

client(MX, unsubscribe, ClientKey, ChannelName) ->
    ok;

client(MX, join, ClientKey, PoolName) ->
    ok;

client(MX, leave, ClientKey, PoolName) ->
    ok.


channel(MX, register, ChannelName, Client) ->
    ok;

channel(MX, set, ChannelKey, Opts) ->
    ok.

channel(MX, unregister, ChannelKey) ->
    ok;

channel(MX, info, ChannelName) ->
    ok.
        

pool(MX, register, PoolName, Client) ->
    ok;

pool(MX, set, PoolKey, Opts) ->
    ok.

pool(MX, unregister, PoolKey) ->
    ok;

pool(MX, info, PoolName) ->
    ok.


send(MX, ClientKey, ClientTo, Message) ->
    ok.

send(MX, ChannelKey, Message) ->
    ok;

send(MX, PoolKey, Message) -> 
    ok.


control(MX, ControlKey, Cmd) ->
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
