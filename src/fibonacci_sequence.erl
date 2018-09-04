%%%-------------------------------------------------------------------
%%% @author Thoe
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 九月 2018 19:21
%%%-------------------------------------------------------------------
-module(fibonacci_sequence).
-author("Thoe").

%% API
-export([fibonacci/1]).
fibonacci(1) -> [1];
fibonacci(2) -> [1, 1];
fibonacci(N) ->
    fibonacci(2, N, [1, 1], 1, 1).
fibonacci(N, N, List, F1, F2) -> lists:reverse(List);
fibonacci(N1, N2, List, F1, F2) ->
    fibonacci(N1 + 1, N2, [F1 + F2 | List], F1 + F2, F1).





