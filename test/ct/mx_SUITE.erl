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

-module(mx_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Function: suite() -> Info
%%
%% Info = [tuple()]
%%   List of key/value pairs.
%%
%% Description: Returns list of tuples to set default properties
%%              for the suite.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%--------------------------------------------------------------------
suite() ->
    [{timetrap,{seconds,30}}].

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the suite.
%%
%% Description: Initialization before the suite.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    % application:load(lager),
    % application:set_env(lager, handlers,
    %     [
    %         {lager_console_backend, info},
    %         {lager_file_backend, [{file, "/tmp/mx.run.log"}, {level, debug}]}
    %     ]
    % ),
    % application:ensure_all_started(lager),
    % application:ensure_all_started(mx),
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> term() | {save_config,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Cleanup after the suite.
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    % application:stop(mx),
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% GroupName = atom()
%%   Name of the test case group that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%% Reason = term()
%%   The reason for skipping all test cases and subgroups in the group.
%%
%% Description: Initialization before each test case group.
%%--------------------------------------------------------------------
init_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%               term() | {save_config,Config1}
%%
%% GroupName = atom()
%%   Name of the test case group that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%%
%% Description: Cleanup after each test case group.
%%--------------------------------------------------------------------
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% TestCase = atom()
%%   Name of the test case that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%%
%% Description: Initialization before each test case.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_testcase(TestCase, Config0) ->
%%               term() | {save_config,Config1} | {fail,Reason}
%%
%% TestCase = atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for failing the test case.
%%
%% Description: Cleanup after each test case.
%%--------------------------------------------------------------------
end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: groups() -> [Group]
%%
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%%   The name of the group.
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%%   Group properties that may be combined.
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%%   The name of a test case.
%% Shuffle = shuffle | {shuffle,Seed}
%%   To get cases executed in random order.
%% Seed = {integer(),integer(),integer()}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%%   To get execution of cases repeated.
%% N = integer() | forever
%%
%% Description: Returns a list of test case group definitions.
%%--------------------------------------------------------------------
groups() ->
    [
    {channel,[sequence], [
        channel_test_Clients_1_Messages_1
        % channel_test_Clients_1_Messages_1000
        % channel_test_Clients_1000_Messages_1
        % channel_test_Clients_1000_Messages_10
        ]},

    {channel,[parallel], [
        channel_test_Clients_1000_Messages_1,
        channel_test_Clients_1000_Messages_1,
        channel_test_Clients_1000_Messages_1,
        channel_test_Clients_1000_Messages_1,
        channel_test_Clients_1000_Messages_1
        % channel_test_Clients_1_Messages_1000
        % channel_test_Clients_1000_Messages_1
        % channel_test_Clients_1000_Messages_10
        ]},
    {pool, [sequence],[
        pool_test_1_1
        ]}
    ].



%%--------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases | {skip,Reason}
%%
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%%   Name of a test case group.
%% TestCase = atom()
%%   Name of a test case.
%% Reason = term()
%%   The reason for skipping all groups and test cases.
%%
%% Description: Returns the list of groups and test cases that
%%              are to be executed.
%%--------------------------------------------------------------------

all() ->
    [
    {group, channel}, % pub/sub
    {group, pool}     % workers pool
    ].


-define(MX(A,B),        gen_server:call({mx, 'mxnode01@127.0.0.1'}, {A,B})).
-define(MX(A,B,C),      gen_server:call({mx, 'mxnode01@127.0.0.1'}, {A,B,C})).
-define(MX(A,B,C,D),      gen_server:call({mx, 'mxnode01@127.0.0.1'}, {A,B,C,D})).

client(ID, ChannelKey, N, DonePid) ->
    Pid = erlang:spawn_link(fun() ->
            ClientName = lists:flatten(io_lib:format("client-~p-~p", [ID,self()])),
            ct:print("registering: ~p", [ClientName]),
            case ?MX(register_client, ClientName, [{monitor, true}]) of
                {duplicate, ClientKey} ->
                    ?MX(set, ClientKey, [{handler, self()}, {monitor, true}]);
                {clientkey, ClientKey} ->
                    pass
            end,
            ?MX(subscribe,ClientKey, ChannelKey),
            Loop = fun Loop(I) when N > I ->
                        receive
                            {'$gen_call', ReplyTo, _M} ->
                                gen_server:reply(ReplyTo, ok),
                                Loop(I);
                            {'$gen_cast', _M} ->
                                Loop(I);
                            {mx, M} ->
                                ct:print("GOT MX MESSAGE: (~p): ~p", [self(), M]),
                                Loop(I+1);
                            stop ->
                                ok;
                            M ->
                                ct:print("GOT UNKNOWN MESSAGE: (~p): ~p", [self(), M]),
                                Loop(I)
                        end;

                    Loop(_I) ->
                        DonePid ! {done, ID}

            end,
            DonePid ! {ready, ID},
            Loop(0)
       end),
    Pid.


channel_test(NumClients, NMessages) ->


    Finish = self(),
    DonePid = erlang:spawn_link(fun() ->
        F = fun Done(N,N) when N == NumClients->
                    Finish ! finish;
                Done(N,NDone) when N == NumClients, N > NDone ->
                    receive
                        {done, _ID} ->
                            Done(N, NDone+1)
                    after 25000 ->
                        Finish ! timeout_done
                    end;
                Done(N,_) ->
                    receive
                        {ready, _ID} when N == NumClients -1 ->
                            Finish ! ready,
                            Done(NumClients, 0);
                        {ready, _ID} ->
                            Done(N+1, 0)
                    after 5000 ->
                        Finish ! timeout_ready
                    end
        end,
        F(0,0)
    end),

    % create publisher
    ChannelName = lists:flatten(io_lib:format("Channel_test_~p", [self()])),
    PublisherName = lists:flatten(io_lib:format("Publisher_~p", [self()])),
    case ?MX(register_client, PublisherName, [{monitor, true}]) of
        {duplicate, PublisherClientKey} ->
            ?MX(set, PublisherClientKey, [{handler, self()}, {monitor, true}]);
        {clientkey, PublisherClientKey} ->
            pass
    end,
    {_, PublisherChannelKey} = ?MX(register_channel, ChannelName, PublisherClientKey, [{own, true}]),

    % create subscribers

    _Clients = [client(ID, ChannelName, NMessages, DonePid) || ID <- lists:seq(1,NumClients)],
    receive
        ready ->
            [?MX(send, PublisherChannelKey, "hello-"++integer_to_list(NM)) || NM <- lists:seq(1,NMessages)]
    end,

    ?assert(receive finish -> true; X -> X after 26000 -> timeout_finish end),
    ok.

channel_test_Clients_1_Messages_1(_X) ->
    % NumClients = 1, % NMessages = 1,
    channel_test(1, 1),
    ok.

channel_test_Clients_1_Messages_1000(_X) ->
    channel_test(1, 1000),
    ok.

channel_test_Clients_1000_Messages_1(_X) ->
    channel_test(1000, 1),
    ok.

channel_test_Clients_1000_Messages_10(_X) ->
    channel_test(1000, 10),
    ok.

pool_test_1_1(_X) ->
    ok.

% test1(_Config) ->
%     % mnesia:dirty_select(mx_table_client, [{'_',[],['$_']}]).
%     % mnesia:dirty_select(mx_table_defer, [{'_',[],['$_']}]).

%     mx:register(client, "Client1"),
%     mx:register(client, "Client2"),
%     mx:register(client, "Client3"),
%     mx:register(client, "Client4"),

%     mx:register(channel, "Channel1", <<42,95,236,108,64,253,36,90,36,60,50,179,219,73,1,61,69>>),

%     mx:subscribe(<<42,47,231,226,247,215,105,46,217,181,173,247,93,206,248,15,209>>, "Channel1"),
%     mx:subscribe(<<42,150,205,12,62,219,183,158,157,112,8,45,243,123,103,79,105>>, "Channel1"),
%     mx:subscribe(<<42,215,87,81,75,153,148,193,185,32,38,111,156,162,183,64,229>>, "Channel1"),

%     mx:register(pool, "Pool1", <<42,95,236,108,64,253,36,90,36,60,50,179,219,73,1,61,69>>),
%     mx:join(<<42,47,231,226,247,215,105,46,217,181,173,247,93,206,248,15,209>>, "Pool1"),
%     mx:join(<<42,150,205,12,62,219,183,158,157,112,8,45,243,123,103,79,105>>, "Pool1"),
%     mx:join(<<42,215,87,81,75,153,148,193,185,32,38,111,156,162,183,64,229>>, "Pool1"),

%     mx:send(<<42,95,236,108,64,253,36,90,36,60,50,179,219,73,1,61,69>>, "hi body"),
%     mx:send(<<35,110,121,48,217,228,92,240,133,25,235,94,163,50,133,167,55>>, "hi channel"),
%     mx:send(<<64,92,61,224,106,0,184,142,80,34,47,10,105,152,188,54,23>>, "hi pool"),

%     ok.
