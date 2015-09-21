# OTP Message Broker

## Overview

Universal OTP message broker allows to create channels (pub/sub), pools,
mixing it (pool of channels, channel of pools) and even create crazy complex messaging
(something like: pool of [pool of [...], clients, channels of [...]]).

You can set priority for message processing (range: 1..10).

Pool have 3 balance methods: rr(round robin), hash (by erlang:phash(Message, lenth(Pool))), random.

Message can be deferred on:

- exceed the queue limit (10000) and receiver has the 'true' in 'defer' option.

- client has 'offline' state and the 'defer' option is set to 'true'

You have to set 'async' Client option to 'false' for delivery control. Default value of this option is 'true'.

## Distributed mode

    Set via environment value of 'master'to run it in slave mode.
```erlang
    % on mxnode01@127.0.0.1
    application:start(mx).
```
```erlang
    % on mxnode02@127.0.0.1
    application:load(mx),
    application:set_env(mx, master, 'mxnode01@127.0.0.1'),
    application:start(mx).
```

now you can call mx:nodes() to get list of mx cluster nodes.

## API

### local use

* Create client/channel/pool

    **mx:register(client, Name)**  
    **mx:register(client, Name, Opts)**  
    Name - list or binary  
    Opts - proplists  
    returns: {clientkey, Key}  
                   {duplicate, Key}
            Key - binary

    **mx:register(channel, Name, ClientKey)**  
    **mx:register(channel, Name, ClientKey, Opts)**  
          Name - list or binary  
          Opts - proplists  
          ClientKey - binary  
          returns: {channelkey, Key}  
                   {duplicate, Key}

    **mx:register(pool, Name, ClientKey)**  
    **mx:register(pool, Name, ClientKey, Opts)**  
          Name - list or binary  
          Opts - proplists  
          ClientKey - binary  
          returns: {poolkey, Key}  
                   {duplicate, Key}  

* Delete client/channel/pool  
    **mx:unregister(Key)**

* Work with channel/pool  
    **mx:subscribe(Key, Channel)**  
    **mx:unsubscribe(Key, Channel)**  
          Key - binary (ClientKey, ChannelKey, PoolKey)  
          Channel - channel name or channel key

    **mx:join(Key, Pool)**  
    **mx:leave(key, Pool)**  
          Key - binary (ClientKey, ChannelKey, PoolKey)  
          Pool - pool name or pool key

* Set options for client/channel/pool  
    **mx:set(Key, Opts)**  
          Key - binary (ClientKey, ChannelKey, PoolKey)  
          Opts - proplists

    **mx:info(Key)**  
          Key - binary (ClientKey, ChannelKey, PoolKey)

* Sending message  
  **mx:send(ClientKey, Message)**  
  **mx:send(ChannelKey, Message)**  
  **mx:send(PoolKey, Message)**

* Clear deferred messages  
    **mx:flush(Key)**  
        Key - binary (ClientKey, ChannelKey, PoolKey)  
        all - truncate the 'deferred' table

* Info  
    **mx:nodes()**  
        show MX cluster nodes

### remote use

You have to use **gen_server:call(Node, Message)**, where
**Node** is atom like 'mx@nodename' and **Message** is one of listed values below:
- {register_client, Client}
- {register_client, Client, Opts}
- {register_channel, ChannelName, ClientKey}
- {register_channel, ChannelName, ClientKey, Opts}
- {register_pool, PoolName, ClientKey}
- {register_pool, PoolName, ClientKey, Opts}
- {unregister, Key}
- {subscribe, Client, To}
- {unsubscribe, Client, From}
- {join, Client, To}
- {leave, Client, From}
- {send, To, Message}
- {info, Key}
- {set, Key, Opts}
- nodes

## Examples

```erlang

    % Client has higest priority by default (priority = 1)
    {clientkey, Client1Key} = mx:register(client, "Client1"),
    {clientkey, Client2Key} = mx:register(client, "Client2", [{priority, 8}]),
    {clientkey, Client3Key} = mx:register(client, "Client3", [{async, false}, {defer, true}]),
    {clientkey, Client4Key} = mx:register(client, "Client4"),

    % register channel with default priority (5)
    {channelkey, Channel1Key} = mx:register(channel, "Channel1", Client4Key),
    ok = mx:subscribe(Client1Key, Channel1Key),
    % just for example try to subscribe one more time
    {already_subscribed, Client1Key} = mx:subscribe(Client1Key, Channel1Key),

    ok = mx:subscribe(Client2Key, Channel1Key),
    ok = mx:subscribe(Client3Key, Channel1Key),

    mx:send(Channel1Key, "Hello, Channel1!").

    % register pool with default balance method is 'rr' - round robin
    %                    default priority (5)
    {poolkey, Pool1Key} = mx:register(pool, "Pool1", Client4Key),
    mx:join(Client1Key, Pool1Key),
    mx:join(Client2Key, Pool1Key),
    mx:join(Client3Key, Pool1Key),

    % create lowest priority channel and pool by Client2
    {channelkey, LPCh1} = mx:register(channel, "LP Channel1", Client2Key, [{priority, 10}]),
    {poolkey, LPPl1}    = mx:register(pool, "LP Pool1", Client2Key, [{priority, 10}]),

    % create highest priority channel and pool by Client3
    {channelkey, HPCh1} = mx:register(channel, "HP Channel1", Client2Key, [{priority, 1}]),
    {poolkey, HPPl1}    = mx:register(pool, "HP Pool1", Client2Key, [{priority, 1}]),

    % high priority pool with 'hash' balance
    {poolkey, HP_Hash_Pl}    = mx:register(pool, "HP Pool (hash)", Client2Key, [{priority, 1}, {balance, hash}]),

    % pool with random balance
    {poolkey, Rand_Pl}    = mx:register(pool, "Pool (random) ", Client2Key, [balance, hash}]),

```

