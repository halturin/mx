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

-export([new/1, put/2, get/1, pop/1, is_empty/1, len/1, total/1, name/1]).

%% includes
-include_lib("include/log.hrl").
-include_lib("include/mx.hrl").

-record(mxq,{queue              = queue:new(),
             name               :: non_neg_integer(),
             length             = 0 :: non_neg_integer(), %% current len
             length_limit       = ?MXQUEUE_LENGTH_LIMIT,
             threshold_low      = ?MXQUEUE_LOW_THRESHOLD,
             threshold_high     = ?MXQUEUE_HIGH_THRESHOLD,
             total              = 0, % total messages
             alarm}).

-type mxq() :: #mxq{}.
-export_type([mxq/0]).



new(QueueName) when is_integer(QueueName) ->
    #mxq{
        name            = QueueName,
        alarm           = alarm()
    };
new(_) ->
    {error, "non negative integer is expected"}.

put(_, #mxq{queue = Q, length = L, length_limit = LM, alarm = F} = MXQ) when L > LM ->
    {defer, MXQ#mxq{alarm   = F(mxq_alarm_queue_length_limit, Q)}};

put(Message, #mxq{queue = Q, length = L, threshold_high = LH, alarm = F} = MXQ) when L > LH ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1,
            alarm   = F(mxq_alarm_threshold_high, Q)};

put(Message, #mxq{queue = Q, length = L, threshold_low = LL, alarm = F} = MXQ) when L > LL ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1,
            alarm   = F(mxq_alarm_threshold_low, Q)};

put(Message, #mxq{queue = Q, length = L, alarm = F} = MXQ) when L == 0 ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1,
            alarm   = F(mxq_alarm_has_message, Q)};

put(Message, #mxq{queue = Q, length = L} = MXQ) ->
    MXQ#mxq{queue   = queue:in(Message, Q),
            length  = L + 1}.


get(#mxq{length = L} = MXQ) when L == 0 ->
    {empty, MXQ};

get(#mxq{queue = Q, length = L, alarm = F, total = T} = MXQ) ->
    {Message, Q1} = queue:out(Q),
    {Message, MXQ#mxq{
        queue   = Q1,
        length  = L - 1,
        alarm   = F(mxq_alarm_clear, Q),
        total   = T + 1
        }}.

pop(#mxq{length = L} = MXQ) when L == 0 ->
    {empty, MXQ};

pop(#mxq{queue = Q, length = L, alarm = F, total = T} = MXQ) ->
    {Message, Q1} = queue:out_r(Q),
    {Message, MXQ#mxq{
        queue   = Q1,
        length  = L - 1,
        total   = T + 1,
        alarm   = F(mxq_alarm_clear, Q)
        }}.

is_empty(#mxq{length = 0})  -> true;
is_empty(#mxq{length = _})  -> false.

len(#mxq{length = L})       -> L.
total(#mxq{total = T})      -> T.
name(#mxq{name = N})        -> N.

alarm() ->
    alarm(alarm_clear).
alarm(State) ->
    fun(Alarm, _) when Alarm =:= State -> alarm(State);
       (Alarm, _Q) when Alarm =/= State ->
            ?LOG("Warinig: ~p -> ~p", [State, Alarm]),
            alarm(Alarm)
    end.

