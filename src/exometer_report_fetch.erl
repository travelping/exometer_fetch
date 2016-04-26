-module(exometer_report_fetch).

-behaviour(exometer_report).

%% gen_server callbacks
-export([exometer_init/1,
         exometer_info/2,
         exometer_cast/2,
         exometer_call/3,
         exometer_report/5,
         exometer_subscribe/5,
         exometer_unsubscribe/4,
         exometer_newentry/2,
         exometer_setopts/4,
         exometer_terminate/2]).


-include_lib("exometer_core/include/exometer.hrl").

-define(DEFAULT_AUTOSUBSCRIBE, false).
-define(DEFAULT_SUBSCRIPTIONS_MOD, undefined).
-define(DEFAULT_KEY_PREFIX, <<"">>).

-record(state, {autosubscribe :: boolean(),
                subscriptions_module :: module(),
                subscriptions ::  map(),
                key_prefix :: binary()}).


%% ===================================================================
%% Public API
%% ===================================================================
exometer_init(Opts) ->
    Autosubscribe = proplists:get_value(autosubscribe, Opts, ?DEFAULT_AUTOSUBSCRIBE),
    SubscriptionsMod = proplists:get_value(subscriptions_module, Opts, ?DEFAULT_SUBSCRIPTIONS_MOD),
    KeyPrefix = proplists:get_value(key_prefix, Opts, ?DEFAULT_KEY_PREFIX),
    State = #state{autosubscribe = Autosubscribe,
                   subscriptions_module = SubscriptionsMod,
                   subscriptions = maps:new(),
                   key_prefix = KeyPrefix},
    {ok, State}.

