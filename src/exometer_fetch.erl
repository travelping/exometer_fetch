-module(exometer_fetch).

-export([fetch/1, fetch/2]).


fetch(Key) ->
    call(Key).

fetch(Key, Datapoint) ->
    call({Key, Datapoint}).

call(Request) ->
    exometer_report:call_reporter(exometer_report_fetch, {request, Request}).
