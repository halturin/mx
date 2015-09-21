# OTP Message Broker

## Overview
    Universal OTP messaging broker allows create channels (pub/sub), pools,
    mixing it (pool of channels, channel of pools) and even crazy complex messaging
    (something like: pool of [pool of [...], clients, channels of [...]]).

    You can set priority for message processing (range: 1..10).

    Pool have 3 balance methods: rr(round robin), hash (by erlang:phash(Message, lenth(Pool))), random.

    Message can be deferred on:

    1) exceed the queue limit (10000) and receiver has the 'true' in 'defer' option.

    2) client has 'offline' state and the 'defer' option is set to 'true'


## API

* Create client/channel/pool
      register(client, Name),
      register(client, Name, Opts),
          Name - list or binary
          Opts - proplists
          returns: {clientkey, Key}
                   {duplicate, Key}
               Key - binary

      register(channel, Name, ClientKey)
      register(channel, Name, ClientKey, Opts)
          Name - list or binary
          Opts - proplists
          ClientKey - binary
          returns: {channelkey, Key}
                   {duplicate, Key}

      register(pool, Name, ClientKey)
      register(pool, Name, ClientKey, Opts)
          Name - list or binary
          Opts - proplists
          ClientKey - binary
          returns: {poolkey, Key}
                   {duplicate, Key}

* Delete client/channel/pool
    unregister(Key)

* Work with channel/pool
      subscribe(Key, Channel)
      unsubscribe(Key, Channel)
          Key - binary (ClientKey, ChannelKey, PoolKey)
          Channel - channel name or channel key

      join(Key, Pool)
      leave(key, Pool)
          Key - binary (ClientKey, ChannelKey, PoolKey)
          Pool - pool name or pool key

* Set options for client/channel/pool
      set(Key, Opts)
          Key - binary (ClientKey, ChannelKey, PoolKey)
          Opts - proplists

      info(Key)
          Key - binary (ClientKey, ChannelKey, PoolKey)

* Sending message
      mx:send(ClientKey, Message)    - unicast message
      mx:send(ChannelKey, Message)   - muilticast
      mx:send(PoolKey, Message)      - pooled unicast message

* Clear deferred messages
    mx:flush(Key)
          Key - binary (ClientKey, ChannelKey, PoolKey)
          all - truncate the 'deferred' table

* Naming keys
    prefix + md5(Name)
    ClientKey  = <<$*, ClientHash/binary>>
    ChannelKey = <<$#, ChannelHash/binary>>
    PoolKey    = <<$@, PoolHash/binary>>

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