exometer_subscribe(Metric, DataPoints, _Interval,
                   Opts, #state{subscriptions=Subscriptions,
                                key_prefix = Prefix} = State)
  when is_list(Opts) ->
    case proplists:get_value(key, Opts, undefined) of
        undefined ->
            {{error, key_missing}, State};
        Key when is_binary(Key) /= true ->
            {{error, key_not_binary}, State};
        Key ->
            PrefixKey = <<Prefix/binary, Key/binary>>,
            case maps:is_key(PrefixKey, Subscriptions) of
                true ->
                    {ok, State};
                false ->
                    DataPoints1 = case is_list(DataPoints) of
                                      true   -> DataPoints;
                                      false  -> [DataPoints]
                                  end,
                    NewSubscriptions = maps:put(PrefixKey, {Metric, DataPoints1}, Subscriptions),
                    {ok, State#state{subscriptions=NewSubscriptions}}
            end
    end;
exometer_subscribe(_Metric, _DataPoint, _Interval, _Opts, State) ->
    {{error, invalid_options}, State}.

exometer_unsubscribe(Metric, _DataPoint, _Extra, #state{subscriptions=Subscriptions} = State) ->
    Pred = fun(_Key, Value) ->
                   case Value of
                       {Metric, _} -> true;
                       _           -> false
                   end
           end,
    KeyToDelete = hd(maps:keys(maps:filter(Pred, Subscriptions))),
    NewSubscriptions = maps:remove(KeyToDelete, Subscriptions),
    {ok, State#state{subscriptions=NewSubscriptions}}.

exometer_call({request, {Key, DataPoint}}, _From, #state{subscriptions=Subscriptions} = State) ->
    {reply, get_metrics(Key, format_datapoint(DataPoint), Subscriptions), State};
exometer_call({request, Key}, From, State) ->
    exometer_call({request, {Key, undefined}}, From, State);
exometer_call(_Req, _From, State) ->
    {ok, State}.

exometer_newentry(#exometer_entry{name = Name, type = Type}, 
                  #state{autosubscribe = true,
                         subscriptions_module = Module} = State)
    when is_atom(Module); Module /= undefined ->
    subscribe(Module:subscribe(Name, Type)),
    {ok, State};
exometer_newentry(_Entry, State) ->
    {ok, State}.

exometer_report(_Metric, _DataPoint, _Extra, _Value, State) -> {ok, State}.
exometer_cast(_Unknown, State) -> {ok, State}.
exometer_info(_Info, State) -> {ok, State}.
exometer_setopts(_Metric, _Options, _Status, State) -> {ok, State}.
exometer_terminate(_Reason, _) -> ignore.


%% ===================================================================
%% Internal functions
%% ===================================================================
subscribe(Subscriptions) when is_list(Subscriptions) ->
    [subscribe(Subscription) || Subscription <- Subscriptions];
subscribe({Name, DataPoints, Extra}) ->
    exometer_report:subscribe(?MODULE, Name, DataPoints, manual, Extra, false);
subscribe(_Name) -> [].

binarize_list(List) when is_list(List) -> list_to_binary(List);
binarize_list(Term) -> Term.

format_datapoint(DP) when is_atom(DP) -> DP;
format_datapoint(DP) when is_list(DP) -> format_datapoint(list_to_binary(DP));
format_datapoint(<<"undefined">>) -> undefined;
format_datapoint(<<"">>) -> undefined;
format_datapoint(Binary) ->
    case re:run(Binary, "^[0-9]*$") of
        {match, _} -> binary_to_integer(Binary);
        _NoMatch   -> binary_to_atom(Binary, latin1)
    end.

get_metrics(Key, DataPoint, Subscriptions) ->
    case maps:get(Key, Subscriptions, undefined) of
        undefined when DataPoint =:= undefined ->
            find_metrics(Key, Subscriptions);
        undefined ->
            {error, not_found};
        MetricInfo when DataPoint =:= undefined ->
            proceed_single_metric(Key, MetricInfo, false);
        {Metric, DataPoints} ->
            case lists:member(DataPoint, DataPoints) of
                true ->
                    NewMetricInfo = {Metric, [DataPoint]},
                    case proceed_single_metric(Key, NewMetricInfo, false) of
                        {ok, [{_, FinalPayload}]} -> {ok, FinalPayload};
                        _Error -> {error, not_found}
                    end;
                false ->
                    {error, datapoint_not_found}
            end
    end.

proceed_single_metric(Key, {Metric, DataPoints}, KeyFlag) ->
    case exometer:get_value(Metric, DataPoints) of
        {ok, DataPointValues} ->
            DataPoints1 = [{DataPoint, binarize_list(Value)} ||
                           {DataPoint, Value} <- DataPointValues],
            Payload = maybe_add_more(Key, DataPoints1, KeyFlag),
            {ok, Payload};
        _Error ->
            {error, not_found}
    end.

maybe_add_more(_Key, DataPoints, false) -> DataPoints;
maybe_add_more(Key, DataPoints, true) ->
    [{key, Key}] ++ [{datapoints, DataPoints}].

find_metrics(Key, Subscriptions) ->
    PrefixKeys = get_prefix_keys(Key, maps:keys(Subscriptions)),
    Pred = fun(K,_V) -> lists:member(K, PrefixKeys) end,
    FilteredSubsciptions = maps:filter(Pred, Subscriptions),
    case accumulate_metrics(maps:to_list(FilteredSubsciptions)) of
        []      -> {error, not_found};
        Metrics -> {ok, Metrics}
    end.

get_prefix_keys(Key, Keys) ->
    ByteSize = byte_size(Key),
    [ SingleKey || SingleKey <- Keys, ByteSize==binary:longest_common_prefix([Key, SingleKey]) ].

accumulate_metrics(Subscriptions) ->
    accumulate_metrics(Subscriptions, []).

accumulate_metrics([], Metrics) -> Metrics;
accumulate_metrics([{Key, MetricInfo} | Subscriptions], Metrics) ->
    case proceed_single_metric(Key, MetricInfo, true) of
        {ok, Metric}     ->
            accumulate_metrics(Subscriptions, Metrics ++ [Metric]);
        {error, _Reason} ->
            accumulate_metrics(Subscriptions, Metrics)
    end.

