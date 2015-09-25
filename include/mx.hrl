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
-define(MXRELATION,                 mx_table_relation).
-define(MXKV,                       mx_table_kv).

-define(MXSYSTEM_CHANNEL,           <<35,1,205,204,237,249,21,234,116,63,125,148,219,82,19,237,212>>).
-define(MXSYSTEM_CLIENTS_CHANNEL,   <<35,218,100,92,158,250,171,65,140,165,196,6,41,174,67,121,214>>).
-define(MXSYSTEM_QUEUES_CHANNEL,    <<35,44,214,227,18,198,49,63,136,180,212,33,133,149,223,21,136>>).


-define(MX_SEND_TIMEOUT,            5000). % sync sending timeout

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

    {?MXRELATION,[{type, set},
                        {disc_copies, [node()]},
                        {record_name, ?MXRELATION},
                        {attributes, record_info(fields, ?MXRELATION)} ]},

    {?MXDEFER, [{type, bag},
                        {disc_copies, [node()]},
                        {record_name, ?MXDEFER},
                        {attributes, record_info(fields, ?MXDEFER)} ]},

    {?MXKV,[{type, set},
                        {disc_copies, [node()]},
                        {record_name, ?MXKV},
                        {attributes, record_info(fields, ?MXKV)} ]} ]).

-record(?MXCLIENT, {
    key         :: binary(),          % <<$*,Md5Hash/binary>> (<<42,...>>)
    name        :: binary(),
    related     :: list(),            % subscribed/joined to
    ownerof     :: list(),            % list of keys (channels, pools)
    handler     :: pid() | offline,   % who manage the client (for recieving messages)
    async       = true :: boolean(),  % send async or wait for 'ok' message
    defer       = false :: boolean(), % defer message when the handler is not available (offline)
    monitor     = false :: boolean(), % generate 'on/off' event message to the $system/$clients channel if its 'true'
    comment     = "Client info" :: list()
    }).

-record(?MXCHANNEL, {
    key         :: binary(),          % <<$#,Md5Hash/binary>> (<<35,...>>)
    name        :: binary(),
    related     :: list(),            % in case of tree-like subscriptions (example: pool of channels)
    owners      :: list(),            % owners (who can publish here)
    priority    = 5 :: non_neg_integer(),   % priority
    defer       = true :: boolean(),        % deferrable. defer message when exceed the queue limit
    comment     = "Channel info" :: list()
    }).

-record(?MXPOOL, {
    key         :: binary(),            % <<$@,Md5Hash/binary>> (<<64,...>>)
    name        :: binary(),
    related     :: list(),              % in case of tree-like pooling (example: channel of pools)
    owners      :: list(),
    balance     = rr :: rr | hash | random,      % balance type
    priority    = 5 :: non_neg_integer(),
    defer       = true :: boolean(),        % deferrable
    comment     = "Pool info" :: list()
    }).

-record(?MXRELATION, {
    key         :: binary(),                % key of channel|pool
    related     = [] :: list()                   % list of client|pool|channel keys
    }).

-record(?MXDEFER, {
    to          :: binary(),
    message,
    priority    :: non_neg_integer(),
    fails       = 0 :: non_neg_integer()    % count of sending fails
    }).

-record(?MXKV, {
    key,
    value
    }).

-endif. % MX_HRL
