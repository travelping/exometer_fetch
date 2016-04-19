# exometer_fetch [![Build Status](https://travis-ci.org/travelping/exometer_fetch.svg)](https://travis-ci.org/travelping/exometer_fetch)

This reporter acts as subscription handler such that other services (e.g. http server) can fetch metrics from it.

### Usage

Add exometer_fetch to your list of dependencies in rebar.config:

```erlang
{deps, [
    {exometer_fetch, ".*", {git, "https://github.com/travelping/exometer_fetch.git", "master"}}
]}.
```

Ensure exometer_fetch is started before your application:

```erlang
{applications, [exometer_fetch]}.
```

Configure it:


```erlang
{exometer,
    {reporters, [
        {exometer_report_fetch, [
            {autosubscribe, true},
            {subscriptions_module, exometer_fetch_subscribe_mod}
        ]}
    ]}
}.
```

It is possible to create a subscription automatically for each newly created metric entry. By default this is disabled. You can enable it in the reporter options.
You must also provide a callback module which handles the entries. Apart from that there are no further options.

The callback module may look like:

```erlang
-module(exometer_fetch_subscribe_mod).
-export([subscribe/2]).

subscribe([test, metric] = Metric, histogram) ->
    {Metric, [max, min], [{key, <<"some_key">>}]};
subscribe(_, _) -> [].
```

`subscribe/2` calls for each new entry and it should return a (possibly empty) list or just one subscription. Here a single subscription has the following layout:

```erlang
{exometer_report:metric(), exometer_report:datapoints(), exometer_report:extra()}
```

### Subscription examples:

```erlang
exometer_report:subscribe(exometer_report_fetch, [erlang, memory], total, manual, [{key, <<"some_key">>}]).
```

Check if everything is working:

```erlang
exometer_fetch:fetch(<<"some_key">>).
```

Further it is possible to return only the value of a specific datapoint:

```erlang
exometer_fetch:fetch(<<"some_key">>, total).
```

Keys always need to be given as binary. If a key is not found then all metrics which have this key as prefix will be returned (or an error if nothing is found).

#### About subscription time intervals:

The report interval in subscriptions should be set to `manual` such that the metric is actually never reported using time interval triggers.
The metric value will be retrieved from exometer directly when one sends a request to the corresponding key.

