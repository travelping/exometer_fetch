-module(exometer_fetch_subscribe_mod).
-compile([export_all]).

subscribe([metric, test1] = Metric, histogram) ->
    Opts = [{key, <<"/my_key1">>}],
    {Metric, [min, max, median], Opts};
subscribe([metric, test2] = Metric, histogram) ->
    Opts1 = [{key, <<"/my_key2">>}],
    Opts2 = [{key, <<"/my_key3">>}],
    [{Metric, min, Opts1},
     {Metric, [max, median], Opts2}];
subscribe(_, _) -> [].
