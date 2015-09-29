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

-module(mx_broker_sup).

-behaviour(supervisor).

-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).


-define(CHILD(I, Type, Args), {{N,I}, {N, start_link, [Args]}, permanent, 5000, Type, [N]}).

%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%% Supervisor callbacks
%% ===================================================================

init([]) ->
    % {ok, Opts}      = application:get_env(mx, broker),
    Opts            = [],
    Workers         = erlang:system_info(schedulers),
    gproc_pool:new(mx_pubsub, round_robin, [{size, Workers}]),

    Children = lists:map(
        fun(I) ->
            Worker = {mx_broker, I},
            gproc_pool:add_worker(mx_pubsub, Worker, I),
            {Worker, {mx_broker, start_link, [I, Opts]},
                        permanent, 5000, worker, [mx_broker]}
        end, lists:seq(1, Workers)),

    {ok, { {one_for_one, 5, 10}, Children } }.

