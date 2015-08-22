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

% returns ChannelKey
channel(MX, register, ChannelName, Client) ->
    ok;
% set options for the Channel ('skip offline': true/false. sms/email aren't required 
% the receiver being online state)
channel(MX, set, ChannelKey, Opts) ->
    ok.
channel(MX, unregister, ChannelKey) ->
    ok;

channel(MX, info, ChannelName) ->
    ok.
        
% return PoolKey
pool(MX, register, PoolName, Client) ->
    ok;

% set options for the Pool
pool(MX, set, PoolKey, Opts) ->
    ok.

pool(MX, unregister, PoolKey) ->
    ok;
pool(MX, info, PoolName) ->
    ok.

% unicast message
% returns: ok
%          offline - client is offline
%          unknown - client is not registered
send(MX, ClientKey, ClientTo, Message) ->
    ok.

% muilticast 
% returns: ok
%          nobody  - channel has no subscribers
%          offline - backend are served this channel is off.
%          unknown - channel is not registered
send(MX, ChannelKey, Message) ->
    ok;
% pooled unicast message
% returns: ok
%          nobody            
%          offline - all the clients are offlined.
%          unknown - pool is not registered
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
