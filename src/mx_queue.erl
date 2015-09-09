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

-module(mx_queue).

-export([q/1, put/2, get/1, pop/1, channels/0]).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include_lib("include/mx.hrl").
-include_lib("include/log.hrl").

-record(mxq,{queue              = queue:new(),
             name,
             length             = 0 :: non_neg_integer(), %% current len
             length_limit       = ?MXQUEUE_LENGTH_LIMIT,
             threshold_low      = ?MXQUEUE_LOW_THRESHOLD,
             threshold_high     = ?MXQUEUE_HIGH_THRESHOLD,
             defer              = true :: boolean(),
             alarm}).
-type mxq() :: #mxq{}.
-export_type([mxq/0]).

-record(state, {status}).

% new queue (or update current)
q(ChannelKey) ->
    case mnesia:dirty_read(mx_table_channel, ChannelKey) of
        [] ->
            unknown_channel;
        [Channel|_] ->
            gen_server:call(?MODULE, {new, Channel})
    end.

put(Message, ChannelKey) ->
    gen_server:call(?MODULE, {put, Message, ChannelKey}).
get(ChannelKey) ->
    gen_server:call(?MODULE, {get, ChannelKey}).
pop(ChannelKey) ->
    gen_server:call(?MODULE, {pop, ChannelKey}).

% list of non empty channels
channels() ->
    gen_server:call(?MODULE, channels).


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
    ets:new(mx_table_queues, [named_table, ordered_set]),
    ets:new(mx_table_nonempty_queues, [named_table, ordered_set]),
    {ok, #state{status = starting}}.

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
handle_call({new, Channel}, _From, State) ->
    Q = case ets:lookup(mx_table_queues, Channel#mx_table_channel.key) of
        [] ->
            ?ERR("@@@@@@@Channel New queue"),
            #mxq{
                name            = Channel#mx_table_channel.key,
                length_limit    = Channel#mx_table_channel.length,
                threshold_low   = Channel#mx_table_channel.lt,
                threshold_high  = Channel#mx_table_channel.ht,
                defer           = Channel#mx_table_channel.defer,
                alarm           = alarm()
            };
        [{ChannelKey, Queue}|_] ->
            ?ERR("@@@@@@@Channel Update queue: ~p", [Queue]),
            Queue#mxq{
                length_limit    = Channel#mx_table_channel.length,
                threshold_low   = Channel#mx_table_channel.lt,
                threshold_high  = Channel#mx_table_channel.ht,
                defer           = Channel#mx_table_channel.defer,
                alarm           = alarm()
            }
    end,

    ets:insert(mx_table_queues, {Channel#mx_table_channel.key, Q}),
    {reply, ok, State};

handle_call({put, Message, ChannelKey}, _From, State) ->
    case ets:lookup(mx_table_queues, ChannelKey) of
        [] ->
            {reply, unknown_channel, State};
        [Queue] ->
            Q = mxq_put(Message, Queue#mxq.queue),
            ets:insert(mx_table_queues, {ChannelKey, Q}),
            {reply, ok, State}
    end;

handle_call({get, ChannelKey}, _From, State) ->
    case ets:lookup(mx_table_queues, ChannelKey) of
        [] ->
            {reply, unknown_channel, State};
        [Queue] when Queue#mxq.length > 0 ->
            {Message, Q} = mxq_get(Queue#mxq.queue),
            ets:insert(mx_table_queues, {ChannelKey, Q}),
            {reply, Message, State};
        _ ->
            {reply, empty, State}
    end;

handle_call({pop, ChannelKey}, _From, State) ->
    case ets:lookup(mx_table_queues, ChannelKey) of
        [] ->
            {reply, unknown_channel, State};
        [Queue] when Queue#mxq.length > 0 ->
            {Message, Q} = mxq_pop(Queue#mxq.queue),
            ets:insert(mx_table_queues, {ChannelKey, Q}),
            {reply, Message, State};
        _ ->
            {reply, empty, State}
    end;


handle_call(channels, _From, State) ->
    Channels = ets:foldl(fun(X) -> X end, [], mx_table_nonempty_queues),
    {reply, Channels, State};

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

mxq_put(_Message, #mxq{queue = Q, length = L, length_limit = LM, alarm = F} = MXQ) when L > LM ->
    % exceed the limit. drop message.
    % FIXME!!! save to the mnesia storage ('mx_table_defer' table) if defer option is set.
    MXQ#mxq{alarm   = F({alarm_queue_length_limit, Q})};

mxq_put(Message, #mxq{queue = Q, length = L, threshold_high = LH, alarm = F} = MXQ) when L > LH ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1,
            alarm   = F({alarm_threshold_high, Q})};

mxq_put(Message, #mxq{queue = Q, length = L, threshold_low = LL, alarm = F} = MXQ) when L > LL ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1,
            alarm   = F({alarm_threshold_low, Q})};

mxq_put(Message, #mxq{name = N, queue = Q, length = L, alarm = F} = MXQ) when L == 0 ->
    MXQ1 = MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1,
            alarm   = F({alarm_has_message, Q})},
    ets:insert(mx_table_nonempty_queues, N),
    MXQ1;

mxq_put(Message, #mxq{queue = Q, length = L} = MXQ) ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1}.


mxq_get(#mxq{name = N, length = L} = MXQ) when L == 0 ->
    ets:delete(mx_table_nonempty_queues, N),
    {empty, MXQ};

mxq_get(#mxq{queue = Q, length = L, alarm = F} = MXQ) ->
    {Message, Q1} = queue:out(Q),
    {Message, MXQ#mxq{
        queue   = Q1,
        length  = L - 1,
        alarm   = F({alarm_clear, Q})
        }}.

mxq_pop(#mxq{name = N, length = L} = MXQ) when L == 0 ->
    ets:delete(mx_table_nonempty_queues, N),
    {empty, MXQ};

mxq_pop(#mxq{queue = Q, length = L, alarm = F} = MXQ) ->
    {Message, Q1} = queue:out_r(Q),
    {Message, MXQ#mxq{
        queue   = Q1,
        length  = L - 1,
        alarm   = F({alarm_clear, Q})
        }}.

alarm() ->
    alarm(alarm_clear).
alarm(State) ->
    fun(Alarm, Q) when Alarm =:= State -> alarm(State);
       (Alarm, Q) when Alarm =/= State ->
            ?LOG("Warinig: ~p -> ~p", [State,Alarm]), alarm(Alarm)
    end.
