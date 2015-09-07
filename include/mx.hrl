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


% queue limits
-define(MXQUEUE_LOW_THRESHOLD,      0.6).
-define(MXQUEUE_HIGH_THRESHOLD,     0.8).
-define(MXQUEUE_LENGTH_LIMIT,       20000).

-define(MXQUEUE_PRIO_NORMAL,        0).
-define(MXQUEUE_PRIO_HIGH,          5).
-define(MXQUEUE_PRIO_RT,            50).

-define(MXMNESIA_TABLES,           [{mx_table_client,[]}, {mx_table_channel,[]}, {mx_table_defer, []}]).

-record(mx_table_client, {
    name        :: binary(),
    key         :: binary(),
    channels    :: list(),
    handler     :: pid() | offline      % who manage the client (for recieving messages)
    }).

-record(mx_table_channel, {
    name        :: binary(),
    key         :: binary(),
    client,                             % owner. publisher
    subscribers :: list(),              % list of subscribed clients
    handler     :: pid(),               % who manage the last mile to the client (WebSocket, email, sms etc.)
    length      :: non_neg_integer(),   % max length of queue
    lt          :: non_neg_integer(),   % low threshold
    ht          :: non_neg_integer(),   % high threshold
    priority    :: non_neg_integer(),   % priority
    defer       :: boolean()            % deferrable
    }).

-record(mx_table_defer, {
    client,                             % message for direct sending to the client
    channel,                            % message for the subscribers
    message
    }).