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

-ifndef(MX_HRL).
-define(MX_HRL, true).

% queue limits
-define(MXQUEUE_LENGTH_LIMIT,       10).
-define(MXQUEUE_LOW_THRESHOLD,      trunc(?MXQUEUE_LENGTH_LIMIT * 0.6)). % 60%
-define(MXQUEUE_HIGH_THRESHOLD,     trunc(?MXQUEUE_LENGTH_LIMIT * 0.8)). % 80%


-define(MXQUEUE_PRIO_SRT,           1). % soft realtime
-define(MXQUEUE_PRIO_NORMAL,        5).
-define(MXQUEUE_PRIO_LOW,           10).

-define(MXCLIENT,                   mx_table_client).
-define(MXCHANNEL,                  mx_table_channel).
-define(MXPOOL,                     mx_table_pool).
-define(MXDEFER,                    mx_table_defer).
-define(MXRELATIONS,                mx_table_relations).

-define(MXTABLES,
    [{?MXCLIENT, [{type, set},
                        {disc_copies, [node()]},
                        {record_name, ?MXCLIENT},
                        {attributes, record_info(fields, ?MXCLIENT)} ]},

    {?MXCHANNEL,[{type, set},
                        {disc_copies, [node()]},
                        {record_name, ?MXCHANNEL},
                        {attributes, record_info(fields, ?MXCHANNEL)} ]},

    {?MXPOOL,[{type, set},
                        {disc_copies, [node()]},
                        {record_name, ?MXPOOL},
                        {attributes, record_info(fields, ?MXPOOL)} ]},

    {?MXRELATIONS,[{type, set},
                        {disc_copies, [node()]},
                        {record_name, ?MXRELATIONS},
                        {attributes, record_info(fields, ?MXRELATIONS)} ]},

    {?MXDEFER, [{type, bag},
                        {disc_copies, [node()]},
                        {record_name, ?MXDEFER},
                        {attributes, record_info(fields, ?MXDEFER)} ]} ]).

-record(?MXCLIENT, {
    key         :: binary(),
    name        :: binary(),
    related     :: list(),              % subscribed/joined to
    ownerof     :: list(),              % list of keys (channels, pools)
    handler     :: pid() | offline,     % who manage the client (for recieving messages)
    comment     = "Client info" :: list()
    }).

-record(?MXCHANNEL, {
    key         :: binary(),
    name        :: binary(),
    related     :: list(),              % in case of tree-like subscriptions (example: pool of channels)
    owners      :: list(),              % owners (who can publish here)
    handler     :: pid(),               % who manage the last mile to the client (WebSocket, email, sms etc.)
    priority    = 5 :: non_neg_integer(),   % priority
    defer       = true :: boolean(),        % deferrable
    comment     = "Channel info" :: list()
    }).

-record(?MXPOOL, {
    key         :: binary(),
    name        :: binary(),
    related     :: list(),              % in case of tree-like pooling (example: channel of pools)
    owners      :: list(),
    balance     :: rr | hash | random,      % balance type
    priority    = 5 :: non_neg_integer(),
    defer       = true :: boolean(),        % deferrable
    comment     = "Pool info" :: list()
    }).

-record(?MXRELATIONS, {
    key         :: binary(),                % key of channel|pool
    related     :: list()                   % list of clients|pools|channels
    }).

-record(?MXDEFER, {
    to          :: binary(),
    message,
    priority    :: non_neg_integer(),
    fails       = 0 :: non_neg_integer()    % count of sending fails
    }).

-endif. % MX_HRL
