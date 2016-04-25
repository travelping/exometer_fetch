-module(exometer_fetch_test).

-include_lib("eunit/include/eunit.hrl").

subscribtions_module_test() ->
    Subscribers =  [ 
                    {reporters, [{exometer_report_fetch, [{autosubscribe, true}, 
                                                          {subscriptions_module, exometer_fetch_subscribe_mod},
                                                          {key_prefix, <<"/metrics">>}]}]}],
    error_logger:tty(false),
    application:set_env(lager, handlers, [{lager_console_backend, none}]),
    application:set_env(exometer, report, Subscribers),
    {ok, Apps} = application:ensure_all_started(exometer_fetch),

    exometer:update_or_create([metric, test1], 1, histogram, []),
    exometer:update_or_create([metric, test2], 2, histogram, []),

    timer:sleep(100),
    ?assertEqual(3, length(exometer_report:list_subscriptions(exometer_report_fetch))),

    {ok, _} = exometer_fetch:fetch(<<"/metrics/my_key1">>),
    {ok, _} = exometer_fetch:fetch(<<"/metrics/my_key1">>, min),
    {ok, _} = exometer_fetch:fetch(<<"/metrics/my">>),

    [application:stop(App) || App <- Apps],
    ok.
