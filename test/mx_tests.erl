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

-module(mx_tests).

-include_lib("eunit/include/eunit.hrl").
-compile(export_all).

mx_test() ->
    % mnesia:dirty_select(mx_table_client, [{'_',[],['$_']}]).
    % mnesia:dirty_select(mx_table_defer, [{'_',[],['$_']}]).

    mx:register(client, "Client1").
    mx:register(client, "Client2").
    mx:register(client, "Client3").
    mx:register(client, "Client4").

    mx:register(channel, "Channel1", <<42,95,236,108,64,253,36,90,36,60,50,179,219,73,1,61,69>>).

    mx:subscribe(<<42,47,231,226,247,215,105,46,217,181,173,247,93,206,248,15,209>>, "Channel1").
    mx:subscribe(<<42,150,205,12,62,219,183,158,157,112,8,45,243,123,103,79,105>>, "Channel1").
    mx:subscribe(<<42,215,87,81,75,153,148,193,185,32,38,111,156,162,183,64,229>>, "Channel1").

    mx:register(pool, "Pool1", <<42,95,236,108,64,253,36,90,36,60,50,179,219,73,1,61,69>>).
    mx:join(<<42,47,231,226,247,215,105,46,217,181,173,247,93,206,248,15,209>>, "Pool1").
    mx:join(<<42,150,205,12,62,219,183,158,157,112,8,45,243,123,103,79,105>>, "Pool1").
    mx:join(<<42,215,87,81,75,153,148,193,185,32,38,111,156,162,183,64,229>>, "Pool1").

    mx:send(<<42,95,236,108,64,253,36,90,36,60,50,179,219,73,1,61,69>>, "hi body").
    mx:send(<<35,110,121,48,217,228,92,240,133,25,235,94,163,50,133,167,55>>, "hi channel").
    mx:send(<<64,92,61,224,106,0,184,142,80,34,47,10,105,152,188,54,23>>, "hi pool").

    ok.

