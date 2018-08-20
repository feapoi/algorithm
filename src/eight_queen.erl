-module(eight_queen).
-export([printf/0, attack_range/2, perms/1]).
-define(MaxQueen, 8).%寻找字符串所有可能的排列

%% @doc 在国际象棋棋盘中，n个皇后不能碰到

perms([]) ->
    [[]];
perms(L) ->
    [[H | T] || H <- L, T <- perms(L -- [H])].
%%perms([]) ->[[]];
%%perms(L) ->
%% [[H | T] || H <- L, T <- perms(L -- [H]), attack_range(H,T) == []].

printf() ->
    L = lists:seq(1, ?MaxQueen),
    io:format("~p~n", [?MaxQueen]),
    perms(L).

%检测出第一行的数字攻击到之后各行哪些数字%left向下行的左侧检测%right向下行的右侧检测
attack_range(Queen, List) ->attack_range(Queen, left, List) ++ attack_range(Queen, right, List).
attack_range(_, _, []) ->[];
attack_range(Queen, left, [H | _]) when Queen - 1 =:= H ->[H];
attack_range(Queen, right, [H | _]) when Queen + 1 =:= H ->[H];
attack_range(Queen, left, [_ | T]) ->attack_range(Queen - 1, left, T);
attack_range(Queen, right, [_ | T]) ->attack_range(Queen + 1, right, T).
